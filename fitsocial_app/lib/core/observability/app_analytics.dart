import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bootstrap/bootstrap_status.dart';
import '../config/app_config.dart';

/// The product events Build 11's features report.
///
/// One enum rather than strings at call sites, so the full list of what the
/// app sends is readable in one place — which is also the list the Play Data
/// Safety form and the privacy policy have to describe. Names follow Firebase's
/// rules (snake_case, at most 40 characters) and are fixed strings: renaming
/// one splits its history in the console.
///
/// Nothing sent with these may identify a person or a place. Parameters carry
/// kinds and counts — a metric name, a period, a reason — never a name, an
/// email, free text somebody typed, or coordinates.
enum AnalyticsEvent {
  goalCreated('goal_created'),
  goalCompleted('goal_completed'),
  challengeCreated('challenge_created'),
  challengeJoined('challenge_joined'),
  challengeCompleted('challenge_completed'),
  compareViewed('compare_viewed'),
  comparePeriodChanged('compare_period_changed'),
  leaderboardViewed('leaderboard_viewed'),
  leaderboardFilterChanged('leaderboard_filter_changed'),
  leaderboardOptoutToggled('leaderboard_optout_toggled'),
  insightGenerated('insight_generated'),
  insightViewed('insight_viewed'),
  insightFeedback('insight_feedback'),
  insightHidden('insight_hidden'),
  upnextShown('upnext_shown'),
  upnextTapped('upnext_tapped'),
  upnextDismissed('upnext_dismissed'),
  recapGenerated('recap_generated'),
  recapShared('recap_shared');

  const AnalyticsEvent(this.name);

  final String name;
}

/// Where product events go.
///
/// An interface for the same reason [CrashReporter] is one: widget tests run
/// with no Firebase app, and a screen that logs on open must not need one.
abstract class AppAnalytics {
  /// Records [event]. Never throws and never needs awaiting: losing an
  /// analytics event is always better than failing the action it describes.
  void log(AnalyticsEvent event, [Map<String, Object> parameters = const {}]);
}

class FirebaseAppAnalytics implements AppAnalytics {
  const FirebaseAppAnalytics();

  @override
  void log(AnalyticsEvent event, [Map<String, Object> parameters = const {}]) {
    FirebaseAnalytics.instance
        .logEvent(name: event.name, parameters: parameters)
        .catchError((_) {});
  }
}

/// Swallows everything. Tests, builds without Firebase, and any build with
/// [AppConfig.enableAnalytics] off.
class NoopAppAnalytics implements AppAnalytics {
  const NoopAppAnalytics();

  @override
  void log(AnalyticsEvent event, [Map<String, Object> parameters = const {}]) {}
}

/// Gated on [AppConfig.enableAnalytics] as well as on Firebase being up, so
/// analytics can be switched off in one place without touching a call site.
final appAnalyticsProvider = Provider<AppAnalytics>((ref) {
  final status = ref.watch(bootstrapStatusProvider);
  if (status.canUseFirebase && appConfig.enableAnalytics) {
    return const FirebaseAppAnalytics();
  }
  return const NoopAppAnalytics();
});
