import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../features/sport/models/workout_session.dart';
import '../models/capture_entry.dart';
import 'ble_heart_rate_service.dart';
import 'ble_source_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Research-grade export formats for EEG, HR, and multi-sensor data.
//
// Supports:
//   • CSV  — universal, any ML pipeline can ingest it
//   • EDF+ — European Data Format (gold standard for EEG/polysomnography)
//   • JSON — BrainFlow-compatible structured export
// ─────────────────────────────────────────────────────────────────────────────

/// Available research export formats.
enum ExportFormat {
  csv('CSV', 'csv', 'Comma-separated values — universal ML compatibility'),
  edfPlus(
    'EDF+',
    'edf',
    'European Data Format — standard for EEG research tools (MNE-Python, EEGLAB)',
  ),
  json('JSON', 'json', 'Structured JSON — BrainFlow / programmatic access');

  final String label;
  final String extension;
  final String description;

  const ExportFormat(this.label, this.extension, this.description);
}

/// What data streams to include in the export.
class ExportOptions {
  final bool includeEeg;
  final bool includeHr;
  final bool includeGps;
  final bool includeEnvironment;
  final bool includeMetadata;

  const ExportOptions({
    this.includeEeg = true,
    this.includeHr = true,
    this.includeGps = true,
    this.includeEnvironment = true,
    this.includeMetadata = true,
  });
}

/// Result of an export operation.
class ExportResult {
  final List<File> files;
  final String summary;

  const ExportResult({required this.files, required this.summary});
}

/// Service that exports capture and workout data in research-grade formats.
class ResearchExportService {
  static final _ts = DateFormat('yyyyMMdd_HHmmss');

  /// Export a [CaptureEntry] (with optional SignalSession + BleHrSession).
  Future<ExportResult> exportCapture(
    CaptureEntry capture, {
    ExportFormat format = ExportFormat.csv,
    ExportOptions options = const ExportOptions(),
  }) async {
    final prefix = 'miruns_capture_${_ts.format(capture.timestamp)}';
    final files = <File>[];
    final parts = <String>[];

    if (options.includeEeg && capture.signalSession != null) {
      final f = await _exportSignalSession(
        capture.signalSession!,
        format,
        prefix,
        capture.timestamp,
      );
      files.add(f);
      parts.add('EEG (${capture.signalSession!.channelCount}ch)');
    }

    if (options.includeHr && capture.bleHrSession != null) {
      final f = await _exportHrSession(
        capture.bleHrSession!,
        format,
        prefix,
        capture.timestamp,
      );
      files.add(f);
      parts.add('HR (${capture.bleHrSession!.samples.length} samples)');
    }

    if (options.includeMetadata) {
      final f = await _exportCaptureMetadata(capture, prefix);
      files.add(f);
      parts.add('metadata');
    }

    return ExportResult(
      files: files,
      summary: parts.isEmpty
          ? 'No exportable data in this capture'
          : 'Exported ${parts.join(", ")}',
    );
  }

  /// Export a [WorkoutSession] with all recorded time-series.
  Future<ExportResult> exportWorkout(
    WorkoutSession workout, {
    ExportFormat format = ExportFormat.csv,
    ExportOptions options = const ExportOptions(),
  }) async {
    final prefix = 'miruns_workout_${_ts.format(workout.startTime)}';
    final files = <File>[];
    final parts = <String>[];

    if (options.includeEeg && workout.eegSamples.isNotEmpty) {
      final f = await _exportWorkoutEeg(workout, format, prefix);
      files.add(f);
      parts.add('EEG bands (${workout.eegSamples.length} samples)');
    }

    if (options.includeHr && workout.hrSamples.isNotEmpty) {
      final f = await _exportWorkoutHr(workout, format, prefix);
      files.add(f);
      parts.add('HR (${workout.hrSamples.length} samples)');
    }

    if (options.includeGps && workout.gpsSamples.isNotEmpty) {
      final f = await _exportWorkoutGps(workout, format, prefix);
      files.add(f);
      parts.add('GPS (${workout.gpsSamples.length} points)');
    }

    if (options.includeMetadata) {
      final f = await _exportWorkoutMetadata(workout, prefix);
      files.add(f);
      parts.add('metadata');
    }

    return ExportResult(
      files: files,
      summary: parts.isEmpty
          ? 'No exportable data in this workout'
          : 'Exported ${parts.join(", ")}',
    );
  }

