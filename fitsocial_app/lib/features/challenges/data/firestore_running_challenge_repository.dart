import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/running_challenge.dart';
import 'running_challenge_repository_contract.dart';

/// User-created running challenges, on Cloud Firestore.
///
/// Reads dominate this class for the same reason they dominate
/// [FirestoreChallengeRepository]: the engine that decides outcomes runs in
/// Cloud Functions. What is here is the handful of writes a client is permitted
/// — creating a challenge, inviting somebody, and moving your own status
/// between invited, active, declined and left. Every counter is written by
/// `functions/running_challenges.js` and refused to clients in firestore.rules.
class FirestoreRunningChallengeRepository
    implements RunningChallengeRepository {
  FirestoreRunningChallengeRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _challenges =>
      _firestore.collection('challenges');

  DocumentReference<Map<String, dynamic>> _challenge(String id) =>
      _challenges.doc(id);

  CollectionReference<Map<String, dynamic>> _participants(String challengeId) =>
      _challenge(challengeId).collection('participants');

  DocumentReference<Map<String, dynamic>> _participant(
    String challengeId,
    String userId,
  ) =>
      _participants(challengeId).doc(userId);

  @override
  Stream<List<RunningChallenge>> watchPublicChallenges({int limit = 40}) {
    // Both filters are load-bearing. The rules cannot filter a list query, so a
    // query that could return a private challenge fails outright rather than
    // dropping the row — dropping either `where` here does not widen the result,
    // it breaks discovery for everybody.
    return _challenges
        .where('visibility', isEqualTo: ChallengeVisibility.public.key)
        .where('status', isEqualTo: RunningChallengeStatus.active.key)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _toChallenge(doc.id, doc.data()))
            .toList(growable: false));
  }

  @override
  Stream<List<ChallengeParticipant>> watchMyParticipations(String userId) {
    // Read from the user's own subcollection, which the engine keeps as a copy
    // of every participant row they hold — see mirrorMembership in
    // functions/running_challenges.js.
    //
    // NOT a collection-group query over `participants`, which is the obvious
    // shape and the one this used to be. That query cannot be authorised at
    // all: on a collection-group list, rules see neither the document nor the
    // path, so the only rule that admits it admits everybody to every
    // participant row in the database. It was refused for every user, and this
    // list — the whole "your challenges" section of the hub, invitations
    // included — came back empty from the day it shipped.
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('challengeMemberships')
        .orderBy('joinedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _toMembership(doc.id, doc.data()))
            .toList(growable: false));
  }

  @override
  Stream<RunningChallenge?> watchChallenge(String challengeId) {
    return _challenge(challengeId).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      return _toChallenge(doc.id, data);
    });
  }

  @override
  Stream<List<ChallengeParticipant>> watchLeaderboard(
    String challengeId, {
    int limit = 50,
  }) {
    // Ordered by the stored rank rather than re-sorted here. The engine writes
    // it with the comparator compareParticipants states, so this order and that
    // one cannot drift; and a four-key orderBy would need a composite index for
    // an answer the server has already worked out.
    //
    // The status filter keeps people who left off the board: their rank is
    // reset to zero when they go, which would otherwise float them to the top.
    return _participants(challengeId)
        .where('status', whereIn: [
          ParticipantStatus.active.key,
          ParticipantStatus.completed.key,
        ])
        .orderBy('rank')
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _toParticipant(doc.id, doc.data()))
            .toList(growable: false));
  }

  @override
  Stream<List<ChallengeParticipant>> watchParticipants(String challengeId) {
    // Unordered and unfiltered, unlike the board: this is the invite sheet
    // asking who is already on the challenge and who is still deciding, and
    // the people it most needs to hear about — invited, declined — are exactly
    // the ones the board leaves out.
    return _participants(challengeId).snapshots().map((snapshot) => snapshot
        .docs
        .map((doc) => _toParticipant(doc.id, doc.data()))
        .toList(growable: false));
  }

  @override
  Stream<ChallengeParticipant?> watchParticipant(
    String challengeId,
    String userId,
  ) {
    return _participant(challengeId, userId).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      return _toParticipant(doc.id, data);
    });
  }

  @override
  Stream<List<ChallengeDay>> watchRecentDays(
    String challengeId,
    String userId, {
    int limit = 14,
  }) {
    return _participant(challengeId, userId)
        .collection('days')
        .orderBy(FieldPath.documentId, descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ChallengeDay(
                  dayKey: doc.id,
                  distanceKm: _double(doc.data()['distanceKm']),
                  runCount: _int(doc.data()['runCount']),
                  qualified: doc.data()['qualified'] == true,
                ))
            .toList(growable: false));
  }

  @override
  Future<RunningChallenge> createChallenge({
    required String creatorId,
    required String title,
    required String description,
    required double goalValueKm,
    required double dailyMinimumKm,
    required String startDayKey,
    required String endDayKey,
    required ChallengeVisibility visibility,
    required int utcOffsetMinutes,
  }) async {
    final ref = _challenges.doc();

    // Every counter starts at zero and the rules check that it does. A create
    // that arrived claiming participants or a finished status would be a
    // competition somebody awarded themselves.
    await ref.set({
      'creatorId': creatorId,
      'title': title,
      'description': description,
      'type': 'running',
      'goalType': ChallengeGoalType.distance.key,
      'goalValueKm': goalValueKm,
      'dailyMinimumKm': dailyMinimumKm,
      'startDayKey': startDayKey,
      'endDayKey': endDayKey,
      'utcOffsetMinutes': utcOffsetMinutes,
      'visibility': visibility.key,
      'maxParticipants': kMaxChallengeParticipants,
      'status': RunningChallengeStatus.active.key,
      'participantCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final written = await ref.get();
    final challenge = _toChallenge(written.id, written.data()!);

    // The creator is a participant in their own challenge. Written directly
    // rather than through [join], which refuses a private challenge — the
    // creator is the one person who may enrol in one.
    await _participant(ref.id, creatorId).set(
      _standingStart(
        challengeId: ref.id,
        userId: creatorId,
        visibility: visibility,
        status: ParticipantStatus.active,
      ),
    );

    return challenge;
  }

  @override
  Future<RunningChallenge> createActivityChallenge({
    required String creatorId,
    required String title,
    required String description,
    required ActivityMetric metric,
    required ActivityMode mode,
    required int? target,
    required String startDayKey,
    required String endDayKey,
    required int utcOffsetMinutes,
  }) async {
    final ref = _challenges.doc();

    // The key list is exactly what the create rule allows; it refuses anything
    // else, including every figure the engine owns.
    await ref.set({
      'creatorId': creatorId,
      'title': title,
      'description': description,
      'type': ChallengeKind.activity.key,
      'metric': metric.key,
      'mode': mode.key,
      if (mode.needsTarget) 'target': target,
      'visibility': ChallengeVisibility.private.key,
      'startDayKey': startDayKey,
      'endDayKey': endDayKey,
      'maxParticipants': kMaxChallengeParticipants,
      'utcOffsetMinutes': utcOffsetMinutes,
      'status': RunningChallengeStatus.active.key,
      'participantCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final written = await ref.get();
    final challenge = _toChallenge(written.id, written.data()!);

    await _participant(ref.id, creatorId).set(
      _standingStart(
        challengeId: ref.id,
        userId: creatorId,
        visibility: ChallengeVisibility.private,
        status: ParticipantStatus.active,
      ),
    );

    return challenge;
  }

  @override
  Future<void> join(RunningChallenge challenge, String userId) {
    // The document id is the user's own uid, so a double tap on Join is one
    // participant record rather than two. Firestore has no unique constraint;
    // a derived id is the only thing that can enforce one.
    return _participant(challenge.id, userId).set(
      _standingStart(
        challengeId: challenge.id,
        userId: userId,
        visibility: challenge.visibility,
        status: ParticipantStatus.active,
      ),
    );
  }

  @override
  Future<void> invite({
    required RunningChallenge challenge,
    required String userId,
  }) {
    // An invitation IS a participant record that has not accepted yet. Same
    // derived id, so inviting the same person twice is inviting them once.
    return _participant(challenge.id, userId).set({
      ..._standingStart(
        challengeId: challenge.id,
        userId: userId,
        visibility: challenge.visibility,
        status: ParticipantStatus.invited,
      ),
      // When they were last asked, and the only thing that separates a resend
      // from every other write this document receives — the engine re-stamps a
      // rank on it whenever anybody's standing moves, and a resend leaves the
      // status exactly where it was. See onChallengeParticipantWritten.
      'invitedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> accept(String challengeId, String userId) {
    return _participant(challengeId, userId).update({
      'status': ParticipantStatus.active.key,
      // Stamped on acceptance rather than on invitation: the leaderboard's
      // final tie-break is join order, and being asked early is not the same as
      // turning up early.
      'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> decline(String challengeId, String userId) =>
      _setStatus(challengeId, userId, ParticipantStatus.declined);

  @override
  Future<void> leave(String challengeId, String userId) =>
      _setStatus(challengeId, userId, ParticipantStatus.left);

  @override
  Future<void> cancel(String challengeId) {
    return _challenge(challengeId).update({
      'status': RunningChallengeStatus.cancelled.key,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _setStatus(
    String challengeId,
    String userId,
    ParticipantStatus status,
  ) {
    return _participant(challengeId, userId).update({
      'status': status.key,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// The only participant shape a client may create.
  ///
  /// Every figure the leaderboard is ordered by is written explicitly as zero,
  /// because the rules check for exactly that — a missing field is not a zero
  /// as far as `participantStartsFromZero` is concerned, and leaving one out
  /// would have the create refused rather than defaulted.
  Map<String, dynamic> _standingStart({
    required String challengeId,
    required String userId,
    required ChallengeVisibility visibility,
    required ParticipantStatus status,
  }) {
    return {
      'challengeId': challengeId,
      'userId': userId,
      'status': status.key,
      // Denormalised from the parent so the read rule can test a field on this
      // document instead of paying a get() on the challenge for every row of a
      // leaderboard.
      'visibility': visibility.key,
      'totalDistanceKm': 0,
      'completedDays': 0,
      'currentStreak': 0,
      'longestStreak': 0,
      'completionPercentage': 0,
      'rank': 0,
      'runCount': 0,
      'totalDurationSeconds': 0,
      'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  RunningChallenge _toChallenge(String id, Map<String, dynamic> data) {
    return RunningChallenge(
      id: id,
      creatorId: (data['creatorId'] as String?) ?? '',
      title: (data['title'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      goalType: ChallengeGoalType.byKey(data['goalType'] as String?),
      goalValueKm: _double(data['goalValueKm']),
      dailyMinimumKm: _double(
        data['dailyMinimumKm'],
        fallback: kDefaultDailyQualifyingKm,
      ),
      startDayKey: (data['startDayKey'] as String?) ?? '',
      endDayKey: (data['endDayKey'] as String?) ?? '',
      utcOffsetMinutes: _int(data['utcOffsetMinutes']),
      visibility: ChallengeVisibility.byKey(data['visibility'] as String?),
      maxParticipants: _int(
        data['maxParticipants'],
        fallback: kMaxChallengeParticipants,
      ),
      status: RunningChallengeStatus.byKey(data['status'] as String?),
      participantCount: _int(data['participantCount']),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      kind: ChallengeKind.byKey(data['type'] as String?),
      activityMetric: ActivityMetric.byKey(data['metric'] as String?),
      activityMode: ActivityMode.byKey(data['mode'] as String?),
      target: (data['target'] as num?)?.toInt(),
    );
  }

  /// A mirrored row, where the document id is the CHALLENGE rather than the
  /// participant — the pair is the same, filed the other way round.
  ///
  /// The uid comes off the copy's own field, which the engine pins as it
  /// writes: nothing but the engine can write here, so the field is as
  /// trustworthy as the id it was taken from.
  ChallengeParticipant _toMembership(String id, Map<String, dynamic> data) {
    return _toParticipant((data['userId'] as String?) ?? '', {
      ...data,
      'challengeId': id,
    });
  }

  ChallengeParticipant _toParticipant(String id, Map<String, dynamic> data) {
    return ChallengeParticipant(
      // The document id is the uid, and is trusted over the field: the id is
      // what the rules pinned, the field is a copy.
      userId: id,
      challengeId: (data['challengeId'] as String?) ?? '',
      status: ParticipantStatus.byKey(data['status'] as String?),
      totalDistanceKm: _double(data['totalDistanceKm']),
      completedDays: _int(data['completedDays']),
      currentStreak: _int(data['currentStreak']),
      longestStreak: _int(data['longestStreak']),
      runCount: _int(data['runCount']),
      totalDurationSeconds: _int(data['totalDurationSeconds']),
      completionPercentage: _double(data['completionPercentage']),
      rank: _int(data['rank']),
      lastQualifiedDayKey: data['lastQualifiedDayKey'] as String?,
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate(),
      total: _int(data['total']),
      targetReachedDayKey: data['targetReachedDayKey'] as String?,
      finalRank: (data['finalRank'] as num?)?.toInt(),
    );
  }

  static int _int(Object? value, {int fallback = 0}) =>
      (value as num?)?.toInt() ?? fallback;

  static double _double(Object? value, {double fallback = 0}) =>
      (value as num?)?.toDouble() ?? fallback;
}
