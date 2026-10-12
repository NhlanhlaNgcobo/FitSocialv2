import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/core/observability/app_analytics.dart';
import 'package:fitsocial_app/features/goals/application/goal_providers.dart';
import 'package:fitsocial_app/features/goals/data/goal_repository.dart';
import 'package:fitsocial_app/features/goals/domain/goal.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';

/// "Days a week" from sign-up, kept as one weekly training-days goal the
/// server counts: created once, left alone when unchanged, replaced when the
/// answer moves.
void main() {
  late _FakeGoals repository;

  ProviderContainer container({bool enabled = true}) {
    final container = ProviderContainer(overrides: [
      goalRepositoryProvider.overrideWithValue(repository),
      currentUserIdProvider.overrideWithValue('uid_test'),
      goalsEnabledProvider.overrideWithValue(enabled),
      appAnalyticsProvider.overrideWithValue(const NoopAppAnalytics()),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Goal goal(String id, GoalMetric metric, int target) => Goal(
        id: id,
        metric: metric,
        period: GoalPeriod.weekly,
        target: target,
        status: GoalStatus.active,
      );

  setUp(() => repository = _FakeGoals());

  test('creates a weekly training-days goal at the answer', () async {
    await container().read(goalActionsProvider).syncTrainingDays(4);
    expect(repository.created, [(GoalMetric.activeDays, GoalPeriod.weekly, 4)]);
    expect(repository.archived, isEmpty);
  });

  test('leaves one at the same target alone', () async {
    repository.running = [goal('g1', GoalMetric.activeDays, 4)];
    await container().read(goalActionsProvider).syncTrainingDays(4);
    expect(repository.created, isEmpty);
    expect(repository.archived, isEmpty);
  });

  test('replaces one at a different target', () async {
    repository.running = [goal('g1', GoalMetric.activeDays, 3)];
    await container().read(goalActionsProvider).syncTrainingDays(5);
    expect(repository.archived, ['g1']);
    expect(repository.created, [(GoalMetric.activeDays, GoalPeriod.weekly, 5)]);
  });

  test('never touches the user\'s other goals', () async {
    repository.running = [goal('steps', GoalMetric.steps, 50000)];
    await container().read(goalActionsProvider).syncTrainingDays(4);
    expect(repository.archived, isEmpty);
    expect(repository.created, hasLength(1));
  });

  test('does nothing while goals are switched off', () async {
    await container(enabled: false)
        .read(goalActionsProvider)
        .syncTrainingDays(4);
    expect(repository.created, isEmpty);
  });

  test('the metric reads back from the server name', () {
    expect(GoalMetric.byKey('active_days'), GoalMetric.activeDays);
    expect(GoalMetric.activeDays.suggestedTarget(GoalPeriod.weekly), 4);
  });
}

class _FakeGoals implements GoalRepository {
  List<Goal> running = const [];
  final created = <(GoalMetric, GoalPeriod, int)>[];
  final archived = <String>[];

  @override
  Stream<List<Goal>> watchActiveGoals(String userId) => Stream.value(running);

  @override
  Future<String> createGoal({
    required GoalMetric metric,
    required GoalPeriod period,
    required int target,
    String? startDayKey,
    String? endDayKey,
  }) async {
    created.add((metric, period, target));
    return 'new';
  }

  @override
  Future<void> archiveGoal(String userId, String goalId) async =>
      archived.add(goalId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