  /// Share the exported files via the native share sheet.
  Future<void> shareFiles(ExportResult result) async {
    if (result.files.isEmpty) return;
    await Share.shareXFiles(
      result.files.map((f) => XFile(f.path)).toList(),
      subject: 'Miruns Research Export',
      text: result.summary,
    );
  }

  // ── Signal Session (raw EEG) ───────────────────────────────────────────

  Future<File> _exportSignalSession(
    SignalSession session,
    ExportFormat format,
    String prefix,
    DateTime captureTime,
  ) async {
    switch (format) {
      case ExportFormat.csv:
        return _signalSessionToCsv(session, prefix);
      case ExportFormat.edfPlus:
        return _signalSessionToEdf(session, prefix, captureTime);
      case ExportFormat.json:
        return _signalSessionToJson(session, prefix);
    }
  }

  Future<File> _signalSessionToCsv(SignalSession session, String prefix) async {
    final buf = StringBuffer();

    // Header comment block
    buf.writeln('# Miruns Research Export — Raw Signal Data');
    buf.writeln('# Source: ${session.sourceName}');
    if (session.deviceName != null) {
      buf.writeln('# Device: ${session.deviceName}');
    }
    buf.writeln('# Sample Rate: ${session.sampleRateHz} Hz');
    buf.writeln('# Channels: ${session.channelCount}');
    buf.writeln('# Duration: ${session.duration.inSeconds}s');
    buf.writeln('# Samples: ${session.samples.length}');
    buf.writeln('#');

    // Column header
    final labels = session.channels.map((c) => '${c.label} (${c.unit})');
    buf.writeln('timestamp_us,elapsed_s,${labels.join(",")}');

    // Data rows
    final t0 = session.samples.isNotEmpty
        ? session.samples.first.time.microsecondsSinceEpoch
        : 0;

    for (final s in session.samples) {
      final us = s.time.microsecondsSinceEpoch;
      final elapsed = (us - t0) / 1e6;
      buf.write('$us,${elapsed.toStringAsFixed(6)}');
      for (final v in s.channels) {
        buf.write(',${v.toStringAsFixed(4)}');
      }
      buf.writeln();
    }

    return _writeFile('${prefix}_eeg.csv', buf.toString());
  }

