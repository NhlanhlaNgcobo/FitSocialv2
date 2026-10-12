import 'package:flutter_test/flutter_test.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/meal_quality.dart';

/// An item the way analyzeMeal resolves it: macros scaled to the grams.
MealFoodItem food(
  String name, {
  required int grams,
  required int calories,
  int protein = 0,
  int carbs = 0,
  int fat = 0,
  String? category,
}) {
  return MealFoodItem(
    name: name,
    grams: grams,
    calories: calories,
    protein: protein,
    carbs: carbs,
    fat: fat,
    category: category,
  );
}

void main() {
  group('MealQuality.of', () {
    test('chicken, broccoli and brown rice is a great plate', () {
      final quality = MealQuality.of([
        food('chicken breast',
            grams: 150, calories: 248, protein: 47, fat: 5,
            category: 'protein'),
        food('broccoli',
            grams: 150, calories: 52, protein: 4, carbs: 11, fat: 1,
            category: 'vegetable'),
        food('brown rice',
            grams: 150, calories: 185, protein: 4, carbs: 39, fat: 2,
            category: 'starch'),
      ])!;

      expect(quality.proteinPoints, 3);
      expect(quality.plantPoints, 2);
      expect(quality.treatPoints, 3);
      expect(quality.fatPoints, 1);
      expect(quality.score, 9);
      expect(quality.band, MealQualityBand.great);
      expect(quality.notes, contains('Plenty of protein'));
    });

    test('pap, beef stew and chakalaka scores good', () {
      final quality = MealQuality.of([
        food('pap',
            grams: 300, calories: 360, protein: 8, carbs: 78, fat: 2,
            category: 'starch'),
        food('beef stew',
            grams: 250, calories: 350, protein: 33, carbs: 18, fat: 15,
            category: 'dish'),
        food('chakalaka',
            grams: 100, calories: 80, protein: 2, carbs: 10, fat: 4,
            category: 'vegetable'),
      ])!;

      expect(quality.score, 7);
      expect(quality.band, MealQualityBand.good);
    });

    test('pizza and a cooldrink is fair, and the drink is a treat', () {
      final quality = MealQuality.of([
        food('pizza',
            grams: 300, calories: 798, protein: 33, carbs: 90, fat: 33,
            category: 'dish'),
        food('coke',
            grams: 330, calories: 139, carbs: 35, category: 'drink'),
      ])!;

      expect(quality.treatPoints, 2);
      expect(quality.plantPoints, 0);
      expect(quality.score, 4);
      expect(quality.band, MealQualityBand.fair);
      expect(quality.notes, contains('No veg or fruit'));
    });

    test('a slab of chocolate is a treat, not an error', () {
      final quality = MealQuality.of([
        food('chocolate',
            grams: 100, calories: 535, protein: 7, carbs: 59, fat: 30,
            category: 'dessert'),
      ])!;

      expect(quality.score, 0);
      expect(quality.band, MealQualityBand.treat);
      expect(quality.notes, contains('Mostly treats'));
    });

    test('too little food to judge gives no score', () {
      expect(MealQuality.of(const []), isNull);
      expect(
        MealQuality.of([
          food('black coffee', grams: 250, calories: 5, category: 'drink'),
        ]),
        isNull,
      );
    });

    test('a cooldrink does not count against the plate weight', () {
      final withDrink = MealQuality.of([
        food('grilled chicken',
            grams: 150, calories: 248, protein: 47, fat: 5,
            category: 'protein'),
        food('green salad',
            grams: 100, calories: 20, protein: 1, carbs: 4,
            category: 'vegetable'),
        food('water', grams: 500, calories: 0, category: 'drink'),
      ])!;

      // 100 of 250 plate grams, not 100 of 750.
      expect(withDrink.plantPoints, 3);
    });

    test('notes stop at three', () {
      final quality = MealQuality.of([
        food('chips',
            grams: 200, calories: 624, protein: 7, carbs: 82, fat: 30,
            category: 'starch'),
        food('cake',
            grams: 100, calories: 370, protein: 4, carbs: 50, fat: 17,
            category: 'dessert'),
      ])!;
      expect(quality.notes.length, lessThanOrEqualTo(3));
    });
  });

  group('MealFoodGroup', () {
    test('the table category wins over the name', () {
      expect(
        MealFoodGroup.of(food('mystery', grams: 1, calories: 1,
            category: 'Fruit')),
        MealFoodGroup.fruit,
      );
    });

    test('items without a category are placed by name', () {
      MealFoodGroup groupOf(String name) =>
          MealFoodGroup.of(food(name, grams: 1, calories: 1));

      expect(groupOf('Side salad'), MealFoodGroup.vegetable);
      expect(groupOf('sliced mango'), MealFoodGroup.fruit);
      expect(groupOf('lentil curry'), MealFoodGroup.legume);
      expect(groupOf('tomato sauce'), MealFoodGroup.condiment);
      expect(groupOf('carrot cake'), MealFoodGroup.dessert);
      expect(groupOf('fruit yoghurt'), MealFoodGroup.dairy);
      expect(groupOf('orange juice'), MealFoodGroup.drink);
      expect(groupOf('grilled hake'), MealFoodGroup.other);
    });

    test('a USDA match is placed by its name, not as "usda"', () {
      expect(
        MealFoodGroup.of(food('kale', grams: 1, calories: 1,
            category: 'usda')),
        MealFoodGroup.vegetable,
      );
    });

    test('sugary condiments are treats, fatty ones are not', () {
      final jam = MealQuality.of([
        food('toast',
            grams: 100, calories: 265, protein: 9, carbs: 49, fat: 3,
            category: 'starch'),
        food('jam',
            grams: 40, calories: 100, carbs: 25, category: 'condiment'),
      ])!;
      final mayo = MealQuality.of([
        food('toast',
            grams: 100, calories: 265, protein: 9, carbs: 49, fat: 3,
            category: 'starch'),
        food('mayonnaise',
            grams: 15, calories: 102, fat: 11, category: 'condiment'),
      ])!;

      expect(jam.treatPoints, lessThan(3));
      expect(mayo.treatPoints, 3);
    });
  });

  test('the category survives a save and a read back', () {
    final item = MealFoodItem.fromMap({
      'name': 'spinach',
      'grams': 80,
      'category': 'vegetable',
      'calories': '18',
      'protein': '2',
      'carbs': '3',
      'fat': '0',
    })!;
    expect(item.category, 'vegetable');
    expect(MealFoodItem.fromMap(item.toMap())!.category, 'vegetable');

    final blank = MealFoodItem.fromMap({'name': 'pap', 'category': ' '})!;
    expect(blank.category, isNull);
    expect(blank.toMap().containsKey('category'), isFalse);
  });
}
