import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/meal_repeat.dart';
import 'package:fitsocial_app/features/main/domain/meal_tracking.dart';
import 'package:fitsocial_app/features/main/presentation/meal_tracking_screen.dart';

class _StubMeals extends UnconfiguredContentRepository {
  _StubMeals({required this.meals, List<MealRepeat>? repeats})
      : repeats = [...?repeats];

  final List<LoggedMeal> meals;
  final List<MealRepeat> repeats;
  final List<LoggedMeal> relogged = [];
  final List<String> deleted = [];

  @override
  Future<List<LoggedMeal>> getLoggedMeals() async => meals;

  @override
  Future<MacroGoals> getMacroGoals() async => const MacroGoals();

  @override
  Future<void> relogMeal(LoggedMeal meal) async => relogged.add(meal);

  @override
  Future<List<MealRepeat>> getMealRepeats() async => [...repeats];

  @override
  Future<void> saveMealRepeat(MealRepeat repeat) async {
    repeats
      ..removeWhere((existing) => existing.id == repeat.id)
      ..add(repeat);
  }

  @override
  Future<void> deleteMealRepeat(String id) async {
    deleted.add(id);
    repeats.removeWhere((repeat) => repeat.id == id);
  }
}

const _oats = MealFoodItem(
  name: 'oats',
  grams: 250,
  calories: 178,
  protein: 6,
  carbs: 30,
  fat: 4,
  category: 'starch',
);

LoggedMeal _breakfast({String? repeatId}) {
  final now = DateTime.now();
  return LoggedMeal(
    id: 'breakfast',
    name: 'Oats',
    loggedAt: DateTime(now.year, now.month, now.day, 0, 5),
    calories: 178,
    protein: 6,
    carbs: 30,
    fat: 4,
    items: const [_oats],
    repeatId: repeatId,
  );
}

MealRepeat _repeat({
  Set<int> weekdays = const {1, 2, 3, 4, 5},
  int hour = 8,
  int minute = 0,
  String? lastLoggedDay,
}) {
  return MealRepeat(
    id: 'r1',
    name: 'Oats',
    weekdays: weekdays,
    hour: hour,
    minute: minute,
    calories: 178,
    protein: 6,
    carbs: 30,
    fat: 4,
    items: const [_oats],
    lastLoggedDay: lastLoggedDay,
  );
}

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