  Future<File> _signalSessionToEdf(
    SignalSession session,
    String prefix,
    DateTime startDate,
  ) async {
    // EDF+ specification: https://www.edfplus.info/specs/edfplus.html
    // We write a standard EDF file (continuous) with digital range mapping.

    final nChannels = session.channelCount;
    final nSamples = session.samples.length;
    if (nChannels == 0 || nSamples == 0) {
      return _writeFile('${prefix}_eeg.edf', '');
    }

    // Determine physical min/max per channel from actual data
    final physMin = List<double>.filled(nChannels, double.infinity);
    final physMax = List<double>.filled(nChannels, double.negativeInfinity);

    for (final s in session.samples) {
      for (var ch = 0; ch < nChannels; ch++) {
        if (s.channels[ch] < physMin[ch]) physMin[ch] = s.channels[ch];
        if (s.channels[ch] > physMax[ch]) physMax[ch] = s.channels[ch];
      }
    }

    // Ensure non-zero range
    for (var ch = 0; ch < nChannels; ch++) {
      if (physMin[ch] == physMax[ch]) {
        physMin[ch] -= 1;
        physMax[ch] += 1;
      }
    }

    // EDF uses 16-bit integers: digital range -32768 to 32767
    const digMin = -32768;
    const digMax = 32767;

    // Data records: 1 second each
    final sampleRate = session.sampleRateHz.round();
    final totalDurationSec = (nSamples / sampleRate).ceil();
    final nDataRecords = totalDurationSec > 0 ? totalDurationSec : 1;
    final samplesPerRecord = sampleRate; // 1 second of data per record

    // ── Build EDF header ──
    final headerBytes = 256 + nChannels * 256;
    final header = Uint8List(headerBytes);

    void writeField(int offset, int length, String value) {
      final padded = value.padRight(length);
      for (var i = 0; i < length; i++) {
        header[offset + i] = i < padded.length ? padded.codeUnitAt(i) : 0x20;
      }
    }

    // Main header (256 bytes)
    writeField(0, 8, '0'); // version
    writeField(8, 80, 'X X X X'); // patient ID (anonymized)
    writeField(
      88,
      80,
      'Startdate ${DateFormat('dd-MMM-yyyy').format(startDate).toUpperCase()} X miruns X',
    );
    writeField(168, 8, DateFormat('dd.MM.yy').format(startDate));
    writeField(176, 8, DateFormat('HH.mm.ss').format(startDate));
    writeField(184, 8, headerBytes.toString());
    writeField(192, 44, 'EDF+C'); // reserved (EDF+ continuous)
    writeField(236, 8, nDataRecords.toString());
    writeField(244, 8, '1'); // duration of each data record in seconds
    writeField(252, 4, nChannels.toString());

    // Per-channel headers (nChannels × 256 bytes total, interleaved fields)
    var off = 256;

    // Labels (16 bytes each)
    for (var ch = 0; ch < nChannels; ch++) {
      writeField(off + ch * 16, 16, session.channels[ch].label);
    }
    off += nChannels * 16;

    // Transducer type (80 bytes each)
    for (var ch = 0; ch < nChannels; ch++) {
      writeField(off + ch * 80, 80, 'EEG electrode');
    }
    off += nChannels * 80;

    // Physical dimension / unit (8 bytes each)
    for (var ch = 0; ch < nChannels; ch++) {
      writeField(off + ch * 8, 8, session.channels[ch].unit);
    }
    off += nChannels * 8;

    // Physical minimum (8 bytes each)
    for (var ch = 0; ch < nChannels; ch++) {
      writeField(off + ch * 8, 8, physMin[ch].toStringAsFixed(1));
    }
    off += nChannels * 8;

    // Physical maximum (8 bytes each)
    for (var ch = 0; ch < nChannels; ch++) {
      writeField(off + ch * 8, 8, physMax[ch].toStringAsFixed(1));
    }
    off += nChannels * 8;

    // Digital minimum (8 bytes each)
    for (var ch = 0; ch < nChannels; ch++) {
      writeField(off + ch * 8, 8, digMin.toString());
    }
    off += nChannels * 8;

    // Digital maximum (8 bytes each)
    for (var ch = 0; ch < nChannels; ch++) {
      writeField(off + ch * 8, 8, digMax.toString());
    }
    off += nChannels * 8;

    // Pre-filtering (80 bytes each)
    for (var ch = 0; ch < nChannels; ch++) {
      writeField(off + ch * 80, 80, 'None');
    }
    off += nChannels * 80;

    // Number of samples in each data record (8 bytes each)
    for (var ch = 0; ch < nChannels; ch++) {
      writeField(off + ch * 8, 8, samplesPerRecord.toString());
    }
    off += nChannels * 8;

    // Reserved (32 bytes each)
    for (var ch = 0; ch < nChannels; ch++) {
      writeField(off + ch * 32, 32, '');
    }

    // ── Build data records ──
    // Each record: nChannels × samplesPerRecord × 2 bytes (16-bit ints, little-endian)
    final recordSize = nChannels * samplesPerRecord * 2;
    final dataBytes = Uint8List(nDataRecords * recordSize);
    final dataView = ByteData.view(dataBytes.buffer);

    for (var rec = 0; rec < nDataRecords; rec++) {
      for (var ch = 0; ch < nChannels; ch++) {
        for (var s = 0; s < samplesPerRecord; s++) {
          final sampleIdx = rec * samplesPerRecord + s;
          int digitalValue;
          if (sampleIdx < nSamples) {
            // Linear scaling: physical → digital
            final phys = session.samples[sampleIdx].channels[ch];
            final scaled =
                (phys - physMin[ch]) /
                    (physMax[ch] - physMin[ch]) *
                    (digMax - digMin) +
                digMin;
            digitalValue = scaled.round().clamp(digMin, digMax);
          } else {
            digitalValue = 0; // pad with zeros
          }
          final byteOffset =
              rec * recordSize + ch * samplesPerRecord * 2 + s * 2;
          dataView.setInt16(byteOffset, digitalValue, Endian.little);
        }
      }
    }

    // Combine header + data
    final edfBytes = Uint8List(header.length + dataBytes.length);
    edfBytes.setAll(0, header);
    edfBytes.setAll(header.length, dataBytes);

    return _writeBinaryFile('${prefix}_eeg.edf', edfBytes);
  }

