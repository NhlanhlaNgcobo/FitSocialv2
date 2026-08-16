import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/domain/meal_tracking.dart';
import 'package:fitsocial_app/features/main/presentation/meal_tracking_screen.dart';

/// Only the two reads the tracking page makes are needed.
class StubMeals extends UnconfiguredContentRepository {
  StubMeals({required this.meals, this.goals = const MacroGoals()});

  final List<LoggedMeal> meals;
  final MacroGoals goals;

  @override
  Future<List<LoggedMeal>> getLoggedMeals() async => meals;

  @override
  Future<MacroGoals> getMacroGoals() async => goals;
}

LoggedMeal meal({
  required String name,
  required int hour,
  required int minute,
  required int calories,
  int protein = 0,
  int carbs = 0,
  int fat = 0,
  int daysAgo = 0,
}) {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day).subtract(
    Duration(days: daysAgo),
  );
  return LoggedMeal(
    id: name,
    name: name,
    loggedAt: DateTime(day.year, day.month, day.day, hour, minute),
    calories: calories,
    protein: protein,
    carbs: carbs,
    fat: fat,
  );
}

/// The four meals from the design, logged today.
List<LoggedMeal> get designDay => [
      meal(
        name: 'Breakfast',
        hour: 8,
        minute: 15,
        calories: 412,
        protein: 28,
        carbs: 45,
        fat: 12,
      ),
      meal(
        name: 'Lunch',
        hour: 13,
        minute: 2,
        calories: 645,
        protein: 45,
        carbs: 62,
        fat: 18,
      ),
      meal(
        name: 'Snack',
        hour: 16,
        minute: 30,
        calories: 210,
        protein: 20,
        carbs: 24,
        fat: 4,
      ),
      meal(
        name: 'Dinner',
        hour: 19,
        minute: 25,
        calories: 575,
        protein: 39,
        carbs: 84,
        fat: 30,
      ),
    ];

Future<void> pumpTracking(WidgetTester tester, StubMeals repository) async {
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contentRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const MealTrackingScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('meal tracking screen', () {
    testWidgets('totals the day and shows each macro against its target',
        (tester) async {
      await pumpTracking(tester, StubMeals(meals: designDay));

      // 412 + 645 + 210 + 575
      expect(find.text(formatMacroValue(1842)), findsOneWidget);
      expect(find.text('/ ${formatMacroValue(2300)} kcal'), findsOneWidget);
      expect(find.text('80%'), findsWidgets);

      // 28 + 45 + 20 + 39 protein, against the 150 g default.
      expect(find.text('132 g'), findsOneWidget);
      expect(find.text('/ 150 g'), findsOneWidget);
    });

    testWidgets('lists the meals in the order they were eaten', (tester) async {
      await pumpTracking(tester, StubMeals(meals: designDay));

      final rows = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .toList();

      expect(
        rows.indexOf('Breakfast') < rows.indexOf('Lunch'),
        isTrue,
        reason: 'a day should read top to bottom as it happened',
      );
      expect(rows.indexOf('Snack') < rows.indexOf('Dinner'), isTrue);
    });

    testWidgets('shows each meal with its time, calories and macros',
        (tester) async {
      await pumpTracking(tester, StubMeals(meals: designDay));

      expect(find.text('08:15'), findsOneWidget);
      expect(find.text('13:02'), findsOneWidget);
      expect(find.text('P 28g'), findsOneWidget);
      expect(find.text('C 62g'), findsOneWidget);
      expect(find.text('F 30g'), findsOneWidget);
    });

    // The whole point of the period picker: a day's target must not be used as
    // a week's.
    testWidgets('scales the target when the period changes', (tester) async {
      await pumpTracking(tester, StubMeals(meals: designDay));
      expect(find.text('/ ${formatMacroValue(2300)} kcal'), findsOneWidget);

      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();

      expect(find.text('/ ${formatMacroValue(2300 * 7)} kcal'), findsOneWidget);
      // The same meals still count — they are inside this week too.
      expect(find.text(formatMacroValue(1842)), findsOneWidget);
    });

    testWidgets('paging back a day leaves today behind', (tester) async {
      await pumpTracking(tester, StubMeals(meals: designDay));
      expect(find.text('Breakfast'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Yesterday'), findsOneWidget);
      expect(find.text('No meals logged for this period.'), findsOneWidget);
      expect(find.text('Breakfast'), findsNothing);
    });

    testWidgets('cannot page into the future', (tester) async {
      await pumpTracking(tester, StubMeals(meals: designDay));

      // byTooltip matches the Tooltip the button builds, so the button itself
      // is its ancestor.
      final next = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Next'),
          matching: find.byType(IconButton),
        ),
      );
      expect(next.onPressed, isNull);
    });

    testWidgets('an empty day invites a first meal', (tester) async {
      await pumpTracking(tester, StubMeals(meals: const []));

      expect(find.text('No meals logged for this period.'), findsOneWidget);
      expect(find.textContaining('Nothing logged yet'), findsOneWidget);
      expect(find.text('Log Another Meal'), findsOneWidget);
    });

    testWidgets('counts only meals inside the window', (tester) async {
      await pumpTracking(
        tester,
        StubMeals(
          meals: [
            ...designDay,
            meal(name: 'Old dinner', hour: 20, minute: 0, calories: 900,
                daysAgo: 9),
          ],
        ),
      );

      // Still today's four, not the one from nine days ago.
      expect(find.text(formatMacroValue(1842)), findsOneWidget);
      expect(find.text('Old dinner'), findsNothing);
    });

    testWidgets('flags going over target rather than capping the number',
        (tester) async {
      await pumpTracking(
        tester,
        StubMeals(
          meals: [meal(name: 'Feast', hour: 12, minute: 0, calories: 3450)],
          goals: const MacroGoals(calories: 2300),
        ),
      );

      expect(find.text('150%'), findsOneWidget);
    });
  });
}
