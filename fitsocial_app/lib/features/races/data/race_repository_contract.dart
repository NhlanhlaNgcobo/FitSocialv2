import '../domain/race_models.dart';

/// Storage and retrieval for the running calendar.
///
/// Reads dominate, and that is the design. The event collection is editorial
/// content: it is written by the ingest script under the Admin SDK and by a
/// moderator promoting a submission, never by the app. What a client is allowed
/// to write is its own two things — which races it has saved, and a submission
/// asking for a race to be added.
abstract class RaceRepository {
  /// Upcoming events matching [filter], soonest first.
  ///
  /// A one-shot read rather than a stream. The calendar changes a few times a
  /// week, not a few times a minute, and a snapshot listener on a query this
  /// broad would bill continuously for data that is functionally static. The
  /// list screen pulls to refresh instead.
  ///
  /// [limit] caps the result set. Firestore can only serve part of a compound
  /// filter, so the remainder is applied on what comes back — see
  /// [RaceFilter.matches]. That means the implementation may over-fetch and
  /// return fewer than [limit] rows.
  Future<List<RaceEvent>> fetchEvents({
    required RaceFilter filter,
    required DateTime now,
    int limit = 200,
  });

  /// One event. Null when the id is unknown, which a stale share link will be.
  Future<RaceEvent?> fetchEvent(String eventId);

  /// The events [userId] has saved, soonest first.
  ///
  /// Streamed, unlike the calendar itself: this one is small, personal, and has
  /// to reflect a tap on the save button immediately.
  Stream<List<RaceEvent>> watchSavedEvents(String userId);

  /// The ids [userId] has saved.
  ///
  /// Separate from [watchSavedEvents] because the list rows need to know which
  /// of them are saved without paying to load the saved events themselves.
  Stream<Set<String>> watchSavedEventIds(String userId);

  /// Saves or unsaves an event for [userId].
  Future<void> setSaved({
    required String userId,
    required String eventId,
    required bool saved,
  });

  /// Records that [userId] tapped through to enter [eventId].
  ///
  /// Writes to the user's own document and nowhere else. A Cloud Function turns
  /// those private records into an anonymous per-race total, which is what makes
  /// referred volume reportable without publishing a log of who is interested in
  /// entering what.
  ///
  /// What this measures is intent. Once the runner leaves for the entry page only
  /// that platform knows whether they paid, so nothing derived from this may be
  /// called a conversion.
  ///
  /// Never throws. A tap that fails to record must not interfere with opening the
  /// entry page, which is the thing the user actually asked for.
  Future<void> recordEntryTap({
    required String userId,
    required String eventId,
    String? platform,
  });

  /// Files a submission for moderation.
  ///
  /// Returns nothing useful on purpose: the rules let a user create a
  /// submission and never read one back, so there is no state here for the app
  /// to follow. The screen says thank you and closes.
  Future<void> submitRace({
    required String userId,
    required RaceSubmission submission,
  });
}