  Future<File> _signalSessionToJson(
    SignalSession session,
    String prefix,
  ) async {
    final data = {
      'format': 'miruns_research_v1',
      'source': {
        'id': session.sourceId,
        'name': session.sourceName,
        'device': session.deviceName,
        'sample_rate_hz': session.sampleRateHz,
      },
      'channels': session.channels
          .map(
            (c) => {
              'label': c.label,
              'unit': c.unit,
              'default_scale': c.defaultScale,
            },
          )
          .toList(),
      'recording': {
        'duration_seconds': session.duration.inMilliseconds / 1000,
        'total_samples': session.samples.length,
        'start_time': session.samples.isNotEmpty
            ? session.samples.first.time.toIso8601String()
            : null,
        'end_time': session.samples.isNotEmpty
            ? session.samples.last.time.toIso8601String()
            : null,
      },
      'data': {
        'timestamps_us': session.samples
            .map((s) => s.time.microsecondsSinceEpoch)
            .toList(),
        'channels': List.generate(
          session.channelCount,
          (ch) => session.samples.map((s) => s.channels[ch]).toList(),
        ),
      },
    };

    // Use compute to avoid blocking UI for large datasets
    final jsonStr = await compute(_encodeJson, data);
    return _writeFile('${prefix}_eeg.json', jsonStr);
  }

  // ── HR Session ────────────────────────────────────────────────────────

  Future<File> _exportHrSession(
    BleHrSession session,
    ExportFormat format,
    String prefix,
    DateTime captureTime,
  ) async {
    switch (format) {
      case ExportFormat.csv:
        return _hrSessionToCsv(session, prefix);
      case ExportFormat.edfPlus:
        // EDF+ for HR — single channel BPM + RR annotations
        return _hrSessionToCsv(
          session,
          prefix,
        ); // CSV fallback; HR is better as CSV
      case ExportFormat.json:
        return _hrSessionToJson(session, prefix);
    }
  }

