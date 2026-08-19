import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/app_session.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider;
import '../data/race_repository.dart';
import '../domain/race_models.dart';

/// The filter row's current state.
///
/// Held above the list screen so the selection survives a trip into an event
/// and back. Somebody who filtered to Western Cape halfs, opened one and came
/// back to an unfiltered list would have to do the work twice.
final raceFilterProvider =
    StateNotifierProvider<RaceFilterController, RaceFilter>((ref) {
  return RaceFilterController();
});

class RaceFilterController extends StateNotifier<RaceFilter> {
  RaceFilterController() : super(const RaceFilter());

  void setTimeframe(RaceTimeframe timeframe) =>
      state = state.copyWith(timeframe: timeframe);

  void toggleProvince(Province province) => state = state.toggleProvince(province);

  void toggleBucket(DistanceBucket bucket) => state = state.toggleBucket(bucket);

  void toggleTag(RaceTag tag) => state = state.toggleTag(tag);

  void setQuery(String query) => state = state.copyWith(query: query);

  void clear() => state = const RaceFilter();
}

/// The day the calendar is being read on.
///
/// A provider rather than `DateTime.now()` inside the query, for two reasons: a
/// test can pin it, and every widget in one build reads the same instant. The
/// second matters more than it looks — "this week" resolving differently for the
/// header and the query would put events in the list that the header says are
/// out of range.
final raceClockProvider = Provider<DateTime>((ref) => DateTime.now());

/// The filtered calendar page.
///
/// A `FutureProvider` keyed on the filter, so changing a chip refetches and
/// Riverpod holds the previous result while it does. Autodisposed on a delay
/// by the list screen's `keepAlive`, which is what makes going back from an
/// event free rather than a second read.
final raceEventsProvider = FutureProvider<List<RaceEvent>>((ref) async {
  final filter = ref.watch(raceFilterProvider);
  final repository = ref.watch(raceRepositoryProvider);
  // Not watched: re-reading the clock on every rebuild would refetch the list
  // whenever anything else in the tree changed. The page is pinned to the
  // instant it was requested, and pull-to-refresh is how it moves on.
  final now = ref.read(raceClockProvider);
  return repository.fetchEvents(filter: filter, now: now);
});

/// One event, for the detail screen.
final raceEventProvider =
    FutureProvider.family<RaceEvent?, String>((ref, eventId) async {
  // The list already holds it in most cases — arriving at a detail screen
  // almost always means tapping a row. Serving it from there makes the
  // transition instant and saves the read; a deep link falls through to fetch.
  final cached = ref.watch(raceEventsProvider).valueOrNull;
  if (cached != null) {
    for (final event in cached) {
      if (event.id == eventId) return event;
    }
  }
  return ref.watch(raceRepositoryProvider).fetchEvent(eventId);
});

/// The ids the signed-in user has saved.
final savedRaceIdsProvider = StreamProvider<Set<String>>((ref) {
  // Re-subscribe across sign-in and sign-out: whose saves these are is decided
  // by who is signed in, so the answer is wrong the moment that changes.
  ref.watch(appSessionProvider);

  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const <String>{});
  return ref.watch(raceRepositoryProvider).watchSavedEventIds(userId);
});

/// The events the signed-in user has saved, soonest first.
final savedRacesProvider = StreamProvider<List<RaceEvent>>((ref) {
  ref.watch(appSessionProvider);

  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const <RaceEvent>[]);
  return ref.watch(raceRepositoryProvider).watchSavedEvents(userId);
});

/// Whether one event is saved.
final raceIsSavedProvider = Provider.family<bool, String>((ref, eventId) {
  final ids = ref.watch(savedRaceIdsProvider).valueOrNull;
  return ids != null && ids.contains(eventId);
});

/// The next saved race, for the countdown on other screens.
///
/// Exposed here rather than computed at a use site so every surface that wants
/// to mention the user's next race agrees on which one it is.
final nextSavedRaceProvider = Provider<RaceEvent?>((ref) {
  final saved = ref.watch(savedRacesProvider).valueOrNull;
  if (saved == null || saved.isEmpty) return null;
  final now = ref.watch(raceClockProvider);
  for (final event in saved) {
    if (!event.isPast(now)) return event;
  }
  return null;
});

/// Saving and unsaving, and filing a submission.
final raceActionsProvider = Provider<RaceActions>((ref) => RaceActions(ref));

class RaceActions {
  RaceActions(this._ref);

  final Ref _ref;

  /// Flips whether [eventId] is saved. Returns the new state.
  ///
  /// Throws when nobody is signed in. The button is not offered to a signed-out
  /// user, so reaching this is a programming error rather than a state to
  /// handle quietly.
  Future<bool> toggleSaved(String eventId) async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) {
      throw StateError('Sign in to save a race.');
    }
    final saved = _ref.read(raceIsSavedProvider(eventId));
    await _ref.read(raceRepositoryProvider).setSaved(
          userId: userId,
          eventId: eventId,
          saved: !saved,
        );
    return !saved;
  }

  /// Notes that the user tapped through to enter [event].
  ///
  /// Deliberately swallows every failure. This is measurement the user did not
  /// ask for, running alongside the one thing they did — opening the entry page.
  /// A dropped tap costs a row in a report; a thrown one would cost the user
  /// their race entry.
  ///
  /// Not awaited by its caller either, so a slow write never delays the browser
  /// opening.
  Future<void> recordEntryTap(RaceEvent event) async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;
    try {
      await _ref.read(raceRepositoryProvider).recordEntryTap(
            userId: userId,
            eventId: event.id,
            platform: event.entryPlatform,
          );
    } catch (_) {
      // Nothing to tell the user and nothing to retry: the next tap writes again.
    }
  }

  Future<void> submit(RaceSubmission submission) async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) {
      throw StateError('Sign in to submit a race.');
    }
    await _ref
        .read(raceRepositoryProvider)
        .submitRace(userId: userId, submission: submission);
  }
}
