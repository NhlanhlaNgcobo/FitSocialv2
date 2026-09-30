import 'dart:async';

import 'package:fitsocial_app/core/config/feature_flags.dart';
import 'package:fitsocial_app/features/goals/data/goal_repository.dart';
import 'package:fitsocial_app/features/goals/domain/goal.dart';
import 'package:fitsocial_app/features/goals/presentation/goals_home_card.dart';
import 'package:fitsocial_app/features/goals/presentation/goals_screen.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGoalRepository implements GoalRepository {
  _FakeGoalRepository([List<Goal> goals = const []]) : _current = goals;

  // The current list is handed to every new listener first, the way a
  // Firestore snapshot stream starts with what is already there. A broadcast
  // stream alone would drop anything added before the screen subscribed.
  List<Goal> _current;
  final _updates = StreamController<List<Goal>>.broadcast();
  final created = <Map<String, Object?>>[];
  final archived = <String>[];
  String? rejectWith;

  @override
  Stream<List<Goal>> watchActiveGoals(String userId) async* {
    yield _current;
    yield* _updates.stream;
  }

  void emit(List<Goal> goals) {
    _current = goals;
    _updates.add(goals);
  }

  @override
  Future<String> createGoal({
    required GoalMetric metric,
    required GoalPeriod period,
    required int target,
    String? startDayKey,
    String? endDayKey,
  }) async {
    if (rejectWith != null) throw GoalRejected(rejectWith!);
    created.add({
      'metric': metric,
      'period': period,
      'target': target,
      'startDayKey': startDayKey,
      'endDayKey': endDayKey,
    });
    return 'new-goal';
  }

  @override
  Future<void> archiveGoal(String userId, String goalId) async {
    archived.add(goalId);
  }
}

Goal _goal({
  String id = 'g1',
  GoalMetric metric = GoalMetric.workouts,
  GoalPeriod period = GoalPeriod.weekly,
  int target = 4,
  int progress = 2,
  bool completed = false,
  int completions = 0,
}) =>
    Goal(
      id: id,
      metric: metric,
      period: period,
      target: target,
      status: GoalStatus.active,
      progress: progress,
      completedCurrent: completed,
      completions: completions,
    );

Widget _host(
  Widget child,
  _FakeGoalRepository repository, {
  bool enabled = true,
}) {
  final flags =
      FeatureFlags.defaults.withFlag(FeatureFlag.goalsChallenges, enabled);
  return ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      goalRepositoryProvider.overrideWithValue(repository),
      featureFlagsProvider.overrideWith((ref) => Stream.value(flags)),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('Goal', () {
    test('reads what the server writes', () {
      final goal = Goal.fromMap('g', {
        'metric': 'active_minutes',
        'period': 'monthly',
        'target': 600,
        'status': 'active',
        'progress': 150,
        'completedCurrent': false,
        'completions': 2,
      })!;
      expect(goal.metric, GoalMetric.activeMinutes);
      expect(goal.period, GoalPeriod.monthly);
      expect(goal.fraction, 0.25);
      expect(goal.remaining, 450);
      expect(goal.progressLabel, '150 / 600 min');
      expect(goal.title, '600 min monthly');
    });

    test('a goal from a newer build is skipped rather than shown wrongly', () {
      expect(
        Goal.fromMap('g', {'metric': 'sleep', 'period': 'weekly', 'target': 7}),
        isNull,
      );
      expect(
        Goal.fromMap('g', {'metric': 'steps', 'period': 'weekly', 'target': 0}),
        isNull,
      );
    });

    test('progress past the target is capped at full and nothing to go', () {
      final goal = _goal(target: 4, progress: 6);
      expect(goal.fraction, 1.0);
      expect(goal.remaining, 0);
      expect(goal.isHit, isTrue);
    });

    test('wire names match the server', () {
      expect(GoalMetric.values.map((m) => m.key), [
        'steps',
        'active_minutes',
        'workouts',
        'meals_logged',
        'streak',
      ]);
      expect(
        GoalPeriod.values.map((p) => p.key),
        ['weekly', 'monthly', 'annual', 'custom'],
      );
    });
  });

  group('GoalsScreen', () {
    testWidgets('says what to do when there are no goals', (tester) async {
      await tester.pumpWidget(
        _host(const GoalsScreen(), _FakeGoalRepository()),
      );
      await tester.pumpAndSettle();
      expect(find.text('No goals yet'), findsOneWidget);
      expect(find.text('Set a goal'), findsOneWidget);
    });

    testWidgets('shows each goal with its progress', (tester) async {
      await tester.pumpWidget(
        _host(
          const GoalsScreen(),
          _FakeGoalRepository([
            _goal(),
            _goal(
              id: 'g2',
              metric: GoalMetric.steps,
              target: 50000,
              progress: 50000,
              completed: true,
              completions: 3,
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 / 4 sessions'), findsOneWidget);
      expect(find.text('2 to go'), findsOneWidget);
      expect(find.text('50,000 / 50,000 steps'), findsOneWidget);
      expect(find.text('Done this week'), findsOneWidget);
      expect(find.text('Hit 3 times so far'), findsOneWidget);
    });

    testWidgets('creates a goal with the chosen metric and target',
        (tester) async {
      final repository = _FakeGoalRepository();
      await tester.pumpWidget(_host(const GoalsScreen(), repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New goal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Steps'));
      await tester.pumpAndSettle();
      // The suggested target follows the metric until it is typed over.
      expect(find.widgetWithText(TextField, '50000'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '70000');
      await tester.tap(find.text('Set goal'));
      await tester.pumpAndSettle();

      expect(repository.created, [
        {
          'metric': GoalMetric.steps,
          'period': GoalPeriod.weekly,
          'target': 70000,
          'startDayKey': null,
          'endDayKey': null,
        },
      ]);
      expect(find.text('New goal'), findsOneWidget, reason: 'sheet closed');
    });

    testWidgets('shows the server\'s reason when a goal is refused',
        (tester) async {
      final repository = _FakeGoalRepository()
        ..rejectWith = 'That target is more than the period can hold.';
      await tester.pumpWidget(_host(const GoalsScreen(), repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New goal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set goal'));
      await tester.pumpAndSettle();

      expect(
        find.text('That target is more than the period can hold.'),
        findsOneWidget,
      );
      expect(find.text('Set goal'), findsOneWidget, reason: 'sheet stays open');
    });

    testWidgets('archives a goal after asking', (tester) async {
      final repository = _FakeGoalRepository([_goal()]);
      await tester.pumpWidget(_host(const GoalsScreen(), repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Goal options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive goal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();

      expect(repository.archived, ['g1']);
    });
  });

  group('GoalsHomeCard', () {
    testWidgets('draws nothing while goals are switched off', (tester) async {
      await tester.pumpWidget(
        _host(
          const GoalsHomeCard(),
          _FakeGoalRepository([_goal()]),
          enabled: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('GOALS'), findsNothing);
      expect(tester.getSize(find.byType(GoalsHomeCard)), Size.zero);
    });

    testWidgets('shows rings for running goals when on', (tester) async {
      await tester.pumpWidget(
        _host(
          const GoalsHomeCard(),
          _FakeGoalRepository([
            _goal(),
            _goal(id: 'g2', metric: GoalMetric.steps),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('GOALS'), findsOneWidget);
      expect(find.text('50%'), findsNWidgets(2));
    });

    testWidgets('invites a first goal when there are none', (tester) async {
      await tester.pumpWidget(
        _host(const GoalsHomeCard(), _FakeGoalRepository()),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Set a target for the week and watch it fill up.'),
        findsOneWidget,
      );
    });
  });
}