  Future<File> _hrSessionToCsv(BleHrSession session, String prefix) async {
    final buf = StringBuffer();

    buf.writeln('# Miruns Research Export — Heart Rate Data');
    if (session.deviceName != null) {
      buf.writeln('# Device: ${session.deviceName}');
    }
    buf.writeln('# Duration: ${session.duration.inSeconds}s');
    buf.writeln('# Samples: ${session.samples.length}');
    if (session.hrv != null) {
      buf.writeln('# HRV RMSSD: ${session.hrv!.rmssd?.toStringAsFixed(2)} ms');
      buf.writeln('# HRV SDNN: ${session.hrv!.sdnn?.toStringAsFixed(2)} ms');
      buf.writeln('# Mean RR: ${session.hrv!.meanRr?.toStringAsFixed(2)} ms');
    }
    buf.writeln('#');

    // BPM time series
    buf.writeln('timestamp_ms,elapsed_s,bpm');
    final t0 = session.samples.isNotEmpty
        ? session.samples.first.time.millisecondsSinceEpoch
        : 0;

    for (final s in session.samples) {
      final ms = s.time.millisecondsSinceEpoch;
      final elapsed = (ms - t0) / 1000;
      buf.writeln('$ms,${elapsed.toStringAsFixed(3)},${s.bpm}');
    }

    // RR intervals section
    if (session.rrMs.isNotEmpty) {
      buf.writeln();
      buf.writeln('# RR Intervals (milliseconds)');
      buf.writeln('rr_interval_ms');
      for (final rr in session.rrMs) {
        buf.writeln(rr.toStringAsFixed(2));
      }
    }

    return _writeFile('${prefix}_hr.csv', buf.toString());
  }

  Future<File> _hrSessionToJson(BleHrSession session, String prefix) async {
    final data = {
      'format': 'miruns_research_v1',
      'type': 'heart_rate',
      'device': session.deviceName,
      'recording': {
        'duration_seconds': session.duration.inMilliseconds / 1000,
        'total_samples': session.samples.length,
      },
      'hrv': session.hrv != null
          ? {
              'rmssd_ms': session.hrv!.rmssd,
              'sdnn_ms': session.hrv!.sdnn,
              'mean_rr_ms': session.hrv!.meanRr,
              'stress_hint': session.hrv!.stressHint,
            }
          : null,
      'bpm_series': {
        'timestamps_ms': session.samples
            .map((s) => s.time.millisecondsSinceEpoch)
            .toList(),
        'bpm': session.samples.map((s) => s.bpm).toList(),
      },
      'rr_intervals_ms': session.rrMs,
    };

    final jsonStr = await compute(_encodeJson, data);
    return _writeFile('${prefix}_hr.json', jsonStr);
  }

  // ── Workout exports ───────────────────────────────────────────────────

  Future<File> _exportWorkoutEeg(
    WorkoutSession workout,
    ExportFormat format,
    String prefix,
  ) async {
    if (format == ExportFormat.json) {
      return _workoutEegToJson(workout, prefix);
    }
    // CSV for both csv and edf (band powers are derived, not raw waveforms)
    return _workoutEegToCsv(workout, prefix);
  }

  Future<File> _workoutEegToCsv(WorkoutSession w, String prefix) async {
    final buf = StringBuffer();
    buf.writeln('# Miruns Research Export — Workout EEG Band Powers');
    buf.writeln('# Workout Type: ${w.workoutType.label}');
    buf.writeln('# Start: ${w.startTime.toIso8601String()}');
    if (w.endTime != null) {
      buf.writeln('# End: ${w.endTime!.toIso8601String()}');
    }
    buf.writeln('# Samples: ${w.eegSamples.length}');
    buf.writeln('#');

    buf.writeln(
      'timestamp_iso,elapsed_s,attention,relaxation,cognitive_load,mental_fatigue,'
      'delta_pct,theta_pct,alpha_pct,beta_pct,gamma_pct,dominant_hz',
    );

    final t0 = w.startTime.millisecondsSinceEpoch;
    for (final s in w.eegSamples) {
      final elapsed = (s.timestamp.millisecondsSinceEpoch - t0) / 1000;
      buf.writeln(
        '${s.timestamp.toIso8601String()},${elapsed.toStringAsFixed(3)},'
        '${s.attention.toStringAsFixed(4)},${s.relaxation.toStringAsFixed(4)},'
        '${s.cognitiveLoad.toStringAsFixed(4)},${s.mentalFatigue.toStringAsFixed(4)},'
        '${s.deltaPct?.toStringAsFixed(4) ?? ""},${s.thetaPct?.toStringAsFixed(4) ?? ""},'
        '${s.alphaPct?.toStringAsFixed(4) ?? ""},${s.betaPct?.toStringAsFixed(4) ?? ""},'
        '${s.gammaPct?.toStringAsFixed(4) ?? ""},${s.dominantHz?.toStringAsFixed(2) ?? ""}',
      );
    }

    return _writeFile('${prefix}_eeg_bands.csv', buf.toString());
  }

