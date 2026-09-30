import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../domain/compare.dart';

/// Which stats document: a week (`2026-W40`) or a month (`2026-09`).
typedef PeriodRef = ({bool monthly, String id});

abstract class CompareRepository {
  /// One period's stats, or null when nothing was logged in it.
  Stream<PeriodStats?> watchPeriod(String userId, PeriodRef period);
}

class FirestoreCompareRepository implements CompareRepository {
  const FirestoreCompareRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Stream<PeriodStats?> watchPeriod(String userId, PeriodRef period) {
    final collection = period.monthly ? 'monthlyStats' : 'weeklyStats';
    return _firestore
        .collection(collection)
        .doc('${userId}_${period.id}')
        .snapshots()
        .map((doc) {
      final data = doc.data();
      return data == null ? null : PeriodStats.fromMap(data);
    });
  }
}

class UnconfiguredCompareRepository implements CompareRepository {
  const UnconfiguredCompareRepository();

  @override
  Stream<PeriodStats?> watchPeriod(String userId, PeriodRef period) =>
      Stream.value(null);
}

final compareRepositoryProvider = Provider<CompareRepository>((ref) {
  if (ref.watch(bootstrapStatusProvider).canUseFirebase) {
    return FirestoreCompareRepository(FirebaseFirestore.instance);
  }
  return const UnconfiguredCompareRepository();
});
