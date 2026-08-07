import 'package:flutter_test/flutter_test.dart';
import 'package:fitsocial_app/features/main/application/create_flow_controller.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';

/// A response shaped like the one analyzeMeal returns: macros as strings,
/// per-item breakdown with the composition each item was computed from.
Map<String, dynamic> analysisResponse() => {
      'name': 'Pap and boerewors',
      'calories': '757',
      'protein': '29',
      'carbs': '78',
      'fat': '35',
      'confidence': 'high',
      'notes': 'Portion estimated from a standard dinner plate.',
      'databaseCoverage': 1.0,
      'foodItems': [
        {
          'name': 'pap',
          'matchedFood': 'Pap (stiff maize porridge)',
          'foodId': 'pap-stiff',
          'grams': 300,
          'quantity': '300g',
          'source': 'database',
          'per100g': {
            'calories': 120,
            'protein': 2.5,
            'carbs': 26,
            'fat': 0.5,
          },
          'calories': '360',
          'protein': '8',
          'carbs': '78',
          'fat': '2',
        },
        {
          'name': 'boerewors',
          'matchedFood': 'Boerewors, grilled',
          'foodId': 'boerewors',
          'grams': 130,
          'quantity': '130g',
          'source': 'database',
          'per100g': {
            'calories': 300,
            'protein': 14,
            'carbs': 3,
            'fat': 26,
          },
          'calories': '390',
          'protein': '18',
          'carbs': '4',
          'fat': '34',
        },
      ],
    };

void main() {
  group('MealFoodItem', () {
    test('parses an analyzed item, including stringly-typed macros', () {
      final item = MealFoodItem.fromMap(analysisResponse()['foodItems'][0]);

      expect(item, isNotNull);
      expect(item!.name, 'pap');
      expect(item.matchedFood, 'Pap (stiff maize porridge)');
      expect(item.foodId, 'pap-stiff');
      expect(item.grams, 300);
      expect(item.source, MacroSource.database);
      expect(item.calories, 360);
      expect(item.protein, 8);
      expect(item.per100g?.calories, 120);
    });

    test('drops an item with no name rather than logging a blank row', () {
      expect(MealFoodItem.fromMap({'grams': 100}), isNull);
      expect(MealFoodItem.fromMap({'name': '   '}), isNull);
      expect(MealFoodItem.fromMap('not a map'), isNull);
    });

    test('rescales macros from the composition when the portion changes', () {
      final item = MealFoodItem.fromMap(analysisResponse()['foodItems'][0])!;
      final halved = item.withGrams(150);

      expect(halved.grams, 150);
      expect(halved.calories, 180);
      expect(halved.protein, 4);
      expect(halved.carbs, 39);
      expect(halved.fat, 1);
      // The composition travels with the item, so it can be rescaled again.
      expect(halved.withGrams(300).calories, 360);
    });

    test('leaves an estimate\'s macros alone — nothing to scale from', () {
      const item = MealFoodItem(
        name: 'mystery stew',
        grams: 200,
        calories: 300,
        protein: 20,
        carbs: 10,
        fat: 18,
      );

      final resized = item.withGrams(400);

      expect(resized.grams, 400);
      expect(resized.source, MacroSource.estimate);
      expect(resized.calories, 300, reason: 'no per100g means no rescaling');
    });

    test('unknown source names fall back to estimate', () {
      expect(MacroSource.fromName('database'), MacroSource.database);
      expect(MacroSource.fromName('usda'), MacroSource.usda);
      expect(MacroSource.fromName('nonsense'), MacroSource.estimate);
      expect(MacroSource.fromName(null), MacroSource.estimate);
      expect(MacroSource.database.isFromDatabase, isTrue);
      expect(MacroSource.usda.isFromDatabase, isTrue);
      expect(MacroSource.estimate.isFromDatabase, isFalse);
    });
  });

  group('MealDraftState.fromAnalysis', () {
    test('takes the totals from the items so the two always agree', () {
      final draft = MealDraftState.fromAnalysis(
        analysisResponse(),
        imageUrl: 'https://example.test/meal.jpg',
      );

      expect(draft.name, 'Pap and boerewors');
      expect(draft.items, hasLength(2));
      expect(draft.imageUrl, 'https://example.test/meal.jpg');
      expect(draft.confidence, 'high');
      expect(draft.databaseCoverage, 1.0);
      // 360 + 390, not the response's own total field.
      expect(draft.calories, '750');
      expect(draft.protein, '26');
      expect(draft.carbs, '82');
      expect(draft.fat, '36');
    });

    test('falls back to the response totals when there are no items', () {
      final response = analysisResponse()..['foodItems'] = <dynamic>[];
      final draft = MealDraftState.fromAnalysis(response);

      expect(draft.items, isEmpty);
      expect(draft.calories, '757');
      expect(draft.protein, '29');
    });

    test('survives a response missing every optional field', () {
      final draft = MealDraftState.fromAnalysis({'name': 'Toast'});

      expect(draft.name, 'Toast');
      expect(draft.items, isEmpty);
      expect(draft.calories, '');
      expect(draft.confidence, isNull);
      expect(draft.databaseCoverage, isNull);
    });
  });

  group('MacroTotals', () {
    test('sums an itemised meal', () {
      final items = MealFoodItem.listFrom(analysisResponse()['foodItems']);
      final totals = MacroTotals.of(items);

      expect(totals.calories, 750);
      expect(totals.protein, 26);
      expect(totals.carbs, 82);
      expect(totals.fat, 36);
    });

    test('an empty meal is all zeros', () {
      final totals = MacroTotals.of(const []);
      expect(totals.calories, 0);
      expect(totals.fat, 0);
    });
  });

  group('FoodSearchResult', () {
    test('converts a database entry into an item at a given portion', () {
      final food = FoodSearchResult.fromMap({
        'id': 'chicken-breast',
        'name': 'Chicken breast, skinless, grilled',
        'category': 'protein',
        'per100g': {
          'calories': 165,
          'protein': 31,
          'carbs': 0,
          'fat': 3.6,
        },
        'defaultPortionGrams': 150,
      });

      expect(food, isNotNull);
      final item = food!.toItem(200);

      expect(item.foodId, 'chicken-breast');
      expect(item.source, MacroSource.database);
      expect(item.grams, 200);
      expect(item.calories, 330);
      expect(item.protein, 62);
      expect(item.fat, 7);
    });

    test('a portion of zero falls back to the food\'s default', () {
      final food = FoodSearchResult.fromMap({
        'id': 'banana',
        'name': 'Banana',
        'per100g': {'calories': 89, 'protein': 1.1, 'carbs': 23, 'fat': 0.3},
        'defaultPortionGrams': 118,
      })!;

      expect(food.toItem(0).grams, 118);
    });

    test('rejects an entry with no composition', () {
      expect(
        FoodSearchResult.fromMap({'id': 'x', 'name': 'Mystery'}),
        isNull,
      );
    });
  });
}