  Future<File> _workoutEegToJson(WorkoutSession w, String prefix) async {
    final data = {
      'format': 'miruns_research_v1',
      'type': 'workout_eeg_bands',
      'workout_type': w.workoutType.name,
      'start_time': w.startTime.toIso8601String(),
      'end_time': w.endTime?.toIso8601String(),
      'samples': w.eegSamples
          .map(
            (s) => {
              'timestamp': s.timestamp.toIso8601String(),
              'attention': s.attention,
              'relaxation': s.relaxation,
              'cognitive_load': s.cognitiveLoad,
              'mental_fatigue': s.mentalFatigue,
              'delta_pct': s.deltaPct,
              'theta_pct': s.thetaPct,
              'alpha_pct': s.alphaPct,
              'beta_pct': s.betaPct,
              'gamma_pct': s.gammaPct,
              'dominant_hz': s.dominantHz,
            },
          )
          .toList(),
    };

    final jsonStr = await compute(_encodeJson, data);
    return _writeFile('${prefix}_eeg_bands.json', jsonStr);
  }

  Future<File> _exportWorkoutHr(
    WorkoutSession workout,
    ExportFormat format,
    String prefix,
  ) async {
    if (format == ExportFormat.json) {
      return _workoutHrToJson(workout, prefix);
    }
    return _workoutHrToCsv(workout, prefix);
  }

  Future<File> _workoutHrToCsv(WorkoutSession w, String prefix) async {
    final buf = StringBuffer();
    buf.writeln('# Miruns Research Export — Workout Heart Rate');
    buf.writeln('# Workout Type: ${w.workoutType.label}');
    buf.writeln('# Start: ${w.startTime.toIso8601String()}');
    buf.writeln('#');

    buf.writeln('timestamp_iso,elapsed_s,bpm,rr_ms');
    final t0 = w.startTime.millisecondsSinceEpoch;
    for (final s in w.hrSamples) {
      final elapsed = (s.timestamp.millisecondsSinceEpoch - t0) / 1000;
      buf.writeln(
        '${s.timestamp.toIso8601String()},${elapsed.toStringAsFixed(3)},'
        '${s.bpm},${s.rrMs?.toStringAsFixed(2) ?? ""}',
      );
    }

    return _writeFile('${prefix}_hr.csv', buf.toString());
  }

  Future<File> _workoutHrToJson(WorkoutSession w, String prefix) async {
    final data = {
      'format': 'miruns_research_v1',
      'type': 'workout_hr',
      'workout_type': w.workoutType.name,
      'start_time': w.startTime.toIso8601String(),
      'end_time': w.endTime?.toIso8601String(),
      'summary': {
        'avg_bpm': w.avgHr,
        'max_bpm': w.maxHr,
        'min_bpm': w.minHr,
        'avg_hrv_ms': w.avgHrvMs,
      },
      'samples': w.hrSamples
          .map(
            (s) => {
              'timestamp': s.timestamp.toIso8601String(),
              'bpm': s.bpm,
              'rr_ms': s.rrMs,
            },
          )
          .toList(),
    };

    final jsonStr = await compute(_encodeJson, data);
    return _writeFile('${prefix}_hr.json', jsonStr);
  }

  Future<File> _exportWorkoutGps(
    WorkoutSession workout,
    ExportFormat format,
    String prefix,
  ) async {
    if (format == ExportFormat.json) {
      return _workoutGpsToJson(workout, prefix);
    }
    return _workoutGpsToCsv(workout, prefix);
  }

