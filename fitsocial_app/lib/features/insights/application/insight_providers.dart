import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/observability/app_analytics.dart';
import '../../../shared/time/period_keys.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider;
import '../data/insight_repository.dart';
import '../domain/weekly_insight.dart';

/// Whether Weekly Insights exist in the app right now: switched on in Remote
/// Config. Off, nothing about them is drawn anywhere, Settings included.
final weeklyInsightsFlagProvider = Provider<bool>(
  (ref) => ref.watch(featureEnabledProvider(FeatureFlag.weeklyInsights)),
);

/// Whether the signed-in user turned Weekly Insights off. False while it loads,
/// which is the state everybody who never touched it is in.
final insightsHiddenProvider = StreamProvider<bool>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(false);
  return ref.watch(insightRepositoryProvider).watchHidden(userId);
});

/// On, and not hidden by this user.
final weeklyInsightsEnabledProvider = Provider<bool>((ref) {
  if (!ref.watch(weeklyInsightsFlagProvider)) return false;
  return !(ref.watch(insightsHiddenProvider).valueOrNull ?? false);
});

String _dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// The week the insight is about: the last one that has finished, on the
/// phone's own calendar -- the same week the server works out from the
/// user's offset.
String lastFinishedWeekId({DateTime? today}) =>
    previousWeekId(isoWeekIdOf(_dayKey(today ?? DateTime.now())));

/// Last week's insight, or null while the server has none stored.
final weeklyInsightProvider = StreamProvider<WeeklyInsight?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null || !ref.watch(weeklyInsightsEnabledProvider)) {
    return Stream.value(null);
  }
  return ref
      .watch(insightRepositoryProvider)
      .watchInsight(userId, lastFinishedWeekId());
});

/// The user's rating of last week's insight.
final insightRatingProvider = StreamProvider<InsightRating?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(null);
  return ref
      .watch(insightRepositoryProvider)
      .watchRating(userId, lastFinishedWeekId());
});

/// Weeks this app session has already asked the server about, so a missing
/// insight is requested once, not once per rebuild.
final _requestedWeeks = <String>{};

/// Asks the server for last week's insight when none is stored -- somebody the
/// Monday job skipped, or the first open after the flag went on. The server
/// answers from its cache when it has one, so this costs a model call at most
/// once per person per week. Watched by the home card.
final insightAutoRequestProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<WeeklyInsight?>>(weeklyInsightProvider, (_, next) {
    if (!next.hasValue || next.value != null) return;
    if (!ref.read(weeklyInsightsEnabledProvider)) return;
    final weekId = lastFinishedWeekId();
    if (!_requestedWeeks.add(weekId)) return;
    ref.read(insightActionsProvider).request().ignore();
  }, fireImmediately: true);
});

class InsightActions {
  const InsightActions(this._ref);

  final Ref _ref;

  InsightRepository get _repository => _ref.read(insightRepositoryProvider);
  AppAnalytics get _analytics => _ref.read(appAnalyticsProvider);

  /// Asks for last week's insight, regenerating it when [regenerate]. Throws
  /// [InsightRefused] with a message to show when today's refreshes are used.
  Future<InsightStatus> request({bool regenerate = false}) async {
    final status = await _repository.request(regenerate: regenerate);
    if (status == InsightStatus.ready) {
      _analytics.log(AnalyticsEvent.insightGenerated, {
        'regenerated': regenerate,
      });
    }
    return status;
  }

  Future<void> rate(InsightRating rating) async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;
    await _repository.rate(userId, lastFinishedWeekId(), rating);
    _analytics.log(AnalyticsEvent.insightFeedback, {'rating': rating.key});
  }

  Future<void> setHidden(bool hidden) async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;
    await _repository.setHidden(userId, hidden);
    _analytics.log(AnalyticsEvent.insightHidden, {'hidden': hidden});
  }

  void logViewed() => _analytics.log(AnalyticsEvent.insightViewed);
}

final insightActionsProvider = Provider<InsightActions>(
  (ref) => InsightActions(ref),
);
