import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../../../core/config/functions_region.dart';
import '../domain/goal.dart';

/// A goal the server refused, with the reason it gave. The callable's
/// messages are written to be shown as they are.
class GoalRejected implements Exception {
  const GoalRejected(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class GoalRepository {
  /// The user's running goals, oldest first.
  Stream<List<Goal>> watchActiveGoals(String userId);

  /// Asks the server for a new goal. Throws [GoalRejected] with a message to
  /// show when it says no.
  Future<String> createGoal({
    required GoalMetric metric,
    required GoalPeriod period,
    required int target,
    String? startDayKey,
    String? endDayKey,
  });

  Future<void> archiveGoal(String userId, String goalId);
}

class FirestoreGoalRepository implements GoalRepository {
  FirestoreGoalRepository(this._firestore, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> _goals(String userId) =>
      _firestore.collection('users').doc(userId).collection('goals');

  @override
  Stream<List<Goal>> watchActiveGoals(String userId) {
    // Filtered on status alone and sorted here: adding an orderBy would need a
    // composite index for a list that never holds more than ten.
    return _goals(userId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) {
      final goals = <Goal>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final created = data['createdAt'];
        final goal = Goal.fromMap(
          doc.id,
          data,
          createdAt: created is Timestamp ? created.toDate() : null,
        );
        if (goal != null) goals.add(goal);
      }
      goals.sort((a, b) {
        final at = a.createdAt, bt = b.createdAt;
        // A goal just created has no server timestamp in the local echo yet;
        // it belongs at the end, where it is about to land anyway.
        if (at == null) return bt == null ? 0 : 1;
        if (bt == null) return -1;
        return at.compareTo(bt);
      });
      return goals;
    });
  }

  @override
  Future<String> createGoal({
    required GoalMetric metric,
    required GoalPeriod period,
    required int target,
    String? startDayKey,
    String? endDayKey,
  }) async {
    try {
      final result = await _functions.httpsCallable('createGoal').call({
        'metric': metric.key,
        'period': period.key,
        'target': target,
        if (startDayKey != null) 'startDayKey': startDayKey,
        if (endDayKey != null) 'endDayKey': endDayKey,
      });
      return (result.data as Map)['goalId'] as String;
    } on FirebaseFunctionsException catch (error) {
      // Validation and the active-goal cap come back with a sentence meant
      // for the user. Anything else is not theirs to fix.
      const userFacing = {
        'invalid-argument',
        'resource-exhausted',
        'failed-precondition',
      };
      if (userFacing.contains(error.code) && error.message != null) {
        throw GoalRejected(error.message!);
      }
      rethrow;
    }
  }

  @override
  Future<void> archiveGoal(String userId, String goalId) {
    return _goals(userId).doc(goalId).update({
      'status': GoalStatus.archived.key,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

/// Used when Firebase was never configured: no goals, and creating one says
/// so rather than pretending.
class UnconfiguredGoalRepository implements GoalRepository {
  const UnconfiguredGoalRepository();

  @override
  Stream<List<Goal>> watchActiveGoals(String userId) => Stream.value(const []);

  @override
  Future<String> createGoal({
    required GoalMetric metric,
    required GoalPeriod period,
    required int target,
    String? startDayKey,
    String? endDayKey,
  }) =>
      Future.error(const GoalRejected('Goals need a connection to FitSocial.'));

  @override
  Future<void> archiveGoal(String userId, String goalId) async {}
}

final goalRepositoryProvider = Provider<GoalRepository>((ref) {
  if (ref.watch(bootstrapStatusProvider).canUseFirebase) {
    return FirestoreGoalRepository(FirebaseFirestore.instance, appFunctions);
  }
  return const UnconfiguredGoalRepository();
});
