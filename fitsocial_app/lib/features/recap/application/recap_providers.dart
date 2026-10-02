import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/feature_flags.dart';
import '../../../shared/time/period_keys.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider, displayNameProvider;
import '../data/recap_repository.dart';
import '../domain/recap.dart';

/// Whether Recap Cards are part of the app right now. Off, no share button
/// for one is drawn anywhere.
final recapCardsEnabledProvider = Provider<bool>(
  (ref) => ref.watch(featureEnabledProvider(FeatureFlag.recapCards)),
);

/// The signed-in user's public name, for the card's signature.
final recapDisplayNameProvider = FutureProvider<String?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  return ref.watch(displayNameProvider(userId).future);
});

String _dayKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// The week a weekly recap is about: the last one that has finished.
String recapWeekId({DateTime? today}) =>
    previousWeekId(isoWeekIdOf(_dayKey(today ?? DateTime.now())));

/// Last week's recap card, or null when the week had nothing in it or the
/// feature is off.
final lastWeekRecapProvider = FutureProvider<RecapCardData?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null || !ref.watch(recapCardsEnabledProvider)) return null;
  final repository = ref.watch(recapRepositoryProvider);
  final weekId = recapWeekId();
  final results = await Future.wait<Object?>([
    repository.weekStats(userId, weekId),
    repository.weeklyGoalsHit(userId, weekId),
    ref.watch(recapDisplayNameProvider.future),
  ]);
  return weekRecapFrom(
    results[0] as Map<String, dynamic>?,
    goalsHit: results[1] as int,
    displayName: results[2] as String?,
  );
});
