import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/observability/app_analytics.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider;
import '../data/up_next_repository.dart';
import '../domain/up_next.dart';

/// Whether Up Next is part of the app right now.
final upNextEnabledProvider = Provider<bool>(
  (ref) => ref.watch(featureEnabledProvider(FeatureFlag.upNext)),
);

/// Today on the phone's calendar, `YYYY-MM-DD` -- the key the server files
/// today's suggestions under, worked out from the same offset.
String upNextDayKey({DateTime? now}) {
  final date = now ?? DateTime.now();
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// Today's suggestions, dismissed ones left out. Empty while switched off.
final upNextProvider = StreamProvider<List<UpNextSuggestion>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null || !ref.watch(upNextEnabledProvider)) {
    return Stream.value(const []);
  }
  return ref.watch(upNextRepositoryProvider).watchDay(userId, upNextDayKey());
});

/// How long a rebuild on the server is trusted before home asks again. The
/// time-of-day rules move on the hour at the finest, so this is plenty.
const Duration kUpNextRefreshEvery = Duration(minutes: 15);

DateTime? _lastRefresh;
final _shownToday = <String>{};

class UpNextActions {
  const UpNextActions(this._ref);

  final Ref _ref;

  AppAnalytics get _analytics => _ref.read(appAnalyticsProvider);

  /// Asks the server to rebuild today's suggestions, at most every
  /// [kUpNextRefreshEvery]. Called when home appears and when the app comes
  /// back to the foreground: two of the rules depend on the time of day, and
  /// nothing on the server fires at noon.
  void maybeRefresh({DateTime? now}) {
    if (!_ref.read(upNextEnabledProvider)) return;
    if (_ref.read(currentUserIdProvider) == null) return;
    final at = now ?? DateTime.now();
    final last = _lastRefresh;
    if (last != null && at.difference(last) < kUpNextRefreshEvery) return;
    _lastRefresh = at;
    _ref.read(upNextRepositoryProvider).refresh().ignore();
  }

  /// Logs `upnext_shown` once per suggestion per day.
  void shown(UpNextSuggestion suggestion) {
    if (!_shownToday.add('${upNextDayKey()}|${suggestion.id}')) return;
    _analytics.log(AnalyticsEvent.upnextShown, {'kind': suggestion.kind});
  }

  void tapped(UpNextSuggestion suggestion) =>
      _analytics.log(AnalyticsEvent.upnextTapped, {'kind': suggestion.kind});

  Future<void> dismiss(UpNextSuggestion suggestion) async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;
    await _ref
        .read(upNextRepositoryProvider)
        .dismiss(userId, upNextDayKey(), suggestion.id);
    _analytics.log(AnalyticsEvent.upnextDismissed, {'kind': suggestion.kind});
  }
}

final upNextActionsProvider =
    Provider<UpNextActions>((ref) => UpNextActions(ref));