  Future<File> _workoutGpsToCsv(WorkoutSession w, String prefix) async {
    final buf = StringBuffer();
    buf.writeln('# Miruns Research Export — Workout GPS Track');
    buf.writeln('# Workout Type: ${w.workoutType.label}');
    buf.writeln('#');

    buf.writeln(
      'timestamp_iso,elapsed_s,latitude,longitude,altitude_m,speed_kmh',
    );
    final t0 = w.startTime.millisecondsSinceEpoch;
    for (final s in w.gpsSamples) {
      final elapsed = (s.timestamp.millisecondsSinceEpoch - t0) / 1000;
      buf.writeln(
        '${s.timestamp.toIso8601String()},${elapsed.toStringAsFixed(3)},'
        '${s.lat.toStringAsFixed(7)},${s.lon.toStringAsFixed(7)},'
        '${s.altitudeM.toStringAsFixed(1)},${s.speedKmh.toStringAsFixed(2)}',
      );
    }

    return _writeFile('${prefix}_gps.csv', buf.toString());
  }

  Future<File> _workoutGpsToJson(WorkoutSession w, String prefix) async {
    final data = {
      'format': 'miruns_research_v1',
      'type': 'workout_gps',
      'workout_type': w.workoutType.name,
      'total_distance_km': w.totalDistanceKm,
      'avg_speed_kmh': w.avgSpeedKmh,
      'max_speed_kmh': w.maxSpeedKmh,
      'track': w.gpsSamples
          .map(
            (s) => {
              'timestamp': s.timestamp.toIso8601String(),
              'lat': s.lat,
              'lon': s.lon,
              'altitude_m': s.altitudeM,
              'speed_kmh': s.speedKmh,
            },
          )
          .toList(),
    };

    final jsonStr = await compute(_encodeJson, data);
    return _writeFile('${prefix}_gps.json', jsonStr);
  }

  // ── Metadata exports ──────────────────────────────────────────────────

  Future<File> _exportCaptureMetadata(
    CaptureEntry capture,
    String prefix,
  ) async {
    final meta = {
      'format': 'miruns_research_v1',
      'type': 'capture_metadata',
      'capture_id': capture.id,
      'timestamp': capture.timestamp.toIso8601String(),
      'source': capture.source.name,
      'trigger': capture.trigger?.name,
      'battery_level': capture.batteryLevel,
      'user_mood': capture.userMood,
      'user_note': capture.userNote,
      'tags': capture.tags,
      if (capture.healthData != null)
        'health': {
          'steps': capture.healthData!.steps,
          'calories': capture.healthData!.calories,
          'distance_m': capture.healthData!.distance,
          'heart_rate_bpm': capture.healthData!.heartRate,
          'sleep_hours': capture.healthData!.sleepHours,
        },
      if (capture.environmentData != null)
        'environment': {
          'temperature_c': capture.environmentData!.temperature,
          'aqi': capture.environmentData!.aqi,
          'uv_index': capture.environmentData!.uvIndex,
          'humidity_pct': capture.environmentData!.humidity,
          'wind_speed': capture.environmentData!.windSpeed,
          'pressure': capture.environmentData!.pressure,
          'conditions': capture.environmentData!.conditions,
          'description': capture.environmentData!.weatherDescription,
        },
      if (capture.locationData != null)
        'location': {
          'latitude': capture.locationData!.latitude,
          'longitude': capture.locationData!.longitude,
          'altitude_m': capture.locationData!.altitude,
          'accuracy_m': capture.locationData!.accuracy,
          'city': capture.locationData!.city,
          'region': capture.locationData!.region,
          'country': capture.locationData!.country,
        },
      if (capture.signalSession != null)
        'signal_session_info': {
          'source_id': capture.signalSession!.sourceId,
          'source_name': capture.signalSession!.sourceName,
          'device': capture.signalSession!.deviceName,
          'sample_rate_hz': capture.signalSession!.sampleRateHz,
          'channel_count': capture.signalSession!.channelCount,
          'total_samples': capture.signalSession!.samples.length,
          'duration_seconds':
              capture.signalSession!.duration.inMilliseconds / 1000,
        },
      if (capture.bleHrSession != null)
        'hr_session_info': {
          'device': capture.bleHrSession!.deviceName,
          'total_samples': capture.bleHrSession!.samples.length,
          'duration_seconds':
              capture.bleHrSession!.duration.inMilliseconds / 1000,
          'avg_bpm': capture.bleHrSession!.avgBpm,
          'min_bpm': capture.bleHrSession!.minBpm,
          'max_bpm': capture.bleHrSession!.maxBpm,
          'hrv': capture.bleHrSession!.hrv != null
              ? {
                  'rmssd_ms': capture.bleHrSession!.hrv!.rmssd,
                  'sdnn_ms': capture.bleHrSession!.hrv!.sdnn,
                  'mean_rr_ms': capture.bleHrSession!.hrv!.meanRr,
                }
              : null,
        },
    };

    final jsonStr = await compute(_encodeJson, meta);
    return _writeFile('${prefix}_metadata.json', jsonStr);
  }

