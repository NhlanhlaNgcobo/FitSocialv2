import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/meal_tracking.dart';
import 'package:fitsocial_app/features/main/domain/progress_models.dart';

LoggedMeal meal({
  String id = 'm1',
  String name = 'Lunch',
  DateTime? at,
  int calories = 600,
  int protein = 40,
  int carbs = 60,
  int fat = 20,
}) {
  return LoggedMeal(
    id: id,
    name: name,
    loggedAt: at ?? DateTime(2026, 5, 8, 13, 2),
    calories: calories,
    protein: protein,
    carbs: carbs,
    fat: fat,
  );
}

/// The window containing 8 May 2026, as the page would build it.
ProgressWindow windowFor(ProgressPeriod period, {int offset = 0}) =>
    ProgressWindow.forOffset(period, offset, today: DateTime(2026, 5, 8));

void main() {
  group('a logged meal', () {
    test('reads its time back zero-padded', () {
      expect(meal(at: DateTime(2026, 5, 8, 8, 5)).timeLabel, '08:05');
      expect(meal(at: DateTime(2026, 5, 8, 19, 25)).timeLabel, '19:25');
    });

    // A meal saved without a name used to render as a blank row. Naming it for
    // the time of day is the distinction the list is actually drawing.
    test('names an unnamed meal for when it was eaten', () {
      String nameAt(int hour) =>
          meal(name: '', at: DateTime(2026, 5, 8, hour)).displayName;

      expect(nameAt(8), 'Breakfast');
      expect(nameAt(13), 'Lunch');
      expect(nameAt(16), 'Snack');
      expect(nameAt(20), 'Dinner');
    });

    test('keeps a name the user gave it', () {
      expect(meal(name: 'Chicken salad').displayName, 'Chicken salad');
      expect(meal(name: '   ').displayName, isNot('   '));
    });
  });

  group('window totals', () {
    test('add up only the meals inside the window', () {
      final summary = MealWindowSummary.from(
        meals: [
          meal(id: 'a', at: DateTime(2026, 5, 8, 8), calories: 412, protein: 28),
          meal(id: 'b', at: DateTime(2026, 5, 8, 13), calories: 645, protein: 45),
          // Yesterday — outside a Day window.
          meal(id: 'c', at: DateTime(2026, 5, 7, 13), calories: 900, protein: 60),
        ],
        window: windowFor(ProgressPeriod.day),
        goals: const MacroGoals(),
      );

      expect(summary.meals.length, 2);
      expect(summary.total(MacroKind.calories), 1057);
      expect(summary.total(MacroKind.protein), 73);
    });

    // The list reads top to bottom as the day happened — breakfast first.
    test('orders the meals as they were eaten', () {
      final summary = MealWindowSummary.from(
        meals: [
          meal(id: 'dinner', at: DateTime(2026, 5, 8, 19, 25)),
          meal(id: 'breakfast', at: DateTime(2026, 5, 8, 8, 15)),
          meal(id: 'lunch', at: DateTime(2026, 5, 8, 13, 2)),
        ],
        window: windowFor(ProgressPeriod.day),
        goals: const MacroGoals(),
      );

      expect(
        summary.meals.map((m) => m.id).toList(),
        ['breakfast', 'lunch', 'dinner'],
      );
    });

    test('a window with nothing in it reports empty', () {
      final summary = MealWindowSummary.from(
        meals: [meal(at: DateTime(2026, 4, 1))],
        window: windowFor(ProgressPeriod.day),
        goals: const MacroGoals(),
      );

      expect(summary.isEmpty, isTrue);
      expect(summary.total(MacroKind.calories), 0);
      expect(summary.insight, contains('Nothing logged'));
    });
  });

  group('goals across a window', () {
    // A week of eating is judged against seven days of target, not one — the
    // denominator has to scale or every week reads as a catastrophic overshoot.
    test('scale by the days in the period', () {
      const goals = MacroGoals(calories: 2300);

      expect(goals.overWindow(MacroKind.calories, windowFor(ProgressPeriod.day)),
          2300);
      expect(
        goals.overWindow(MacroKind.calories, windowFor(ProgressPeriod.week)),
        2300 * 7,
      );
      // May 2026 has 31 days.
      expect(
        goals.overWindow(MacroKind.calories, windowFor(ProgressPeriod.month)),
        2300 * 31,
      );
    });

    test('fall back to sensible defaults when none are stored', () {
      final goals = MacroGoals.fromMap(null);
      expect(goals.calories, MacroGoals.defaultCalories);
      expect(goals.protein, MacroGoals.defaultProtein);
    });

    test('round-trip through a map', () {
      const goals = MacroGoals(calories: 2000, protein: 160, carbs: 200, fat: 70);
      final restored = MacroGoals.fromMap(goals.toMap());

      expect(restored.calories, 2000);
      expect(restored.protein, 160);
      expect(restored.carbs, 200);
      expect(restored.fat, 70);
    });

    test('a partially stored document keeps defaults for the rest', () {
      final goals = MacroGoals.fromMap(const {'calorieGoal': 1800});
      expect(goals.calories, 1800);
      expect(goals.fat, MacroGoals.defaultFat);
    });
  });

  group('macro progress', () {
    test('reports the percentage against the goal', () {
      const progress =
          MacroProgress(kind: MacroKind.calories, total: 1842, goal: 2300);
      expect(progress.percent, 80);
      expect(progress.fraction, closeTo(0.8, 0.001));
      expect(progress.isOver, isFalse);
    });

    // The bar has a fixed track, so it clamps — but the number must not, or
    // going over target would be invisible.
    test('clamps the bar but not the figure when over target', () {
      const progress =
          MacroProgress(kind: MacroKind.calories, total: 3000, goal: 2000);
      expect(progress.fraction, 1.0);
      expect(progress.percent, 150);
      expect(progress.isOver, isTrue);
    });

    test('a zero goal reads as zero rather than dividing by it', () {
      const progress =
          MacroProgress(kind: MacroKind.protein, total: 50, goal: 0);
      expect(progress.fraction, 0);
      expect(progress.percent, 0);
    });
  });

  group('insight', () {
    MealWindowSummary summaryWith({
      required int calories,
      required int protein,
    }) {
      return MealWindowSummary.from(
        meals: [
          meal(at: DateTime(2026, 5, 8, 12), calories: calories, protein: protein),
        ],
        window: windowFor(ProgressPeriod.day),
        goals: const MacroGoals(calories: 2000, protein: 100),
      );
    }

    // The line has to name the thing that is actually true, not praise
    // unconditionally — a day 60% over target is not "doing great".
    test('calls out a large overshoot', () {
      expect(
        summaryWith(calories: 3200, protein: 100).insight,
        contains('past your calorie target'),
      );
    });

    test('calls out being well under', () {
      expect(
        summaryWith(calories: 600, protein: 90).insight,
        contains('under your calorie target'),
      );
    });

    test('singles out protein when it is the one lagging', () {
      expect(
        summaryWith(calories: 1800, protein: 30).insight,
        contains('protein is the one lagging'),
      );
    });

    test('commends a balanced window', () {
      expect(
        summaryWith(calories: 1800, protein: 90).insight,
        contains('doing great'),
      );
    });
  });

  group('formatting', () {
    test('groups thousands from the right', () {
      const sep = thousandsSeparator;
      expect(formatMacroValue(1842), '1${sep}842');
      expect(formatMacroValue(2300), '2${sep}300');
      expect(formatMacroValue(132), '132');
      expect(formatMacroValue(0), '0');
      expect(formatMacroValue(1000000), '1${sep}000${sep}000');
    });

    // The separator has to be one that cannot wrap: a plain space would let
    // "1 842" break across two lines inside a narrow macro column.
    test('separates with a non-breaking character', () {
      expect(thousandsSeparator, isNot(' '));
      expect(formatMacroValue(1842), isNot(contains(' ')));
    });

    test('names the day window the way the design does', () {
      expect(
        mealWindowLabel(windowFor(ProgressPeriod.day)),
        'Today, 8 May',
      );
      expect(
        mealWindowLabel(windowFor(ProgressPeriod.day, offset: -1)),
        'Yesterday, 7 May',
      );
      expect(
        mealWindowLabel(windowFor(ProgressPeriod.day, offset: -3)),
        'Tue, 5 May',
      );
    });

    test('leaves week and month to the shared window label', () {
      expect(
        mealWindowLabel(windowFor(ProgressPeriod.month)),
        'May 2026',
      );
      expect(
        mealWindowLabel(windowFor(ProgressPeriod.week)),
        windowFor(ProgressPeriod.week).label,
      );
    });
  });
}
