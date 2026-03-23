import 'package:flutter/material.dart';

import '../ble_source_provider.dart';

/// Miruns 4-channel EEG headset source provider.
///
/// Uses the same TI ADS1299 ADC as the 8-channel variant but with a
/// 4-channel electrode montage designed for the Miruns headset.
///
/// ### Protocol
/// - BLE service UUID: `0000fe42-8e22-4541-9d4c-21edae82ed19`
/// - Notification characteristic: same UUID (single-characteristic design)
/// - Each notification: 60 bytes → 5 samples × 4 channels × 3 bytes
///   (big-endian, 24-bit two's complement)
/// - Voltage formula: `µV = 1_000_000 × 4.5 × (raw_signed / 16_777_215)`
class Miruns4ChSource extends BleSourceProvider {
  // ── Identity ────────────────────────────────────────────────────────

  @override
  String get id => 'miruns_4ch';

  @override
  String get displayName => 'Miruns 4-Ch EEG';

  @override
  String get description =>
      'Miruns EEG headset — 4 channels, 24-bit, 250 SPS. '
      'Based on the TI ADS1299 front-end.';

  @override
  IconData get icon => Icons.headset;

  @override
  List<String> get advertisedNames => ['EAREEG'];

  // ── BLE identifiers ────────────────────────────────────────────────

  @override
  String get serviceUuid => '0000fe42-8e22-4541-9d4c-21edae82ed19';

  @override
  String get notifyCharacteristicUuid => '0000fe42-8e22-4541-9d4c-21edae82ed19';

  // ── Channel layout ─────────────────────────────────────────────────

  /// Standard 10-20 electrode labels for a 4-channel montage.
  static const _labels = ['Fp1', 'Fp2', 'O1', 'O2'];

  @override
  List<ChannelDescriptor> get channelDescriptors => List.generate(
    4,
    (i) => ChannelDescriptor(
      label: _labels[i],
      unit: 'µV',
      defaultScale: 100, // ±100 µV autoscale window
    ),
  );

  @override
  double get sampleRateHz => 250;

  // ── Data parsing ───────────────────────────────────────────────────

  /// Reference voltage (V) of the ADS1299.
  static const double _vRef = 4.5;

  /// Full-scale positive value for 24-bit ADC.
  static const int _fullScale = 16777215; // 2^24 - 1

  /// Midpoint for unsigned→signed conversion (bit 23 set).
  static const int _signBit = 0x800000; // 2^23

  /// Bytes per single sample: 4 channels × 3 bytes.
  static const int _bytesPerSample = 12;

  @override
  List<SignalSample> parseNotification(List<int> data) {
    // Need at least one full sample (12 bytes).
    if (data.length < _bytesPerSample) return const [];

    final sampleCount = data.length ~/ _bytesPerSample;
    final now = DateTime.now();
    final samples = <SignalSample>[];

    for (var s = 0; s < sampleCount; s++) {
      final base = s * _bytesPerSample;
      final channels = <double>[];
      for (var ch = 0; ch < 4; ch++) {
        final offset = base + ch * 3;
        // Big-endian 24-bit unsigned assembly.
        int raw =
            (data[offset] << 16) | (data[offset + 1] << 8) | data[offset + 2];

        // Two's complement sign extension to signed 24-bit.
        if (raw >= _signBit) {
          raw -= _fullScale + 1; // 2^24
        }

        // Convert to microvolts.
        final uv = 1000000.0 * _vRef * (raw / _fullScale);
        channels.add(double.parse(uv.toStringAsFixed(2)));
      }

      // Space timestamps evenly across the batch based on sample rate.
      final offsetMicros = (s * 1000000 ~/ sampleRateHz.round());
      samples.add(
        SignalSample(
          time: now.subtract(
            Duration(microseconds: (sampleCount - 1 - s) * offsetMicros),
          ),
          channels: channels,
        ),
      );
    }

    return samples;
  }
}
