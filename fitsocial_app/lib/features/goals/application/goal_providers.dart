import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/observability/app_analytics.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider;
import '../data/goal_repository.dart';
import '../domain/goal.dart';

/// Whether goals are part of the app right now. Off until switched on in
/// Remote Config.
final goalsEnabledProvider = Provider<bool>(
  (ref) => ref.watch(featureEnabledProvider(FeatureFlag.goalsChallenges)),
);

/// The signed-in user's running goals. Empty when goals are switched off or
/// nobody is signed in.
final activeGoalsProvider = StreamProvider<List<Goal>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null || !ref.watch(goalsEnabledProvider)) {
    return Stream.value(const []);
  }
  return ref.watch(goalRepositoryProvider).watchActiveGoals(userId);
});

/// The largest number of goals running at once. Mirrors MAX_ACTIVE_GOALS in
/// functions/goals.js, so the app can say so before asking.
const int kMaxActiveGoals = 10;

class GoalActions {
  const GoalActions(this._ref);

  final Ref _ref;

  GoalRepository get _repository => _ref.read(goalRepositoryProvider);
  AppAnalytics get _analytics => _ref.read(appAnalyticsProvider);

  /// Creates a goal. Throws [GoalRejected] with a message to show when the
  /// server refuses it.
  Future<void> create({
    required GoalMetric metric,
    required GoalPeriod period,
    required int target,
    String? startDayKey,
    String? endDayKey,
  }) async {
    await _repository.createGoal(
      metric: metric,
      period: period,
      target: target,
      startDayKey: startDayKey,
      endDayKey: endDayKey,
    );
    _analytics.log(AnalyticsEvent.goalCreated, {
      'metric': metric.key,
      'period': period.key,
    });
  }

  Future<void> archive(Goal goal) async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;
    await _repository.archiveGoal(userId, goal.id);
  }
}

final goalActionsProvider = Provider<GoalActions>((ref) => GoalActions(ref));

/// Logs `goal_completed` when a goal the app is watching flips to hit.
///
/// Completion is decided on the server, so the app only sees it arrive. The
/// first snapshot is taken as the baseline and never logged, so opening the
/// app on a week that was already hit does not count it a second time.
final goalCompletionLoggerProvider = Provider<void>((ref) {
  Map<String, bool>? seen;
  ref.listen<AsyncValue<List<Goal>>>(activeGoalsProvider, (_, next) {
    final goals = next.valueOrNull;
    if (goals == null) return;
    final now = {for (final goal in goals) goal.id: goal.completedCurrent};
    final before = seen;
    seen = now;
    if (before == null) return;
    for (final goal in goals) {
      if (goal.completedCurrent && before[goal.id] == false) {
        ref.read(appAnalyticsProvider).log(AnalyticsEvent.goalCompleted, {
          'metric': goal.metric.key,
          'period': goal.period.key,
        });
      }
    }
  }, fireImmediately: true);
});
