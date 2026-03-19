import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:miruns_flutter/core/services/ble_heart_rate_service.dart';

void main() {
  // ── BleHrSample ────────────────────────────────────────────────────────

  group('BleHrSample', () {
    test('toJson / fromJson round-trip', () {
      final t = DateTime.now();
      final sample = BleHrSample(time: t, bpm: 72);
      final json = sample.toJson();
      final restored = BleHrSample.fromJson(json);
      expect(restored.bpm, 72);
      // millisecondsSinceEpoch round-trip truncates microseconds
      expect(
        restored.time.millisecondsSinceEpoch,
        t.millisecondsSinceEpoch,
      );
    });

    test('toJson uses millisecondsSinceEpoch', () {
      final t = DateTime.utc(2026, 3, 18);
      final json = BleHrSample(time: t, bpm: 60).toJson();
      expect(json['t'], t.millisecondsSinceEpoch);
      expect(json['b'], 60);
    });
  });

  // ── BleHrvMetrics ──────────────────────────────────────────────────────

  group('BleHrvMetrics', () {
    test('toJson / fromJson round-trip', () {
      const hrv = BleHrvMetrics(rmssd: 45.0, sdnn: 52.0, meanRr: 830.0);
      final json = hrv.toJson();
      final restored = BleHrvMetrics.fromJson(json);
      expect(restored.rmssd, 45.0);
      expect(restored.sdnn, 52.0);
      expect(restored.meanRr, 830.0);
    });

    test('fromJson handles null values', () {
      final restored = BleHrvMetrics.fromJson(<String, dynamic>{});
      expect(restored.rmssd, isNull);
      expect(restored.sdnn, isNull);
      expect(restored.meanRr, isNull);
    });

    test('fromJson coerces int to double', () {
      final restored = BleHrvMetrics.fromJson({
        'rmssd': 45,
        'sdnn': 52,
        'mean_rr': 830,
      });
      expect(restored.rmssd, 45.0);
      expect(restored.sdnn, 52.0);
      expect(restored.meanRr, 830.0);
    });

    group('stressHint', () {
      test('returns unknown when rmssd is null', () {
        const hrv = BleHrvMetrics();
        expect(hrv.stressHint, 'unknown');
      });

      test('returns relaxed for rmssd >= 50', () {
        const hrv = BleHrvMetrics(rmssd: 50.0);
        expect(hrv.stressHint, 'relaxed / parasympathetic-dominant');
      });

      test('returns moderate for rmssd >= 30', () {
        const hrv = BleHrvMetrics(rmssd: 30.0);
        expect(hrv.stressHint, 'moderate autonomic balance');
      });

      test('returns mild stress for rmssd >= 15', () {
        const hrv = BleHrvMetrics(rmssd: 15.0);
        expect(hrv.stressHint, 'mild stress / active');
      });

      test('returns high stress for rmssd < 15', () {
        const hrv = BleHrvMetrics(rmssd: 10.0);
        expect(hrv.stressHint, 'high stress / sympathetic-dominant');
      });
    });

    group('compute', () {
      test('returns null for fewer than 3 intervals', () {
        expect(BleHrvMetrics.compute([]), isNull);
        expect(BleHrvMetrics.compute([800.0]), isNull);
        expect(BleHrvMetrics.compute([800.0, 810.0]), isNull);
      });

      test('computes correctly for 3 constant intervals', () {
        // All RR = 800 ms → diffs = 0, RMSSD = 0, SDNN = 0
        final hrv = BleHrvMetrics.compute([800.0, 800.0, 800.0]);
        expect(hrv, isNotNull);
        expect(hrv!.rmssd, 0.0);
        expect(hrv.sdnn, 0.0);
        expect(hrv.meanRr, 800.0);
      });

      test('computes RMSSD for alternating intervals', () {
        // [800, 900, 800, 900] → diffs = [100, -100, 100]
        // sumSqDiff = 10000 + 10000 + 10000 = 30000
        // RMSSD = sqrt(30000 / 3) = sqrt(10000) = 100
        final hrv = BleHrvMetrics.compute([800, 900, 800, 900]);
        expect(hrv, isNotNull);
        expect(hrv!.rmssd, closeTo(100.0, 0.001));
      });

      test('computes SDNN correctly', () {
        // [800, 900, 800, 900] → mean = 850
        // deviations = [-50, 50, -50, 50]
        // sumSqDev = 2500*4 = 10000
        // SDNN = sqrt(10000/4) = sqrt(2500) = 50
        final hrv = BleHrvMetrics.compute([800, 900, 800, 900]);
        expect(hrv!.sdnn, closeTo(50.0, 0.001));
      });

      test('computes meanRr correctly', () {
        final hrv = BleHrvMetrics.compute([800, 850, 900]);
        expect(hrv!.meanRr, closeTo(850.0, 0.001));
      });

      test('handles realistic RR intervals', () {
        // Typical resting HR ~70 bpm → RR ~857 ms
        final rrMs = [857.0, 862.0, 849.0, 870.0, 845.0, 860.0, 855.0];
        final hrv = BleHrvMetrics.compute(rrMs);
        expect(hrv, isNotNull);
        expect(hrv!.rmssd, greaterThan(0));
        expect(hrv.sdnn, greaterThan(0));
        expect(hrv.meanRr, closeTo(856.86, 0.1));
      });

      test('RMSSD matches manual computation for known values', () {
        // [1000, 1020, 990] → diffs = [20, -30]
        // sumSqDiff = 400 + 900 = 1300
        // RMSSD = sqrt(1300 / 2) = sqrt(650) ≈ 25.495
        final hrv = BleHrvMetrics.compute([1000.0, 1020.0, 990.0]);
        expect(hrv!.rmssd, closeTo(math.sqrt(650), 0.001));
      });
    });
  });

  // ── BleHrSession ───────────────────────────────────────────────────────

  group('BleHrSession', () {
    final t0 = DateTime.utc(2026, 3, 18, 10, 0, 0);
    final t1 = DateTime.utc(2026, 3, 18, 10, 0, 1);
    final t2 = DateTime.utc(2026, 3, 18, 10, 0, 2);
    final t3 = DateTime.utc(2026, 3, 18, 10, 0, 3);

    BleHrSession makeSession({
      List<BleHrSample>? samples,
      List<double>? rrMs,
      BleHrvMetrics? hrv,
      String? deviceName,
    }) {
      return BleHrSession(
        samples: samples ??
            [
              BleHrSample(time: t0, bpm: 70),
              BleHrSample(time: t1, bpm: 72),
              BleHrSample(time: t2, bpm: 75),
              BleHrSample(time: t3, bpm: 68),
            ],
        rrMs: rrMs ?? [857.0, 833.0, 800.0, 882.0],
        hrv: hrv ?? const BleHrvMetrics(rmssd: 35.0, sdnn: 42.0, meanRr: 843.0),
        deviceName: deviceName ?? 'Polar H10',
      );
    }

    test('encode / decode round-trip', () {
      final session = makeSession();
      final encoded = session.encode();
      final decoded = BleHrSession.decode(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.samples.length, 4);
      expect(decoded.samples[0].bpm, 70);
      expect(decoded.rrMs.length, 4);
      expect(decoded.hrv!.rmssd, 35.0);
      expect(decoded.deviceName, 'Polar H10');
    });

    test('decode returns null for null input', () {
      expect(BleHrSession.decode(null), isNull);
    });

    test('decode returns null for malformed JSON', () {
      expect(BleHrSession.decode('not-json'), isNull);
    });

    test('minBpm returns smallest BPM', () {
      final session = makeSession();
      expect(session.minBpm, 68);
    });

    test('maxBpm returns largest BPM', () {
      final session = makeSession();
      expect(session.maxBpm, 75);
    });

    test('avgBpm returns average BPM rounded', () {
      // (70 + 72 + 75 + 68) / 4 = 71.25 → 71
      final session = makeSession();
      expect(session.avgBpm, 71);
    });

    test('minBpm / maxBpm / avgBpm return null for empty samples', () {
      final session = makeSession(samples: [], rrMs: []);
      expect(session.minBpm, isNull);
      expect(session.maxBpm, isNull);
      expect(session.avgBpm, isNull);
    });

    test('duration returns difference between first and last sample', () {
      final session = makeSession();
      expect(session.duration, const Duration(seconds: 3));
    });

    test('duration returns zero for single sample', () {
      final session = makeSession(
        samples: [BleHrSample(time: t0, bpm: 70)],
      );
      expect(session.duration, Duration.zero);
    });

    test('duration returns zero for empty samples', () {
      final session = makeSession(samples: []);
      expect(session.duration, Duration.zero);
    });

    group('bpmTrend', () {
      test('returns stable for fewer than 4 samples', () {
        final session = makeSession(
          samples: [
            BleHrSample(time: t0, bpm: 70),
            BleHrSample(time: t1, bpm: 80),
            BleHrSample(time: t2, bpm: 90),
          ],
        );
        expect(session.bpmTrend, 'stable');
      });

      test('returns rising when late quarter is higher', () {
        final session = makeSession(
          samples: [
            BleHrSample(time: t0, bpm: 60),
            BleHrSample(time: t1, bpm: 62),
            BleHrSample(time: t2, bpm: 70),
            BleHrSample(time: t3, bpm: 70),
            BleHrSample(
              time: DateTime.utc(2026, 3, 18, 10, 0, 4),
              bpm: 72,
            ),
            BleHrSample(
              time: DateTime.utc(2026, 3, 18, 10, 0, 5),
              bpm: 74,
            ),
            BleHrSample(
              time: DateTime.utc(2026, 3, 18, 10, 0, 6),
              bpm: 76,
            ),
            BleHrSample(
              time: DateTime.utc(2026, 3, 18, 10, 0, 7),
              bpm: 78,
            ),
          ],
        );
        expect(session.bpmTrend, 'rising');
      });

      test('returns falling when late quarter is lower', () {
        final session = makeSession(
          samples: [
            BleHrSample(time: t0, bpm: 80),
            BleHrSample(time: t1, bpm: 78),
            BleHrSample(time: t2, bpm: 70),
            BleHrSample(time: t3, bpm: 68),
            BleHrSample(
              time: DateTime.utc(2026, 3, 18, 10, 0, 4),
              bpm: 66,
            ),
            BleHrSample(
              time: DateTime.utc(2026, 3, 18, 10, 0, 5),
              bpm: 64,
            ),
            BleHrSample(
              time: DateTime.utc(2026, 3, 18, 10, 0, 6),
              bpm: 62,
            ),
            BleHrSample(
              time: DateTime.utc(2026, 3, 18, 10, 0, 7),
              bpm: 60,
            ),
          ],
        );
        expect(session.bpmTrend, 'falling');
      });

      test('returns stable when delta ≤ 5', () {
        final session = makeSession(
          samples: [
            BleHrSample(time: t0, bpm: 70),
            BleHrSample(time: t1, bpm: 71),
            BleHrSample(time: t2, bpm: 72),
            BleHrSample(time: t3, bpm: 73),
          ],
        );
        expect(session.bpmTrend, 'stable');
      });
    });

    test('decode preserves HRV as null when not present', () {
      final session = BleHrSession(
        samples: [BleHrSample(time: t0, bpm: 70)],
        rrMs: const [],
        hrv: null,
        deviceName: null,
      );
      final decoded = BleHrSession.decode(session.encode());
      expect(decoded!.hrv, isNull);
      expect(decoded.deviceName, isNull);
    });
  });
}
