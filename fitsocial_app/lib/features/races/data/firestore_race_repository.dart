import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/race_models.dart';
import 'race_mappers.dart';
import 'race_query_plan.dart';
import 'race_repository_contract.dart';

/// The running calendar, on Cloud Firestore.
///
/// The interesting part of this class is [fetchEvents], and the reason is a
/// Firestore limit: a query may carry only one disjunctive clause. The filter
/// row on the list screen offers three of them at once — provinces, distances
/// and tags — so the query has to pick which one the server answers and finish
/// the rest locally. [RaceQueryPlan] makes that choice, and keeping it in its
/// own file is what lets it be tested without a database.
class FirestoreRaceRepository implements RaceRepository {
  FirestoreRaceRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _events =>
      _firestore.collection(RaceFields.collection);

  CollectionReference<Map<String, dynamic>> _saved(String userId) => _firestore
      .collection('users')
      .doc(userId)
      .collection(RaceFields.savedSubcollection);

  @override
  Future<List<RaceEvent>> fetchEvents({
    required RaceFilter filter,
    required DateTime now,
    int limit = 200,
  }) async {
    final plan = RaceQueryPlan.from(filter: filter, now: now);

    Query<Map<String, dynamic>> query = _events
        .where(RaceFields.startAt,
            isGreaterThanOrEqualTo: Timestamp.fromDate(plan.from))
        .orderBy(RaceFields.startAt);

    final until = plan.until;
    if (until != null) {
      query = query.where(RaceFields.startAt,
          isLessThan: Timestamp.fromDate(until));
    }

    switch (plan.serverClause) {
      case RaceServerClause.provinces:
        query = query.where(
          RaceFields.province,
          whereIn: filter.provinces.map((p) => p.code).toList(growable: false),
        );
      case RaceServerClause.distances:
        query = query.where(
          RaceFields.distanceBuckets,
          arrayContainsAny:
              filter.buckets.map((b) => b.key).toList(growable: false),
        );
      case RaceServerClause.tags:
        query = query.where(
          RaceFields.tags,
          arrayContainsAny:
              filter.tags.map((t) => t.key).toList(growable: false),
        );
      case RaceServerClause.none:
        break;
    }

    final snapshot = await query.limit(plan.fetchLimit(limit)).get();

    final events = <RaceEvent>[];
    for (final doc in snapshot.docs) {
      final event = raceEventFromDoc(doc.id, doc.data());
      if (event == null) continue;
      // The lower bound is set behind today so multi-day events still in
      // progress come back — see RaceQueryPlan.from. Dropping the ones that
      // have actually finished is this line's whole job.
      if (event.isPast(now)) continue;
      if (!filter.matches(event)) continue;
      events.add(event);
      if (events.length >= limit) break;
    }

    // Already in date order from the query, which is the only order this
    // release offers. Nearest-first belongs with the map surface, and both are
    // deliberately out of scope here.
    return events;
  }

  @override
  Future<RaceEvent?> fetchEvent(String eventId) async {
    final doc = await _events.doc(eventId).get();
    return raceEventFromDoc(doc.id, doc.data());
  }

  @override
  Stream<Set<String>> watchSavedEventIds(String userId) {
    return _saved(userId).snapshots().map(
          (snapshot) => snapshot.docs.map((doc) => doc.id).toSet(),
        );
  }

  @override
  Stream<List<RaceEvent>> watchSavedEvents(String userId) {
    // Two hops rather than a denormalised copy of the event on the save
    // document. A saved race is exactly the thing most likely to change after
    // you save it — a postponement, a sold-out flag — and a snapshot taken at
    // save time would show the runner the stale version of the one event they
    // care most about being right.
    return _saved(userId).snapshots().asyncMap((snapshot) async {
      final ids = snapshot.docs.map((doc) => doc.id).toList(growable: false);
      if (ids.isEmpty) return const <RaceEvent>[];

      final events = <RaceEvent>[];
      // whereIn caps at 30 values, so saved races are read in pages of 30.
      for (var start = 0; start < ids.length; start += 30) {
        final page = ids.sublist(start, (start + 30).clamp(0, ids.length));
        final docs =
            await _events.where(FieldPath.documentId, whereIn: page).get();
        for (final doc in docs.docs) {
          final event = raceEventFromDoc(doc.id, doc.data());
          if (event != null) events.add(event);
        }
      }

      events.sort((a, b) => a.startAt.compareTo(b.startAt));
      return events;
    });
  }

  @override
  Future<void> setSaved({
    required String userId,
    required String eventId,
    required bool saved,
  }) async {
    final doc = _saved(userId).doc(eventId);
    if (!saved) {
      await doc.delete();
      return;
    }
    await doc.set({'savedAt': FieldValue.serverTimestamp()});
  }

  @override
  Future<void> recordEntryTap({
    required String userId,
    required String eventId,
    String? platform,
  }) async {
    // One unconditional merge, so a tap costs a single write with no read and no
    // transaction. `taps` increments and `lastTapAt` moves; the Cloud Function
    // reads the gap between the old and new timestamp to decide whether this tap
    // counts towards the public total, and fills in firstTapAt.
    await _firestore
        .collection('users')
        .doc(userId)
        .collection(RaceFields.tapsSubcollection)
        .doc(eventId)
        .set({
      RaceFields.eventId: eventId,
      RaceFields.lastTapAt: FieldValue.serverTimestamp(),
      RaceFields.taps: FieldValue.increment(1),
      RaceFields.tapRef: newEntryTapRef(),
      if (platform != null) RaceFields.entryPlatform: platform,
    }, SetOptions(merge: true));
  }

  @override
  Future<void> submitRace({
    required String userId,
    required RaceSubmission submission,
  }) async {
    await _firestore
        .collection(RaceFields.submissions)
        .add(raceSubmissionToDoc(userId, submission));
  }
}
