import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:miruns_flutter/core/models/body_blog_version.dart';

void main() {
  // ── Fixtures ───────────────────────────────────────────────────────────

  final fixedDate = DateTime.utc(2026, 3, 18);
  final generatedTime = DateTime.utc(2026, 3, 18, 14, 30, 45);

  Map<String, dynamic> fullJson() => {
    'id': 42,
    'date': '2026-03-18',
    'generated_at': generatedTime.toIso8601String(),
    'trigger': BlogVersionTrigger.aiEnriched,
    'headline': 'A productive morning',
    'summary': 'Solid sleep fueled a focused work session.',
    'full_body': '## Morning\nSlept well. Went for a run at 7am.',
    'mood': 'focused',
    'mood_emoji': '🎯',
    'tags': jsonEncode(['morning', 'productive']),
    'ai_generated': 1,
  };

  // ── fromJson ───────────────────────────────────────────────────────────

  group('BodyBlogVersion.fromJson', () {
    test('parses all fields correctly', () {
      final version = BodyBlogVersion.fromJson(fullJson());
      expect(version.id, 42);
      expect(version.date, DateTime.parse('2026-03-18T00:00:00.000'));
      expect(version.generatedAt, generatedTime);
      expect(version.trigger, BlogVersionTrigger.aiEnriched);
      expect(version.headline, 'A productive morning');
      expect(version.summary, 'Solid sleep fueled a focused work session.');
      expect(version.fullBody, contains('Slept well'));
      expect(version.mood, 'focused');
      expect(version.moodEmoji, '🎯');
      expect(version.tags, ['morning', 'productive']);
      expect(version.aiGenerated, isTrue);
    });

    test('handles null tags gracefully', () {
      final json = fullJson()..['tags'] = null;
      final version = BodyBlogVersion.fromJson(json);
      expect(version.tags, isEmpty);
    });

    test('aiGenerated defaults to false when 0 or null', () {
      final json0 = fullJson()..['ai_generated'] = 0;
      expect(BodyBlogVersion.fromJson(json0).aiGenerated, isFalse);

      final jsonNull = fullJson()..['ai_generated'] = null;
      expect(BodyBlogVersion.fromJson(jsonNull).aiGenerated, isFalse);
    });

    test('date parses date-only string into midnight DateTime', () {
      final version = BodyBlogVersion.fromJson(fullJson());
      expect(version.date.hour, 0);
      expect(version.date.minute, 0);
      expect(version.date.second, 0);
    });
  });

  // ── toJson ─────────────────────────────────────────────────────────────

  group('BodyBlogVersion.toJson', () {
    test('round-trip: fromJson → toJson → fromJson', () {
      final original = BodyBlogVersion.fromJson(fullJson());
      final json = original.toJson();
      final restored = BodyBlogVersion.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.headline, original.headline);
      expect(restored.summary, original.summary);
      expect(restored.fullBody, original.fullBody);
      expect(restored.mood, original.mood);
      expect(restored.moodEmoji, original.moodEmoji);
      expect(restored.tags, original.tags);
      expect(restored.trigger, original.trigger);
      expect(restored.aiGenerated, original.aiGenerated);
    });

    test('stores date as YYYY-MM-DD string', () {
      final version = BodyBlogVersion.fromJson(fullJson());
      final json = version.toJson();
      expect(json['date'], '2026-03-18');
    });

    test('stores date with zero-padded month and day', () {
      final json = fullJson()..['date'] = '2026-01-05';
      final version = BodyBlogVersion.fromJson(json);
      expect(version.toJson()['date'], '2026-01-05');
    });

    test('stores tags as JSON-encoded string', () {
      final version = BodyBlogVersion.fromJson(fullJson());
      final json = version.toJson();
      final tags = jsonDecode(json['tags'] as String);
      expect(tags, ['morning', 'productive']);
    });

    test('stores aiGenerated as 1 for true', () {
      final version = BodyBlogVersion.fromJson(fullJson());
      expect(version.toJson()['ai_generated'], 1);
    });

    test('stores aiGenerated as 0 for false', () {
      final json = fullJson()..['ai_generated'] = 0;
      final version = BodyBlogVersion.fromJson(json);
      expect(version.toJson()['ai_generated'], 0);
    });

    test('stores generated_at as ISO 8601', () {
      final version = BodyBlogVersion.fromJson(fullJson());
      final json = version.toJson();
      expect(json['generated_at'], generatedTime.toIso8601String());
    });
  });

  // ── BlogVersionTrigger constants ───────────────────────────────────────

  group('BlogVersionTrigger', () {
    test('draft constant', () {
      expect(BlogVersionTrigger.draft, 'draft');
    });

    test('aiEnriched constant', () {
      expect(BlogVersionTrigger.aiEnriched, 'ai_enriched');
    });

    test('refresh constant', () {
      expect(BlogVersionTrigger.refresh, 'refresh');
    });

    test('incremental constant', () {
      expect(BlogVersionTrigger.incremental, 'incremental');
    });

    test('regen constant', () {
      expect(BlogVersionTrigger.regen, 'regen');
    });
  });
}
