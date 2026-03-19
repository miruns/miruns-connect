import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:miruns_flutter/core/models/capture_ai_metadata.dart';

void main() {
  // ── Fixtures ───────────────────────────────────────────────────────────

  final fixedDate = DateTime.utc(2026, 3, 18, 14, 30);

  CaptureAiMetadata fullMetadata() => CaptureAiMetadata(
    summary: 'Active morning with outdoor run.',
    themes: ['outdoor-activity', 'recovery'],
    energyLevel: 'high',
    moodAssessment: 'energized and focused',
    tags: ['running', 'morning'],
    notableSignals: ['elevated heart rate', 'high UV'],
    generatedAt: fixedDate,
    timeOfDay: 'morning',
    dayType: 'weekday',
    activityCategory: 'active',
    locationContext: 'outdoors',
    sleepQuality: 8,
    stressLevel: 3,
    weatherImpact: 'positive',
    socialContext: 'alone',
    patternHints: ['consistent-morning-routine', 'post-workout-energy-boost'],
    bodySignal: 'energized',
    environmentScore: 9,
    hrvContext: 'relaxed-autonomic-tone',
    hrArc: 'HR rose steadily from 68 to 142 bpm.',
    nutritionContext: 'Light breakfast, good energy balance.',
  );

  // ── toJson / fromJson ──────────────────────────────────────────────────

  group('CaptureAiMetadata serialisation', () {
    test('toJson / fromJson round-trip with all fields', () {
      final meta = fullMetadata();
      final json = meta.toJson();
      final restored = CaptureAiMetadata.fromJson(json);

      expect(restored.summary, meta.summary);
      expect(restored.themes, meta.themes);
      expect(restored.energyLevel, meta.energyLevel);
      expect(restored.moodAssessment, meta.moodAssessment);
      expect(restored.tags, meta.tags);
      expect(restored.notableSignals, meta.notableSignals);
      expect(restored.generatedAt, meta.generatedAt);
      expect(restored.timeOfDay, meta.timeOfDay);
      expect(restored.dayType, meta.dayType);
      expect(restored.activityCategory, meta.activityCategory);
      expect(restored.locationContext, meta.locationContext);
      expect(restored.sleepQuality, meta.sleepQuality);
      expect(restored.stressLevel, meta.stressLevel);
      expect(restored.weatherImpact, meta.weatherImpact);
      expect(restored.socialContext, meta.socialContext);
      expect(restored.patternHints, meta.patternHints);
      expect(restored.bodySignal, meta.bodySignal);
      expect(restored.environmentScore, meta.environmentScore);
      expect(restored.hrvContext, meta.hrvContext);
      expect(restored.hrArc, meta.hrArc);
      expect(restored.nutritionContext, meta.nutritionContext);
    });

    test('toJson omits null v2 correlation fields', () {
      final meta = CaptureAiMetadata(
        summary: 'Test',
        themes: const [],
        energyLevel: 'medium',
        moodAssessment: 'calm',
        tags: const [],
        notableSignals: const [],
        generatedAt: fixedDate,
      );
      final json = meta.toJson();
      expect(json.containsKey('time_of_day'), isFalse);
      expect(json.containsKey('day_type'), isFalse);
      expect(json.containsKey('activity_category'), isFalse);
      expect(json.containsKey('pattern_hints'), isFalse);
      expect(json.containsKey('hrv_context'), isFalse);
      expect(json.containsKey('nutrition_context'), isFalse);
    });

    test('toJson includes pattern_hints only when non-empty', () {
      final withHints = fullMetadata();
      expect(withHints.toJson().containsKey('pattern_hints'), isTrue);

      final withoutHints = CaptureAiMetadata(
        summary: 'Test',
        themes: const [],
        energyLevel: 'low',
        moodAssessment: 'tired',
        tags: const [],
        notableSignals: const [],
        generatedAt: fixedDate,
        patternHints: const [],
      );
      expect(withoutHints.toJson().containsKey('pattern_hints'), isFalse);
    });

    test('fromJson handles all missing optional fields', () {
      final meta = CaptureAiMetadata.fromJson({
        'summary': 'Hello',
        'themes': ['a'],
        'energy_level': 'high',
        'mood_assessment': 'good',
        'tags': ['b'],
        'notable_signals': ['c'],
        'generated_at': fixedDate.toIso8601String(),
      });
      expect(meta.timeOfDay, isNull);
      expect(meta.dayType, isNull);
      expect(meta.activityCategory, isNull);
      expect(meta.locationContext, isNull);
      expect(meta.sleepQuality, isNull);
      expect(meta.stressLevel, isNull);
      expect(meta.weatherImpact, isNull);
      expect(meta.socialContext, isNull);
      expect(meta.patternHints, isEmpty);
      expect(meta.bodySignal, isNull);
      expect(meta.environmentScore, isNull);
      expect(meta.hrvContext, isNull);
      expect(meta.hrArc, isNull);
      expect(meta.nutritionContext, isNull);
    });

    test('fromJson defaults summary to empty string when null', () {
      final meta = CaptureAiMetadata.fromJson({
        'generated_at': fixedDate.toIso8601String(),
      });
      expect(meta.summary, '');
    });

    test('fromJson defaults energyLevel to unknown when null', () {
      final meta = CaptureAiMetadata.fromJson({
        'generated_at': fixedDate.toIso8601String(),
      });
      expect(meta.energyLevel, 'unknown');
    });

    test('fromJson defaults list fields to empty when non-list', () {
      final meta = CaptureAiMetadata.fromJson({
        'themes': 'not-a-list',
        'tags': 42,
        'notable_signals': null,
        'generated_at': fixedDate.toIso8601String(),
      });
      expect(meta.themes, isEmpty);
      expect(meta.tags, isEmpty);
      expect(meta.notableSignals, isEmpty);
    });

    test('fromJson defaults generatedAt to now when null', () {
      final before = DateTime.now();
      final meta = CaptureAiMetadata.fromJson(<String, dynamic>{});
      expect(
        meta.generatedAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
    });
  });

  // ── encode / decode ────────────────────────────────────────────────────

  group('CaptureAiMetadata encode / decode', () {
    test('encode produces valid JSON string', () {
      final meta = fullMetadata();
      final encoded = meta.encode();
      expect(() => jsonDecode(encoded), returnsNormally);
    });

    test('decode round-trip preserves all fields', () {
      final meta = fullMetadata();
      final decoded = CaptureAiMetadata.decode(meta.encode());
      expect(decoded, isNotNull);
      expect(decoded!.summary, meta.summary);
      expect(decoded.themes, meta.themes);
      expect(decoded.hrvContext, meta.hrvContext);
      expect(decoded.nutritionContext, meta.nutritionContext);
    });

    test('decode returns null for null input', () {
      expect(CaptureAiMetadata.decode(null), isNull);
    });

    test('decode returns null for empty string', () {
      expect(CaptureAiMetadata.decode(''), isNull);
    });

    test('decode returns null for malformed JSON', () {
      expect(CaptureAiMetadata.decode('not-json'), isNull);
    });

    test('decode returns null for valid JSON but wrong type', () {
      expect(CaptureAiMetadata.decode('"just a string"'), isNull);
    });
  });
}
