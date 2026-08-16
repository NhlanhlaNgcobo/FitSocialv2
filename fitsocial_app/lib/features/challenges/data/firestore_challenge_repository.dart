import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/challenge_badges.dart';
import '../domain/challenge_clock.dart';
import '../domain/challenge_models.dart';
import '../domain/challenge_task.dart';
import 'challenge_repository_contract.dart';

/// Challenges, on Cloud Firestore.
///
/// Reads dominate this class because the engine that writes challenge state
/// runs in Cloud Functions. What is here is the three writes a client is
/// permitted — starting a run, leaving one, and the two manual counters — plus
/// the step record, which has to pass through the device because only the
/// device can see the pedometer.
class FirestoreChallengeRepository implements ChallengeRepository {
  FirestoreChallengeRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _enrollments =>
      _firestore.collection('challengeEnrollments');

  CollectionReference<Map<String, dynamic>> get _dailySteps =>
      _firestore.collection('dailySteps');

  CollectionReference<Map<String, dynamic>> get _earlyWorm =>
      _firestore.collection('earlyWorm');

  CollectionReference<Map<String, dynamic>> get _stats =>
      _firestore.collection('challengeStats');

  DocumentReference<Map<String, dynamic>> _enrollment(String id) =>
      _enrollments.doc(id);

