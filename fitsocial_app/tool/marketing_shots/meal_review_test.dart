import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/application/create_flow_controller.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/presentation/meal_review_screen.dart';

import 'shot_fakes.dart';
import 'shot_harness.dart';

/// A braai plate as the photo analysis would itemise it.
const braaiPlate = [
  MealFoodItem(
    name: 'Boerewors',
    matchedFood: 'Boerewors, grilled',
    grams: 150,
    quantity: '1 coil piece',
    calories: 438,
    protein: 22,
    carbs: 3,
    fat: 38,
    source: MacroSource.database,
    per100g: FoodComposition(calories: 292, protein: 14.7, carbs: 2, fat: 25.3),
  ),
  MealFoodItem(
    name: 'Pap',
    matchedFood: 'Maize meal porridge, stiff',
    grams: 250,
    quantity: '1 cup',
    calories: 283,
    protein: 6,
    carbs: 61,
    fat: 1,
    source: MacroSource.database,
    per100g: FoodComposition(calories: 113, protein: 2.4, carbs: 24.4, fat: 0.4),
  ),
  MealFoodItem(
    name: 'Chakalaka',
    matchedFood: 'Chakalaka relish',
    grams: 120,
    quantity: '½ cup',
    calories: 92,
    protein: 3,
    carbs: 14,
    fat: 3,
    source: MacroSource.database,
    per100g: FoodComposition(calories: 77, protein: 2.5, carbs: 11.7, fat: 2.5),
  ),
  MealFoodItem(
    name: 'Grilled chicken thigh',
    matchedFood: 'Chicken thigh, grilled, skinless',
    grams: 120,
    quantity: '1 thigh',
    calories: 216,
    protein: 30,
    carbs: 0,
    fat: 10,
    source: MacroSource.usda,
    per100g: FoodComposition(calories: 180, protein: 25, carbs: 0, fat: 8.3),
  ),
];

CreateFlowController mealFlow() {
  final flow = CreateFlowController();
  flow.updateMeal(const MealDraftState(
    name: 'Braai plate',
    calories: '1029',
    protein: '61',
    carbs: '78',
    fat: '52',
    items: braaiPlate,
    confidence: 'high',
    databaseCoverage: 1,
  ));
  return flow;
}

void main() {
  testWidgets('meal review', (tester) async {
    await shoot(
      tester,
      'meal_review',
      shotApp(const MealReviewScreen(), pushed: true, overrides: [
        ...baseFakes,
        createFlowControllerProvider.overrideWith((ref) => mealFlow()),
      ]),
    );
  });
  testWidgets('meal review long', (tester) async {
    await shoot(
      tester,
      'meal_review_long',
      shotApp(const MealReviewScreen(), pushed: true, overrides: [
        ...baseFakes,
        createFlowControllerProvider.overrideWith((ref) => mealFlow()),
      ]),
      height: 2000,
    );
  });
}
