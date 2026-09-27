import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/meal_tracking.dart';
import 'package:fitsocial_app/features/main/presentation/meal_tracking_screen.dart';
import 'package:fitsocial_app/features/main/presentation/meal_upload_screen.dart';

import 'shot_fakes.dart';
import 'shot_harness.dart';

class _Meals extends ShotContent {
  const _Meals();

  static LoggedMeal meal(String name, int daysAgo, int h, int m, int kcal, int p, int c, int f,
      {int items = 1}) {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysAgo));
    return LoggedMeal(
        id: '$name$daysAgo', name: name, loggedAt: DateTime(d.year, d.month, d.day, h, m),
        calories: kcal, protein: p, carbs: c, fat: f, itemCount: items, sharedToFeed: true);
  }

  @override
  Future<List<LoggedMeal>> getLoggedMeals() async => [
        // Yesterday, at the hours people actually eat; the page is stepped
        // back a day with its own arrow (it reads the device clock).
        meal('Oats, banana and peanut butter', 1, 7, 10, 520, 19, 72, 17, items: 3),
        meal('Biltong', 1, 10, 30, 125, 28, 1, 2),
        meal('Bunny chow (quarter, beans)', 1, 13, 5, 690, 21, 112, 17, items: 2),
        meal('Braai plate', 1, 19, 30, 1029, 61, 78, 52, items: 4),
        meal('Pap and chakalaka', 2, 19, 20, 460, 12, 88, 7, items: 2),
      ];

  @override
  Future<MacroGoals> getMacroGoals() async => const MacroGoals();
}

void main() {
  testWidgets('meal upload', (tester) async {
    await shoot(tester, 'meal_upload',
        shotApp(const MealUploadScreen(), pushed: true, overrides: signedIn()));
  });

  testWidgets('meal summary', (tester) async {
    await shoot(tester, 'meal_summary',
        shotApp(const MealTrackingScreen(), pushed: true,
            overrides: signedIn(content: const _Meals())),
        height: 1500, before: (t) async {
      await t.tapAt(const Offset(40, 213));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    });
  });
}