  @override
  Stream<List<ChallengeEnrollment>> watchEnrollments(String userId) {
    return _enrollments
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _toEnrollment(doc.id, doc.data()))
            .toList(growable: false));
  }

  @override
  Stream<ChallengeEnrollment?> watchEnrollment(String enrollmentId) {
    return _enrollment(enrollmentId).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      return _toEnrollment(doc.id, data);
    });
  }

  @override
  Stream<DailyProgress> watchDay(String enrollmentId, String dayKey) {
    final day = _enrollment(enrollmentId).collection('days').doc(dayKey);
    final manual = _enrollment(enrollmentId).collection('manual').doc(dayKey);

    // Two documents, not one. The engine owns the day record and recomputes it
    // from the logs a moment after anything is written; the manual entry is the
    // user's own and lands instantly. Overlaying the second on the first is
    // what makes a tap on the water stepper tick immediately instead of after a
    // round trip to a Cloud Function.
    return _combine2(
      day.snapshots(),
      manual.snapshots(),
      (daySnapshot, manualSnapshot) {
        final data = daySnapshot.data();
        final values = <ChallengeTask, double>{};

        final stored = data?['values'];
        if (stored is Map) {
          for (final entry in stored.entries) {
            final task = ChallengeTask.byKey(entry.key.toString());
            final value = entry.value;
            if (task != null && value is num) values[task] = value.toDouble();
          }
        }

        final local = manualSnapshot.data();
        if (local != null) {
          for (final task in ChallengeTask.manual) {
            final value = local[task.key];
            if (value is num) values[task] = value.toDouble();
          }
        }

        return DailyProgress(
          dayKey: dayKey,
          values: values,
          open: (data?['open'] as bool?) ?? true,
        );
      },
    );
  }

  @override
  Stream<List<DailyProgress>> watchRecentDays(String enrollmentId, int days) {
    return _enrollment(enrollmentId)
        .collection('days')
        .orderBy('dayKey', descending: true)
        .limit(days)
        .snapshots()
        .map((snapshot) {
      final result = snapshot.docs
          .map((doc) => _toDay(doc.id, doc.data()))
          .toList(growable: false);
      // Oldest first: the strip reads left to right as time passing.
      return result.reversed.toList(growable: false);
    });
  }

  @override
  Future<ChallengeEnrollment> enroll({
    required String userId,
    required ChallengeKey challengeKey,
    required int utcOffsetMinutes,
  }) async {
    final clock = ChallengeClock(utcOffsetMinutes: utcOffsetMinutes);
    final startDayKey = clock.today();
    final id = ChallengeEnrollment.idFor(
      userId: userId,
      challengeKey: challengeKey,
      startDayKey: startDayKey,
    );
    final ref = _enrollment(id);

    // A derived id makes this idempotent, but a plain `set` would still reset
    // the counters of a run started earlier today and already under way. The
    // existing document wins.
    final existing = await ref.get();
    if (existing.exists) {
      return _toEnrollment(existing.id, existing.data()!);
    }

    // Every counter starts at zero, and the rules check that they do. A create
    // that arrived pre-loaded with completed days would be a run somebody
    // awarded themselves.
    await ref.set({
      'userId': userId,
      'challengeKey': challengeKey.key,
      'startDayKey': startDayKey,
      'status': EnrollmentStatus.active.key,
      'daysCompleted': 0,
      'currentStreak': 0,
      'longestStreak': 0,
      'consecutiveMissedDays': 0,
      'missedDaysTotal': 0,
      'pointsEarned': 0,
      'progressPercent': 0,
      'utcOffsetMinutes': utcOffsetMinutes,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final written = await ref.get();
    return _toEnrollment(written.id, written.data()!);
  }

  @override
  Future<void> abandon(String enrollmentId) {
    return _enrollment(enrollmentId).update({
      'status': EnrollmentStatus.abandoned.key,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> setManualTask({
    required String enrollmentId,
    required String dayKey,
    required ChallengeTask task,
    required int value,
  }) {
    if (!task.isManual) {
      throw ArgumentError.value(
        task.key,
        'task',
        'Only water and reading are set by hand. Everything else is read from '
            'the logs, and the rules refuse a client write either way.',
      );
    }

    return _enrollment(enrollmentId).collection('manual').doc(dayKey).set(
      {
        'dayKey': dayKey,
        task.key: value < 0 ? 0 : value,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> syncUserClock(String userId, int utcOffsetMinutes) {
    return _firestore.collection('users').doc(userId).set(
      {'utcOffsetMinutes': utcOffsetMinutes},
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> refreshClock(String enrollmentId, int utcOffsetMinutes) {
    return _enrollment(enrollmentId).update({
      'utcOffsetMinutes': utcOffsetMinutes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> recordDailySteps({
    required String userId,
    required String dayKey,
    required int steps,
    required String source,
  }) async {
    final ref = _dailySteps.doc('${userId}_$dayKey');

    // The highest reading for a day wins. Sources disagree and some of them
    // reset: a pedometer restarts when the phone reboots, and Health Connect
    // can come back empty while a permission is being re-granted. Taking the
    // maximum means a bad reading cannot delete a day's walking.
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(ref);
      final previous = (existing.data()?['steps'] as num?)?.toInt() ?? 0;
      if (existing.exists && previous >= steps) return;

      transaction.set(
        ref,
        {
          'userId': userId,
          'dayKey': dayKey,
          'steps': steps,
          'source': source,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  @override
  Stream<EarlyWormStreak> watchEarlyWorm(String userId) {
    return _earlyWorm.doc(userId).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return const EarlyWormStreak();
      return EarlyWormStreak(
        currentStreak: _int(data['currentStreak']),
        longestStreak: _int(data['longestStreak']),
        totalDays: _int(data['totalDays']),
        lastQualifiedDayKey: data['lastQualifiedDayKey'] as String?,
      );
    });
  }

  @override
  Stream<List<UserBadge>> watchBadges(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('badges')
        .snapshots()
        .map((snapshot) {
      final badges = <UserBadge>[];
      for (final doc in snapshot.docs) {
        final badge = ChallengeBadge.byKey(doc.id);
        // A badge key this build does not know about is skipped rather than
        // shown as a blank tile. An older app reading a newer catalogue is the
        // normal case, not an error.
        if (badge == null) continue;
        final data = doc.data();
        badges.add(UserBadge(
          badge: badge,
          awardedAt:
              (data['awardedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          count: _int(data['count'], fallback: 1),
          rarityPercent: (data['rarityPercent'] as num?)?.toDouble(),
        ));
      }
      badges.sort((a, b) => a.badge.index.compareTo(b.badge.index));
      return badges;
    });
  }

  @override
  Stream<int> watchPoints(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((doc) => _int(doc.data()?['totalPoints']));
  }

  @override
  Stream<ChallengeStats> watchStats(ChallengeKey challengeKey) {
    return _stats.doc(challengeKey.key).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return const ChallengeStats();
      return ChallengeStats(
        activeCount: _int(data['activeCount']),
        completedCount: _int(data['completedCount']),
      );
    });
  }

  ChallengeEnrollment _toEnrollment(String id, Map<String, dynamic> data) {
    return ChallengeEnrollment(
      id: id,
      userId: (data['userId'] as String?) ?? '',
      challengeKey:
          ChallengeKey.byKey(data['challengeKey'] as String? ?? '') ??
              ChallengeKey.pulse75,
      startDayKey: (data['startDayKey'] as String?) ?? '',
      utcOffsetMinutes: _int(data['utcOffsetMinutes'], fallback: 0),
      pointsEarned: _int(data['pointsEarned']),
      lastEvaluatedDayKey: data['lastEvaluatedDayKey'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      progress: EnrollmentProgress(
        daysCompleted: _int(data['daysCompleted']),
        currentStreak: _int(data['currentStreak']),
        longestStreak: _int(data['longestStreak']),
        consecutiveMissedDays: _int(data['consecutiveMissedDays']),
        status: EnrollmentStatus.byKey(data['status'] as String? ?? 'active'),
      ),
    );
  }

  DailyProgress _toDay(String dayKey, Map<String, dynamic> data) {
    final values = <ChallengeTask, double>{};
    final stored = data['values'];
    if (stored is Map) {
      for (final entry in stored.entries) {
        final task = ChallengeTask.byKey(entry.key.toString());
        final value = entry.value;
        if (task != null && value is num) values[task] = value.toDouble();
      }
    }
    return DailyProgress(
      dayKey: dayKey,
      values: values,
      open: (data['open'] as bool?) ?? true,
    );
  }

  static int _int(Object? value, {int fallback = 0}) =>
      (value as num?)?.toInt() ?? fallback;
}

/// Two streams as one, emitting once both have reported and on every change
/// after that.
///
/// The pair here is always two documents read from the same screen, so waiting
/// for both costs nothing and avoids a frame where the day is drawn with half
/// its numbers.
Stream<R> _combine2<A, B, R>(
  Stream<A> first,
  Stream<B> second,
  R Function(A, B) combine,
) {
  late StreamController<R> controller;
  StreamSubscription<A>? firstSub;
  StreamSubscription<B>? secondSub;

  A? latestFirst;
  B? latestSecond;
  var hasFirst = false;
  var hasSecond = false;

  void emit() {
    if (!hasFirst || !hasSecond) return;
    controller.add(combine(latestFirst as A, latestSecond as B));
  }

  controller = StreamController<R>(
    onListen: () {
      firstSub = first.listen(
        (value) {
          latestFirst = value;
          hasFirst = true;
          emit();
        },
        onError: controller.addError,
      );
      secondSub = second.listen(
        (value) {
          latestSecond = value;
          hasSecond = true;
          emit();
        },
        onError: controller.addError,
      );
    },
    onCancel: () async {
      await firstSub?.cancel();
      await secondSub?.cancel();
    },
  );

  return controller.stream;
}