/// Lets a toast run its course so no timer is left pending.
Future<void> _settleToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  group('MealRepeat', () {
    // 2026-10-05 is a Monday.
    final monday9am = DateTime(2026, 10, 5, 9);

    test('is due on its days once its time has passed', () {
      final repeat = _repeat();
      expect(repeat.isDueAt(monday9am), isTrue);
      expect(repeat.isDueAt(DateTime(2026, 10, 5, 7, 59)), isFalse);
      // Saturday.
      expect(repeat.isDueAt(DateTime(2026, 10, 10, 9)), isFalse);
    });

    test('is not due twice on the same day', () {
      final repeat = _repeat(lastLoggedDay: '2026-10-05');
      expect(repeat.isDueAt(monday9am), isFalse);
      expect(repeat.isDueAt(DateTime(2026, 10, 6, 9)), isTrue);
    });

    test('a repeat made from a meal starts tomorrow', () {
      final meal = _breakfast();
      final now = DateTime.now();
      final repeat = MealRepeat.fromMeal(
        meal,
        id: 'x',
        weekdays: const {1, 2, 3, 4, 5, 6, 7},
        today: now,
      );
      expect(repeat.hour, 0);
      expect(repeat.minute, 5);
      expect(repeat.items, [_oats]);
      expect(repeat.isDueAt(now), isFalse);
      expect(repeat.isDueAt(now.add(const Duration(days: 1))), isTrue);
    });

    test('lands at its own time on the day it is logged', () {
      expect(_repeat(hour: 7, minute: 30).timeOn(monday9am),
          DateTime(2026, 10, 5, 7, 30));
    });

    test('describes its schedule the way people say it', () {
      expect(_repeat(weekdays: {1, 2, 3, 4, 5, 6, 7}).scheduleLabel,
          'Every day at 08:00');
      expect(_repeat().scheduleLabel, 'Weekdays at 08:00');
      expect(_repeat(weekdays: {6, 7}).daysLabel, 'Weekends');
      expect(_repeat(weekdays: {5, 1, 3}).daysLabel, 'Mon, Wed, Fri');
    });

    test('survives a save and a read back', () {
      final repeat = _repeat(lastLoggedDay: '2026-10-05');
      final read = MealRepeat.fromMap(repeat.toMap())!;
      expect(read.weekdays, repeat.weekdays);
      expect(read.timeLabel, '08:00');
      expect(read.lastLoggedDay, '2026-10-05');
      expect(read.items.single.category, 'starch');
    });

    test('a stored repeat with no valid days is dropped', () {
      expect(
        MealRepeat.fromMap({'id': 'r', 'weekdays': [0, 9]}),
        isNull,
      );
    });
  });

  group('meal tracking actions', () {
    testWidgets('logs a meal again from its options', (tester) async {
      final repository = _StubMeals(meals: [_breakfast()]);
      await _pump(tester, repository);

      await tester.tap(find.byTooltip('Meal options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log again now'));
      await tester.pumpAndSettle();

      expect(repository.relogged.single.id, 'breakfast');
      expect(find.text('Oats logged again.'), findsOneWidget);
      await _settleToast(tester);
    });

    testWidgets('sets a meal to repeat every day at the time it was eaten',
        (tester) async {
      final repository = _StubMeals(meals: [_breakfast()]);
      await _pump(tester, repository);

      await tester.tap(find.byTooltip('Meal options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Repeat this meal'));
      await tester.pumpAndSettle();

      expect(find.text('Every day at 00:05'), findsOneWidget);
      await tester.tap(find.text('Start repeating'));
      await tester.pumpAndSettle();

      final saved = repository.repeats.single;
      expect(saved.weekdays, {1, 2, 3, 4, 5, 6, 7});
      expect(saved.timeLabel, '00:05');
      expect(saved.lastLoggedDay, MealRepeat.dayKey(DateTime.now()));
      // The new repeat shows in its own panel.
      expect(find.text('Repeating Meals'), findsOneWidget);
      await _settleToast(tester);
    });

    testWidgets('a day can be taken out before saving', (tester) async {
      final repository = _StubMeals(meals: [_breakfast()]);
      await _pump(tester, repository);

      await tester.tap(find.byTooltip('Meal options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Repeat this meal'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Sun'));
      await tester.tap(find.bySemanticsLabel('Sat'));
      await tester.pumpAndSettle();

      expect(find.text('Weekdays at 00:05'), findsOneWidget);
      await tester.tap(find.text('Start repeating'));
      await tester.pumpAndSettle();
      expect(repository.repeats.single.weekdays, {1, 2, 3, 4, 5});
      await _settleToast(tester);
    });

    testWidgets('a repeat can be stopped from its row', (tester) async {
      final repository = _StubMeals(meals: const [], repeats: [_repeat()]);
      await _pump(tester, repository);

      expect(find.text('Weekdays at 08:00'), findsOneWidget);
      await tester.tap(find.text('Weekdays at 08:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop repeating'));
      await tester.pumpAndSettle();

      expect(repository.deleted, ['r1']);
      expect(find.text('Repeating Meals'), findsNothing);
      await _settleToast(tester);
    });

    testWidgets('no repeats, no panel', (tester) async {
      await _pump(tester, _StubMeals(meals: [_breakfast()]));
      expect(find.text('Repeating Meals'), findsNothing);
    });

    testWidgets('a meal a repeat logged is marked as one', (tester) async {
      await _pump(tester, _StubMeals(meals: [_breakfast(repeatId: 'r1')]));
      expect(find.byIcon(Icons.event_repeat_rounded), findsOneWidget);
    });
  });
}
