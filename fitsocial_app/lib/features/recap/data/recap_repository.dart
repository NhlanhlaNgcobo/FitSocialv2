import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';

abstract class RecapRepository {
  /// The `weeklyStats` document for [weekId], or null when there is none.
  Future<Map<String, dynamic>?> weekStats(String userId, String weekId);

  /// How many weekly goals were completed in [weekId].
  Future<int> weeklyGoalsHit(String userId, String weekId);
}

class FirestoreRecapRepository implements RecapRepository {
  FirestoreRecapRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<Map<String, dynamic>?> weekStats(String userId, String weekId) async {
    final doc = await _firestore
        .collection('weeklyStats')
        .doc('${userId}_$weekId')
        .get();
    return doc.data();
  }

  @override
  Future<int> weeklyGoalsHit(String userId, String weekId) async {
    // Every weekly goal, archived ones included: a goal hit last week and
    // archived since was still hit. Each keeps one record per week it ran,
    // under the week's id, so this is one read per weekly goal.
    final goals = await _firestore
        .collection('users')
        .doc(userId)
        .collection('goals')
        .where('period', isEqualTo: 'weekly')
        .get();
    final records = await Future.wait([
      for (final goal in goals.docs)
        goal.reference.collection('periods').doc(weekId).get(),
    ]);
    return records.where((r) => r.data()?['completed'] == true).length;
  }
}

/// Without Firebase: nothing to recap.
class UnconfiguredRecapRepository implements RecapRepository {
  const UnconfiguredRecapRepository();

  @override
  Future<Map<String, dynamic>?> weekStats(String userId, String weekId) async =>
      null;

  @override
  Future<int> weeklyGoalsHit(String userId, String weekId) async => 0;
}

final recapRepositoryProvider = Provider<RecapRepository>((ref) {
  if (ref.watch(bootstrapStatusProvider).canUseFirebase) {
    return FirestoreRecapRepository(FirebaseFirestore.instance);
  }
  return const UnconfiguredRecapRepository();
});
