import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/domain/meal_tracking.dart';
import 'package:fitsocial_app/features/main/domain/progress_models.dart';
import 'package:fitsocial_app/features/main/presentation/meal_tracking_screen.dart';

class _StubMeals extends UnconfiguredContentRepository {
  _StubMeals({this.steps = const {}, this.goals = const MacroGoals()});

  final Map<String, int> steps;
  final MacroGoals goals;
  List<String>? askedFor;

  @override
  Future<List<LoggedMeal>> getLoggedMeals() async => [
        LoggedMeal(
          id: 'm',
          name: 'Lunch',
          loggedAt: DateTime.now().subtract(const Duration(minutes: 1)),
          calories: 600,
          protein: 40,
          carbs: 60,
          fat: 20,
        ),
      ];

  @override
  Future<MacroGoals> getMacroGoals() async => goals;

  @override
  Future<Map<String, int>> getDailySteps(List<String> dayKeys) async {
    askedFor = dayKeys;
    return steps;
  }
}

String get _today => mealDayKey(DateTime.now());

Future<void> _pump(WidgetTester tester, _StubMeals repository) async {
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [contentRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const MealTrackingScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('StepCalories', () {
    test('only steps past the baseline count', () {
      expect(StepCalories.forDay(0), 0);
      expect(StepCalories.forDay(5000), 0);
      // 5,000 extra steps at the default 70 kg: 5000 * 0.0005 * 70.
      expect(StepCalories.forDay(10000), 175);
    });

    test('scales with body weight', () {
      expect(StepCalories.forDay(10000, weightKg: 100), 250);
      expect(StepCalories.forDay(10000, weightKg: 0), 175);
    });

    test('is capped per day', () {
      expect(StepCalories.forDay(100000), StepCalories.maxPerDay);
    });
  });

  group('MacroGoals.stepBonus', () {
    test('is on unless it was switched off', () {
      expect(MacroGoals.fromMap(null).stepBonus, isTrue);
      expect(MacroGoals.fromMap({'calorieGoal': 2000}).stepBonus, isTrue);
      expect(MacroGoals.fromMap({'stepBonus': false}).stepBonus, isFalse);
      final off = const MacroGoals().copyWith(stepBonus: false);
      expect(MacroGoals.fromMap(off.toMap()).stepBonus, isFalse);
    });
  });

  group('MealWindowSummary', () {
    final today = DateTime(2026, 10, 5);
    final day = ProgressWindow.forOffset(ProgressPeriod.day, 0, today: today);
    final week =
        ProgressWindow.forOffset(ProgressPeriod.week, 0, today: today);

    test('walking raises the calorie target and nothing else', () {
      final summary = MealWindowSummary.from(
        meals: const [],
        window: day,
        goals: const MacroGoals(),
        stepsByDay: {'2026-10-05': 10000},
      );
      expect(summary.stepCalories, 175);
      expect(summary.progress(MacroKind.calories).goal, 2300 + 175);
      expect(summary.progress(MacroKind.protein).goal, 150);
    });

    test('a week counts each day against its own baseline', () {
      final summary = MealWindowSummary.from(
        meals: const [],
        window: week,
        goals: const MacroGoals(),
        // Two 10,000-step days and a 4,000-step day. Summed first, 24,000
        // steps would clear one baseline; per day it is two bonuses.
        stepsByDay: {
          mealDayKey(week.start): 10000,
          mealDayKey(week.start.add(const Duration(days: 1))): 10000,
          mealDayKey(week.start.add(const Duration(days: 2))): 4000,
          '2020-01-01': 50000, // outside the window
        },
      );
      expect(summary.steps, 24000);
      expect(summary.stepCalories, 350);
    });

    test('switched off, steps change nothing', () {
      final summary = MealWindowSummary.from(
        meals: const [],
        window: day,
        goals: const MacroGoals(stepBonus: false),
        stepsByDay: {'2026-10-05': 10000},
      );
      expect(summary.stepCalories, 0);
      expect(summary.progress(MacroKind.calories).goal, 2300);
    });
  });

  group('meal tracking screen', () {
    testWidgets('says what walking added to the target', (tester) async {
      final repository = _StubMeals(steps: {_today: 10000});
      await _pump(tester, repository);

      expect(repository.askedFor, [_today]);
      expect(
        find.text(
          'Calorie target includes +175 kcal for '
          '${formatMacroValue(10000)} steps',
        ),
        findsOneWidget,
      );
      expect(find.text('/ ${formatMacroValue(2475)} kcal'), findsOneWidget);
    });

    testWidgets('no steps past the baseline, no line', (tester) async {
      await _pump(tester, _StubMeals(steps: {_today: 3000}));
      expect(find.textContaining('Calorie target includes'), findsNothing);
      expect(find.text('/ ${formatMacroValue(2300)} kcal'), findsOneWidget);
    });

    testWidgets('switched off, steps are not even read', (tester) async {
      final repository = _StubMeals(
        steps: {_today: 10000},
        goals: const MacroGoals(stepBonus: false),
      );
      await _pump(tester, repository);
      expect(repository.askedFor, isNull);
      expect(find.textContaining('Calorie target includes'), findsNothing);
    });
  });
}
