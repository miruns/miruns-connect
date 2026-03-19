import 'package:flutter_test/flutter_test.dart';
import 'package:miruns_flutter/core/models/nutrition_log.dart';

void main() {
  // ── Fixtures ───────────────────────────────────────────────────────────

  final fullFacts = NutritionFacts(
    energyKcal: 539,
    fat: 30.9,
    saturatedFat: 10.6,
    carbohydrates: 57.5,
    sugars: 56.3,
    fiber: 3.4,
    proteins: 6.3,
    salt: 0.107,
    sodium: 0.043,
  );

  final fixedDate = DateTime.utc(2026, 3, 18, 10, 30);

  NutritionLog fullLog() => NutritionLog(
    barcode: '3017620422003',
    productName: 'Nutella',
    brand: 'Ferrero',
    nutriScore: 'e',
    novaGroup: 4,
    per100g: fullFacts,
    servingSize: '15 g',
    perServing: const NutritionFacts(energyKcal: 80.8),
    imageUrl: 'https://example.com/nutella.jpg',
    scannedAt: fixedDate,
    quantityNote: '2 servings',
  );

  // ── NutritionFacts ─────────────────────────────────────────────────────

  group('NutritionFacts', () {
    test('toJson / fromJson round-trip', () {
      final json = fullFacts.toJson();
      final restored = NutritionFacts.fromJson(json);
      expect(restored.energyKcal, fullFacts.energyKcal);
      expect(restored.fat, fullFacts.fat);
      expect(restored.saturatedFat, fullFacts.saturatedFat);
      expect(restored.carbohydrates, fullFacts.carbohydrates);
      expect(restored.sugars, fullFacts.sugars);
      expect(restored.fiber, fullFacts.fiber);
      expect(restored.proteins, fullFacts.proteins);
      expect(restored.salt, fullFacts.salt);
      expect(restored.sodium, fullFacts.sodium);
    });

    test('fromJson handles all-null fields', () {
      final restored = NutritionFacts.fromJson(<String, dynamic>{});
      expect(restored.energyKcal, isNull);
      expect(restored.fat, isNull);
      expect(restored.proteins, isNull);
    });

    test('fromJson coerces int to double', () {
      final restored = NutritionFacts.fromJson({'energy_kcal': 100, 'fat': 5});
      expect(restored.energyKcal, 100.0);
      expect(restored.fat, 5.0);
    });

    test('macroLine formats full data', () {
      expect(fullFacts.macroLine, contains('539 kcal'));
      expect(fullFacts.macroLine, contains('P 6.3g'));
      expect(fullFacts.macroLine, contains('C 57.5g'));
      expect(fullFacts.macroLine, contains('F 30.9g'));
      expect(fullFacts.macroLine, contains('S 56.3g'));
    });

    test('macroLine handles partial data', () {
      const partial = NutritionFacts(energyKcal: 42);
      expect(partial.macroLine, '42 kcal');
    });

    test('macroLine handles empty data', () {
      const empty = NutritionFacts();
      expect(empty.macroLine, isEmpty);
    });
  });

  // ── NutritionLog ───────────────────────────────────────────────────────

  group('NutritionLog', () {
    test('toJson / fromJson round-trip with all fields', () {
      final log = fullLog();
      final json = log.toJson();
      final restored = NutritionLog.fromJson(json);
      expect(restored.barcode, '3017620422003');
      expect(restored.productName, 'Nutella');
      expect(restored.brand, 'Ferrero');
      expect(restored.nutriScore, 'e');
      expect(restored.novaGroup, 4);
      expect(restored.per100g!.energyKcal, 539);
      expect(restored.servingSize, '15 g');
      expect(restored.perServing!.energyKcal, 80.8);
      expect(restored.imageUrl, 'https://example.com/nutella.jpg');
      expect(restored.scannedAt, fixedDate);
      expect(restored.quantityNote, '2 servings');
    });

    test('fromJson defaults productName when missing', () {
      final restored = NutritionLog.fromJson({
        'barcode': '1234',
        'scanned_at': fixedDate.toIso8601String(),
      });
      expect(restored.productName, 'Unknown product');
    });

    test('fromJson defaults scannedAt to now when missing', () {
      final before = DateTime.now();
      final restored = NutritionLog.fromJson({'barcode': '1234'});
      expect(
        restored.scannedAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('fromJson handles null optional fields', () {
      final restored = NutritionLog.fromJson({
        'barcode': '1234',
        'scanned_at': fixedDate.toIso8601String(),
      });
      expect(restored.brand, isNull);
      expect(restored.nutriScore, isNull);
      expect(restored.novaGroup, isNull);
      expect(restored.per100g, isNull);
      expect(restored.perServing, isNull);
      expect(restored.servingSize, isNull);
      expect(restored.imageUrl, isNull);
      expect(restored.quantityNote, isNull);
    });

    test('copyWith preserves values when no args', () {
      final log = fullLog();
      final copy = log.copyWith();
      expect(copy.barcode, log.barcode);
      expect(copy.brand, log.brand);
      expect(copy.nutriScore, log.nutriScore);
      expect(copy.novaGroup, log.novaGroup);
      expect(copy.per100g!.energyKcal, log.per100g!.energyKcal);
      expect(copy.quantityNote, log.quantityNote);
    });

    test('copyWith overrides specified fields', () {
      final log = fullLog();
      final copy = log.copyWith(
        barcode: 'NEW',
        productName: 'Updated',
        brand: 'NewBrand',
      );
      expect(copy.barcode, 'NEW');
      expect(copy.productName, 'Updated');
      expect(copy.brand, 'NewBrand');
      // other fields preserved
      expect(copy.nutriScore, log.nutriScore);
    });

    test('copyWith clear flags set fields to null', () {
      final log = fullLog();
      final copy = log.copyWith(
        clearBrand: true,
        clearNutriScore: true,
        clearNovaGroup: true,
        clearPer100g: true,
        clearServingSize: true,
        clearPerServing: true,
        clearImageUrl: true,
        clearQuantityNote: true,
      );
      expect(copy.brand, isNull);
      expect(copy.nutriScore, isNull);
      expect(copy.novaGroup, isNull);
      expect(copy.per100g, isNull);
      expect(copy.servingSize, isNull);
      expect(copy.perServing, isNull);
      expect(copy.imageUrl, isNull);
      expect(copy.quantityNote, isNull);
    });

    test('encode / decode round-trip', () {
      final log = fullLog();
      final encoded = log.encode();
      final decoded = NutritionLog.decode(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.barcode, log.barcode);
      expect(decoded.productName, log.productName);
      expect(decoded.per100g!.sugars, log.per100g!.sugars);
    });

    test('decode returns null for null input', () {
      expect(NutritionLog.decode(null), isNull);
    });

    test('decode returns null for empty string', () {
      expect(NutritionLog.decode(''), isNull);
    });

    test('decode returns null for malformed JSON', () {
      expect(NutritionLog.decode('not-json'), isNull);
    });

    test('encodeList / decodeList round-trip', () {
      final logs = [fullLog(), fullLog().copyWith(barcode: '999')];
      final encoded = NutritionLog.encodeList(logs);
      final decoded = NutritionLog.decodeList(encoded);
      expect(decoded.length, 2);
      expect(decoded[0].barcode, '3017620422003');
      expect(decoded[1].barcode, '999');
    });

    test('decodeList returns empty for null', () {
      expect(NutritionLog.decodeList(null), isEmpty);
    });

    test('decodeList returns empty for empty string', () {
      expect(NutritionLog.decodeList(''), isEmpty);
    });

    test('decodeList returns empty for malformed JSON', () {
      expect(NutritionLog.decodeList('bad'), isEmpty);
    });

    test('displayLabel includes brand when present', () {
      final log = fullLog();
      expect(log.displayLabel, 'Ferrero · Nutella');
    });

    test('displayLabel omits brand when null', () {
      final log = fullLog().copyWith(clearBrand: true);
      expect(log.displayLabel, 'Nutella');
    });

    test('sugarSummary formats sugar value', () {
      final log = fullLog();
      expect(log.sugarSummary, 'Sugar: 56.3 g / 100 g');
    });

    test('sugarSummary returns n/a when no per100g', () {
      final log = fullLog().copyWith(clearPer100g: true);
      expect(log.sugarSummary, 'Sugar: n/a');
    });

    test('sugarSummary returns n/a when sugar is null', () {
      final log = NutritionLog(
        barcode: '123',
        productName: 'Test',
        per100g: const NutritionFacts(energyKcal: 100),
        scannedAt: fixedDate,
      );
      expect(log.sugarSummary, 'Sugar: n/a');
    });

    test('toJson encodes nested NutritionFacts as maps', () {
      final json = fullLog().toJson();
      expect(json['per_100g'], isA<Map<String, dynamic>>());
      expect(json['per_serving'], isA<Map<String, dynamic>>());
    });

    test('toJson stores scannedAt as ISO 8601', () {
      final json = fullLog().toJson();
      expect(json['scanned_at'], fixedDate.toIso8601String());
    });
  });
}