  Future<File> _exportWorkoutMetadata(
    WorkoutSession workout,
    String prefix,
  ) async {
    final meta = {
      'format': 'miruns_research_v1',
      'type': 'workout_metadata',
      'workout_id': workout.id,
      'workout_type': workout.workoutType.name,
      'start_time': workout.startTime.toIso8601String(),
      'end_time': workout.endTime?.toIso8601String(),
      'duration_seconds': workout.duration.inSeconds,
      'metrics': {
        'total_distance_km': workout.totalDistanceKm,
        'avg_speed_kmh': workout.avgSpeedKmh,
        'max_speed_kmh': workout.maxSpeedKmh,
        'avg_hr_bpm': workout.avgHr,
        'max_hr_bpm': workout.maxHr,
        'min_hr_bpm': workout.minHr,
        'avg_hrv_ms': workout.avgHrvMs,
        'calories_burned': workout.caloriesBurned,
        'avg_attention': workout.avgAttention,
        'avg_mental_fatigue': workout.avgMentalFatigue,
      },
      'data_availability': {
        'eeg_samples': workout.eegSamples.length,
        'hr_samples': workout.hrSamples.length,
        'gps_samples': workout.gpsSamples.length,
        'insights': workout.insights.length,
      },
      if (workout.feedback != null)
        'user_feedback': {
          'fatigue_level': workout.feedback!.fatigueLevel,
          'energy_level': workout.feedback!.energyLevel,
          'rpe': workout.feedback!.rpe,
          'mood': workout.feedback!.moodEmoji,
          'note': workout.feedback!.note,
        },
      if (workout.analysis != null)
        'ai_analysis': {
          'performance_score': workout.analysis!.performanceScore,
          'fatigue_assessment': workout.analysis!.fatigueAssessment,
          'recovery_recommendation': workout.analysis!.recoveryRecommendation,
          'estimated_recovery_minutes':
              workout.analysis!.estimatedRecoveryTime.inMinutes,
          'eeg_insight': workout.analysis!.eegInsight,
        },
    };

    final jsonStr = await compute(_encodeJson, meta);
    return _writeFile('${prefix}_metadata.json', jsonStr);
  }

  // ── File I/O helpers ──────────────────────────────────────────────────

  Future<File> _writeFile(String fileName, String content) async {
    final dir = await _exportDir();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content);
    return file;
  }

  Future<File> _writeBinaryFile(String fileName, Uint8List bytes) async {
    final dir = await _exportDir();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<Directory> _exportDir() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/miruns_exports');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// JSON encode in isolate (avoids jank for large datasets).
  static String _encodeJson(Map<String, dynamic> data) {
    final encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(data);
  }
}
