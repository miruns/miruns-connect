import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/body_blog_entry.dart';
import '../../../core/models/capture_entry.dart';
import '../../../core/services/research_export_service.dart';
import '../../../core/services/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../sport/models/workout_session.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Export screen — unified data export hub.
//
// Lets the user select a date range and pick which data categories to
// include, then bundles everything into a single ZIP-like share flow.
// ─────────────────────────────────────────────────────────────────────────────

/// Which data categories the user can toggle for export.
enum _DataCategory {
  captures(
    'Captures',
    Icons.camera_rounded,
    'Health, environment, location snapshots',
  ),
  eegSessions(
    'EEG Sessions',
    Icons.waves_rounded,
    'Raw signal recordings from BLE sources',
  ),
  heartRate(
    'Heart Rate',
    Icons.favorite_rounded,
    'BLE HR streams & workout HR data',
  ),
  workouts(
    'Workouts',
    Icons.directions_run_rounded,
    'GPS, HR, EEG band-power, insights',
  ),
  journal('Journal', Icons.auto_stories_outlined, 'Body blog daily entries'),
  health(
    'Health Data',
    Icons.monitor_heart_outlined,
    'Steps, sleep, calories, HRV from OS',
  );

  final String label;
  final IconData icon;
  final String description;

  const _DataCategory(this.label, this.icon, this.description);
}

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  // Date range
  late DateTime _from;
  late DateTime _to;

  // Category toggles
  final _enabled = <_DataCategory, bool>{
    for (final c in _DataCategory.values) c: true,
  };

  // Format
  ExportFormat _format = ExportFormat.csv;

  // Loading / export state
  bool _loading = false;
  bool _scanning = true;
  String? _error;

  // Data counts (populated by _scan)
  int _captureCount = 0;
  int _eegCount = 0;
  int _hrCount = 0;
  int _workoutCount = 0;
  int _journalCount = 0;
  bool _healthAvailable = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 30));
    _to = DateTime(now.year, now.month, now.day);
    _scan();
  }

  // ── Scan the database for available data in the selected range ──────────

  Future<void> _scan() async {
    setState(() => _scanning = true);

    try {
      final db = ref.read(localDbServiceProvider);
      final workoutService = ref.read(workoutServiceProvider);
      final healthService = ref.read(healthServiceProvider);

      // Captures in range
      final captures = await db.loadCapturesInRange(_from, _to);
      int eeg = 0, hr = 0;
      for (final c in captures) {
        if (c.signalSession != null) eeg++;
        if (c.bleHrSession != null) hr++;
      }

      // Journal entries in range
      final entries = await db.loadEntriesInRange(_from, _to);

      // Workouts — load all and filter by date
      final allWorkouts = await workoutService.loadWorkouts();
      final rangeWorkouts = allWorkouts.where((w) {
        return !w.startTime.isBefore(_from) &&
            !w.startTime.isAfter(_to.add(const Duration(days: 1)));
      }).toList();

      // Also count workout HR data
      for (final w in rangeWorkouts) {
        if (w.hrSamples.isNotEmpty) hr++;
        if (w.eegSamples.isNotEmpty) eeg++;
      }

      // Health availability
      final hasHealth = await healthService.isHealthAvailable();

      if (!mounted) return;
      setState(() {
        _captureCount = captures.length;
        _eegCount = eeg;
        _hrCount = hr;
        _workoutCount = rangeWorkouts.length;
        _journalCount = entries.length;
        _healthAvailable = hasHealth;
        _scanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = 'Scan failed: $e';
      });
    }
  }

  int _countFor(_DataCategory cat) {
    switch (cat) {
      case _DataCategory.captures:
        return _captureCount;
      case _DataCategory.eegSessions:
        return _eegCount;
      case _DataCategory.heartRate:
        return _hrCount;
      case _DataCategory.workouts:
        return _workoutCount;
      case _DataCategory.journal:
        return _journalCount;
      case _DataCategory.health:
        return _healthAvailable ? -1 : 0; // -1 = available but uncountable
    }
  }

  // ── Export logic ────────────────────────────────────────────────────────

  Future<void> _export() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = ref.read(localDbServiceProvider);
      final workoutService = ref.read(workoutServiceProvider);
      final healthService = ref.read(healthServiceProvider);
      final exportService = ResearchExportService();

      final files = <File>[];
      final parts = <String>[];

      // ── Captures (with optional EEG & HR inline) ──────────────────────
      if (_enabled[_DataCategory.captures]! ||
          _enabled[_DataCategory.eegSessions]! ||
          _enabled[_DataCategory.heartRate]!) {
        final captures = await db.loadCapturesInRange(_from, _to);

        // If user wants individual capture exports
        if (_enabled[_DataCategory.captures]!) {
          final f = await _capturesToCsv(captures);
          files.add(f);
          parts.add('${captures.length} captures');
        }

        // Individual EEG/HR exports via ResearchExportService
        for (final capture in captures) {
          final hasEeg =
              _enabled[_DataCategory.eegSessions]! &&
              capture.signalSession != null;
          final hasHr =
              _enabled[_DataCategory.heartRate]! &&
              capture.bleHrSession != null;
          if (hasEeg || hasHr) {
            final result = await exportService.exportCapture(
              capture,
              format: _format,
              options: ExportOptions(
                includeEeg: hasEeg,
                includeHr: hasHr,
                includeGps: false,
                includeEnvironment: false,
                includeMetadata: false,
              ),
            );
            files.addAll(result.files);
          }
        }
      }

      // ── Workouts ──────────────────────────────────────────────────────
      if (_enabled[_DataCategory.workouts]!) {
        final allWorkouts = await workoutService.loadWorkouts();
        final rangeWorkouts = allWorkouts.where((w) {
          return !w.startTime.isBefore(_from) &&
              !w.startTime.isAfter(_to.add(const Duration(days: 1)));
        }).toList();

        if (rangeWorkouts.isNotEmpty) {
          // Summary CSV
          final f = await _workoutsToCsv(rangeWorkouts);
          files.add(f);
          parts.add('${rangeWorkouts.length} workouts');

          // Individual detailed exports
          for (final w in rangeWorkouts) {
            final result = await exportService.exportWorkout(
              w,
              format: _format,
              options: ExportOptions(
                includeEeg: _enabled[_DataCategory.eegSessions]!,
                includeHr: _enabled[_DataCategory.heartRate]!,
                includeGps: true,
                includeEnvironment: false,
                includeMetadata: true,
              ),
            );
            files.addAll(result.files);
          }
        }
      }

      // ── Journal entries ───────────────────────────────────────────────
      if (_enabled[_DataCategory.journal]!) {
        final entries = await db.loadEntriesInRange(_from, _to);
        if (entries.isNotEmpty) {
          final f = await _journalToCsv(entries);
          files.add(f);
          parts.add('${entries.length} journal entries');
        }
      }

      // ── Platform Health data ──────────────────────────────────────────
      if (_enabled[_DataCategory.health]! && _healthAvailable) {
        final healthData = await healthService.getHealthData(
          startTime: _from,
          endTime: _to.add(const Duration(days: 1)),
        );
        if (healthData.isNotEmpty) {
          final f = await _healthToCsv(healthData);
          files.add(f);
          parts.add('${healthData.length} health data points');
        }
      }

      if (files.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No data to export in this date range.';
        });
        return;
      }

      // Share
      await Share.shareXFiles(
        files.map((f) => XFile(f.path)).toList(),
        subject:
            'Miruns Export — ${DateFormat.yMMMd().format(_from)} to ${DateFormat.yMMMd().format(_to)}',
        text: 'Miruns data export: ${parts.join(", ")}',
      );

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Export failed: $e';
        });
      }
    }
  }

  // ── CSV writers ─────────────────────────────────────────────────────────

  Future<File> _capturesToCsv(List<CaptureEntry> captures) async {
    final buf = StringBuffer();
    buf.writeln(
      'id,timestamp,source,mood,steps,heart_rate,calories,'
      'sleep_hours,distance,temperature,humidity,aqi,'
      'latitude,longitude,battery,has_eeg,has_hr,tags',
    );

    for (final c in captures) {
      final h = c.healthData;
      final e = c.environmentData;
      final l = c.locationData;
      buf.writeln(
        [
          c.id,
          c.timestamp.toIso8601String(),
          c.source.name,
          c.userMood ?? '',
          h?.steps ?? '',
          h?.heartRate ?? '',
          h?.calories?.toStringAsFixed(1) ?? '',
          h?.sleepHours?.toStringAsFixed(1) ?? '',
          h?.distance?.toStringAsFixed(2) ?? '',
          e?.temperature?.toStringAsFixed(1) ?? '',
          e?.humidity ?? '',
          e?.aqi ?? '',
          l?.latitude.toStringAsFixed(5) ?? '',
          l?.longitude.toStringAsFixed(5) ?? '',
          c.batteryLevel ?? '',
          c.signalSession != null ? '1' : '0',
          c.bleHrSession != null ? '1' : '0',
          '"${c.tags.join(", ")}"',
        ].join(','),
      );
    }

    return _writeFile('miruns_captures_export.csv', buf.toString());
  }

  Future<File> _workoutsToCsv(List<WorkoutSession> workouts) async {
    final buf = StringBuffer();
    buf.writeln(
      'id,start_time,end_time,type,duration_min,distance_km,'
      'avg_speed_kmh,max_speed_kmh,avg_hr,max_hr,min_hr,avg_hrv_ms,'
      'calories,avg_attention,avg_mental_fatigue,hr_samples,eeg_samples,gps_points',
    );

    for (final w in workouts) {
      final dur = w.endTime != null
          ? w.endTime!.difference(w.startTime).inMinutes
          : 0;
      buf.writeln(
        [
          w.id,
          w.startTime.toIso8601String(),
          w.endTime?.toIso8601String() ?? '',
          w.workoutType.name,
          dur,
          w.totalDistanceKm?.toStringAsFixed(2) ?? '',
          w.avgSpeedKmh?.toStringAsFixed(1) ?? '',
          w.maxSpeedKmh?.toStringAsFixed(1) ?? '',
          w.avgHr ?? '',
          w.maxHr ?? '',
          w.minHr ?? '',
          w.avgHrvMs?.toStringAsFixed(1) ?? '',
          w.caloriesBurned ?? '',
          w.avgAttention?.toStringAsFixed(1) ?? '',
          w.avgMentalFatigue?.toStringAsFixed(1) ?? '',
          w.hrSamples.length,
          w.eegSamples.length,
          w.gpsSamples.length,
        ].join(','),
      );
    }

    return _writeFile('miruns_workouts_export.csv', buf.toString());
  }

  Future<File> _journalToCsv(List<BodyBlogEntry> entries) async {
    final buf = StringBuffer();
    buf.writeln('date,headline,mood,mood_emoji,tags,summary');

    for (final e in entries) {
      buf.writeln(
        [
          e.date,
          '"${_escapeCsv(e.headline)}"',
          '"${_escapeCsv(e.mood)}"',
          e.moodEmoji,
          '"${e.tags.join(", ")}"',
          '"${_escapeCsv(e.summary)}"',
        ].join(','),
      );
    }

    return _writeFile('miruns_journal_export.csv', buf.toString());
  }

  Future<File> _healthToCsv(List<dynamic> data) async {
    final buf = StringBuffer();
    buf.writeln('type,value,unit,date_from,date_to,source');

    for (final d in data) {
      buf.writeln(
        [
          d.type.name,
          d.value,
          d.unit,
          d.dateFrom.toIso8601String(),
          d.dateTo.toIso8601String(),
          d.sourceName,
        ].join(','),
      );
    }

    return _writeFile('miruns_health_export.csv', buf.toString());
  }

  String _escapeCsv(String s) => s.replaceAll('"', '""').replaceAll('\n', ' ');

  Future<File> _writeFile(String name, String content) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    return file.writeAsString(content);
  }

  // ── Date picker ─────────────────────────────────────────────────────────

  Future<void> _pickDateRange() async {
    final c = context.miruns;
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppTheme.cyan,
              onPrimary: Colors.black,
              surface: AppTheme.deepSea,
              onSurface: c.textStrong,
            ),
          ),
          child: child!,
        );
      },
    );

    if (result != null) {
      setState(() {
        _from = result.start;
        _to = result.end;
      });
      _scan();
    }
  }

  // ── Quick date range presets ────────────────────────────────────────────

  void _setPreset(int days) {
    final now = DateTime.now();
    setState(() {
      _from = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: days));
      _to = DateTime(now.year, now.month, now.day);
    });
    _scan();
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.miruns;
    final fmt = DateFormat.yMMMd();

    final anyEnabled = _enabled.values.any((v) => v);
    final anyData =
        _captureCount > 0 ||
        _workoutCount > 0 ||
        _journalCount > 0 ||
        _healthAvailable;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Export Data',
          style: AppTheme.geist(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: c.textStrong,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: c.textStrong),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        children: [
          // ── Date range ──────────────────────────────────────────────
          _SectionLabel('DATE RANGE'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickDateRange,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: c.tintFaint,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.date_range_rounded,
                    size: 18,
                    color: AppTheme.cyan,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${fmt.format(_from)}  →  ${fmt.format(_to)}',
                      style: AppTheme.geist(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.textStrong,
                      ),
                    ),
                  ),
                  Icon(Icons.edit_rounded, size: 16, color: c.textMuted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Quick presets
          Row(
            children: [
              _PresetChip('7 days', () => _setPreset(7)),
              const SizedBox(width: 8),
              _PresetChip('30 days', () => _setPreset(30)),
              const SizedBox(width: 8),
              _PresetChip('90 days', () => _setPreset(90)),
              const SizedBox(width: 8),
              _PresetChip('All', () => _setPreset(365 * 3)),
            ],
          ),
          const SizedBox(height: 28),

          // ── Data categories ─────────────────────────────────────────
          _SectionLabel('DATA TO EXPORT'),
          const SizedBox(height: 8),
          if (_scanning)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.cyan,
                  ),
                ),
              ),
            )
          else
            ..._DataCategory.values.map((cat) {
              final count = _countFor(cat);
              final available = count != 0;
              return _CategoryTile(
                category: cat,
                count: count,
                enabled: _enabled[cat]! && available,
                available: available,
                onChanged: available
                    ? (v) => setState(() => _enabled[cat] = v)
                    : null,
              );
            }),

          const SizedBox(height: 28),

          // ── Format ──────────────────────────────────────────────────
          _SectionLabel('FORMAT'),
          const SizedBox(height: 8),
          Row(
            children: ExportFormat.values.map((f) {
              final selected = f == _format;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: f != ExportFormat.values.last ? 8 : 0,
                  ),
                  child: GestureDetector(
                    onTap: () => setState(() => _format = f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.cyan.withValues(alpha: 0.12)
                            : c.tintFaint,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? AppTheme.cyan : c.border,
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            f.label,
                            style: AppTheme.geist(
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: selected ? AppTheme.cyan : c.textBody,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            f.extension.toUpperCase(),
                            style: AppTheme.geistMono(
                              fontSize: 10,
                              color: c.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Text(
            _format.description,
            style: AppTheme.geist(
              fontSize: 11,
              color: c.textMuted,
              height: 1.4,
            ),
          ),

          // ── Error ───────────────────────────────────────────────────
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.crimson.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.crimson.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: AppTheme.crimson,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: AppTheme.geist(
                        fontSize: 12,
                        color: AppTheme.crimson,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: c.border, width: 0.5)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _loading || _scanning || !anyEnabled || !anyData
                  ? null
                  : _export,
              icon: _loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.ios_share_rounded, size: 18),
              label: Text(
                _loading ? 'Exporting…' : 'Export & Share',
                style: AppTheme.geist(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.cyan,
                foregroundColor: Colors.black,
                disabledBackgroundColor: c.tintSubtle,
                disabledForegroundColor: c.textMuted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Reusable widgets ─────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTheme.geist(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: context.miruns.textSubtle,
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.miruns;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: c.tintFaint,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.borderSubtle),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTheme.geist(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c.textBody,
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.count,
    required this.enabled,
    required this.available,
    this.onChanged,
  });

  final _DataCategory category;
  final int count;
  final bool enabled;
  final bool available;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.miruns;
    final countLabel = count < 0
        ? 'available'
        : count == 0
        ? 'none'
        : '$count';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: available ? () => onChanged?.call(!enabled) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: enabled
                ? AppTheme.cyan.withValues(alpha: 0.06)
                : c.tintFaint,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled
                  ? AppTheme.cyan.withValues(alpha: 0.25)
                  : c.borderSubtle,
            ),
          ),
          child: Row(
            children: [
              Icon(
                category.icon,
                size: 18,
                color: enabled
                    ? AppTheme.cyan
                    : available
                    ? c.textMuted
                    : c.textFaint,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.label,
                      style: AppTheme.geist(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: available ? c.textStrong : c.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category.description,
                      style: AppTheme.geist(fontSize: 11, color: c.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: count > 0
                      ? AppTheme.seaGreen.withValues(alpha: 0.12)
                      : count < 0
                      ? AppTheme.cyan.withValues(alpha: 0.10)
                      : c.tintSubtle,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  countLabel,
                  style: AppTheme.geistMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: count > 0
                        ? AppTheme.seaGreen
                        : count < 0
                        ? AppTheme.cyan
                        : c.textFaint,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: enabled,
                  onChanged: available ? (v) => onChanged?.call(v!) : null,
                  activeColor: AppTheme.cyan,
                  side: BorderSide(
                    color: available ? c.textMuted : c.textFaint,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(3),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
