import 'package:flutter_test/flutter_test.dart';
import 'package:miruns_flutter/core/models/ai_provider_config.dart';

void main() {
  // ── AiProviderType ─────────────────────────────────────────────────────

  group('AiProviderType', () {
    test('has expected number of values', () {
      expect(AiProviderType.values.length, 11);
    });

    test('each type has a non-empty displayName', () {
      for (final type in AiProviderType.values) {
        expect(
          type.displayName.isNotEmpty,
          isTrue,
          reason: '$type missing displayName',
        );
      }
    });
  });

  // ── AiProviderConfig presets ───────────────────────────────────────────

  group('AiProviderConfig.preset', () {
    test('mirunsCloud preset is active by default', () {
      final cfg = AiProviderConfig.preset(AiProviderType.mirunsCloud);
      expect(cfg.isActive, isTrue);
      expect(cfg.baseUrl, isNotEmpty);
    });

    test('openAi preset has correct baseUrl and model', () {
      final cfg = AiProviderConfig.preset(AiProviderType.openAi);
      expect(cfg.baseUrl, 'https://api.openai.com');
      expect(cfg.model, 'gpt-4o-mini');
      expect(cfg.isActive, isFalse);
    });

    test('local preset uses localhost', () {
      final cfg = AiProviderConfig.preset(AiProviderType.local);
      expect(cfg.baseUrl, contains('localhost'));
    });

    test('custom preset has empty baseUrl', () {
      final cfg = AiProviderConfig.preset(AiProviderType.custom);
      expect(cfg.baseUrl, isEmpty);
    });

    test('every type has a preset', () {
      for (final type in AiProviderType.values) {
        expect(() => AiProviderConfig.preset(type), returnsNormally);
      }
    });
  });

  // ── Helpers ────────────────────────────────────────────────────────────

  group('AiProviderConfig helpers', () {
    test('requiresApiKey is false only for mirunsCloud', () {
      expect(AiProviderConfig.defaultProvider.requiresApiKey, isFalse);
      expect(
        AiProviderConfig.preset(AiProviderType.openAi).requiresApiKey,
        isTrue,
      );
    });

    test('isDefault is true only for mirunsCloud', () {
      expect(AiProviderConfig.defaultProvider.isDefault, isTrue);
      expect(
        AiProviderConfig.preset(AiProviderType.openRouter).isDefault,
        isFalse,
      );
    });

    test('hasEditableUrl is true for local and custom', () {
      expect(
        AiProviderConfig.preset(AiProviderType.local).hasEditableUrl,
        isTrue,
      );
      expect(
        AiProviderConfig.preset(AiProviderType.custom).hasEditableUrl,
        isTrue,
      );
      expect(
        AiProviderConfig.preset(AiProviderType.openAi).hasEditableUrl,
        isFalse,
      );
    });

    test('subtitle returns non-empty string for every type', () {
      for (final type in AiProviderType.values) {
        final cfg = AiProviderConfig.preset(type);
        expect(
          cfg.subtitle.isNotEmpty,
          isTrue,
          reason: '$type has no subtitle',
        );
      }
    });
  });

  // ── chatCompletionsUri ─────────────────────────────────────────────────

  group('AiProviderConfig.chatCompletionsUri', () {
    test('appends /v1/chat/completions when no /v1 suffix', () {
      final uri = AiProviderConfig.chatCompletionsUri('https://api.openai.com');
      expect(uri.toString(), 'https://api.openai.com/v1/chat/completions');
    });

    test('appends /chat/completions when /v1 already present', () {
      final uri = AiProviderConfig.chatCompletionsUri(
        'http://localhost:11434/v1',
      );
      expect(uri.toString(), 'http://localhost:11434/v1/chat/completions');
    });

    test('strips trailing slashes before normalizing', () {
      final uri = AiProviderConfig.chatCompletionsUri(
        'https://api.openai.com///',
      );
      expect(uri.toString(), 'https://api.openai.com/v1/chat/completions');
    });

    test('handles /v1/ with trailing slash', () {
      final uri = AiProviderConfig.chatCompletionsUri(
        'http://localhost:11434/v1/',
      );
      // Trailing slash is stripped first, then v1 suffix is found
      expect(uri.path, '/v1/chat/completions');
    });

    test('handles deep path like openrouter /api', () {
      final uri = AiProviderConfig.chatCompletionsUri(
        'https://openrouter.ai/api',
      );
      expect(uri.toString(), 'https://openrouter.ai/api/v1/chat/completions');
    });

    test('handles groq /openai base URL (ends with non-v1)', () {
      final uri = AiProviderConfig.chatCompletionsUri(
        'https://api.groq.com/openai',
      );
      expect(uri.toString(), 'https://api.groq.com/openai/v1/chat/completions');
    });
  });

  // ── Serialisation ──────────────────────────────────────────────────────

  group('AiProviderConfig serialisation', () {
    test('toJson / fromJson round-trip', () {
      const cfg = AiProviderConfig(
        type: AiProviderType.openAi,
        baseUrl: 'https://api.openai.com',
        apiKey: 'sk-test',
        model: 'gpt-4o',
        isActive: true,
      );
      final json = cfg.toJson();
      final restored = AiProviderConfig.fromJson(json);
      expect(restored.type, AiProviderType.openAi);
      expect(restored.baseUrl, 'https://api.openai.com');
      expect(restored.apiKey, 'sk-test');
      expect(restored.model, 'gpt-4o');
      expect(restored.isActive, isTrue);
    });

    test('fromJson defaults unknown type to mirunsCloud', () {
      final cfg = AiProviderConfig.fromJson({
        'type': 'nonexistent_provider',
        'baseUrl': 'http://test.com',
      });
      expect(cfg.type, AiProviderType.mirunsCloud);
    });

    test('fromJson defaults missing fields', () {
      final cfg = AiProviderConfig.fromJson(<String, dynamic>{});
      expect(cfg.type, AiProviderType.mirunsCloud);
      expect(cfg.baseUrl, '');
      expect(cfg.apiKey, '');
      expect(cfg.model, '');
      expect(cfg.isActive, isFalse);
    });

    test('encode / decode round-trip', () {
      const cfg = AiProviderConfig(
        type: AiProviderType.groq,
        baseUrl: 'https://api.groq.com/openai',
        apiKey: 'gsk-123',
        model: 'llama-3.3-70b-versatile',
        isActive: true,
      );
      final decoded = AiProviderConfig.decode(cfg.encode());
      expect(decoded.type, AiProviderType.groq);
      expect(decoded.apiKey, 'gsk-123');
    });
  });

  // ── copyWith ───────────────────────────────────────────────────────────

  group('AiProviderConfig copyWith', () {
    test('preserves values when no args', () {
      const cfg = AiProviderConfig(
        type: AiProviderType.openAi,
        baseUrl: 'https://api.openai.com',
        apiKey: 'sk-test',
        model: 'gpt-4o',
        isActive: true,
      );
      final copy = cfg.copyWith();
      expect(copy, cfg);
    });

    test('overrides specified fields', () {
      const cfg = AiProviderConfig(
        type: AiProviderType.openAi,
        baseUrl: 'https://api.openai.com',
        model: 'gpt-4o',
      );
      final copy = cfg.copyWith(apiKey: 'new-key', isActive: true);
      expect(copy.apiKey, 'new-key');
      expect(copy.isActive, isTrue);
      // preserved
      expect(copy.type, AiProviderType.openAi);
      expect(copy.model, 'gpt-4o');
    });
  });

  // ── Equality ───────────────────────────────────────────────────────────

  group('AiProviderConfig equality', () {
    test('equal configs have same hashCode', () {
      const a = AiProviderConfig(
        type: AiProviderType.openAi,
        baseUrl: 'https://api.openai.com',
        apiKey: 'key',
        model: 'gpt-4o',
        isActive: true,
      );
      const b = AiProviderConfig(
        type: AiProviderType.openAi,
        baseUrl: 'https://api.openai.com',
        apiKey: 'key',
        model: 'gpt-4o',
        isActive: true,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('different configs are not equal', () {
      const a = AiProviderConfig(
        type: AiProviderType.openAi,
        baseUrl: 'https://api.openai.com',
      );
      const b = AiProviderConfig(
        type: AiProviderType.groq,
        baseUrl: 'https://api.groq.com/openai',
      );
      expect(a, isNot(b));
    });
  });
}
