import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../../../core/config/functions_region.dart';
import '../domain/weekly_insight.dart';

/// The server said no to a request, with a sentence meant for the user.
class InsightRefused implements Exception {
  const InsightRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class InsightRepository {
  /// The stored insight for [weekId], or null while there is none.
  Stream<WeeklyInsight?> watchInsight(String userId, String weekId);

  /// Asks the server for last week's insight. Returns the status it stored.
  /// Cheap when one is already stored: the server returns it without calling
  /// the model unless [regenerate].
  Future<InsightStatus> request({bool regenerate = false});

  Stream<InsightRating?> watchRating(String userId, String weekId);

  Future<void> rate(String userId, String weekId, InsightRating rating);

  Stream<bool> watchHidden(String userId);

  Future<void> setHidden(String userId, bool hidden);
}

class FirestoreInsightRepository implements InsightRepository {
  FirestoreInsightRepository(this._firestore, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  DocumentReference<Map<String, dynamic>> _user(String userId) =>
      _firestore.collection('users').doc(userId);

  @override
  Stream<WeeklyInsight?> watchInsight(String userId, String weekId) =>
      _user(userId)
          .collection('insights')
          .doc(weekId)
          .snapshots()
          .map(
            (doc) => doc.exists
                ? WeeklyInsight.fromMap(weekId, doc.data() ?? const {})
                : null,
          );

  @override
  Future<InsightStatus> request({bool regenerate = false}) async {
    try {
      final result = await _functions
          .httpsCallable('requestWeeklyInsight')
          .call({'regenerate': regenerate});
      return InsightStatus.fromKey((result.data as Map)['status']);
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'resource-exhausted' && error.message != null) {
        throw InsightRefused(error.message!);
      }
      rethrow;
    }
  }

  DocumentReference<Map<String, dynamic>> _feedback(
    String userId,
    String weekId,
  ) => _firestore.collection('insightFeedback').doc('${userId}_$weekId');

  @override
  Stream<InsightRating?> watchRating(String userId, String weekId) => _feedback(
    userId,
    weekId,
  ).snapshots().map((doc) => InsightRating.fromKey(doc.data()?['rating']));

  @override
  Future<void> rate(String userId, String weekId, InsightRating rating) =>
      _feedback(userId, weekId).set({
        'userId': userId,
        'weekId': weekId,
        'rating': rating.key,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  @override
  Stream<bool> watchHidden(String userId) => _user(
    userId,
  ).snapshots().map((doc) => doc.data()?['insightsHidden'] == true);

  @override
  Future<void> setHidden(String userId, bool hidden) =>
      _user(userId).set({'insightsHidden': hidden}, SetOptions(merge: true));
}

/// Without Firebase: no insights, nothing hidden, and asking says so.
class UnconfiguredInsightRepository implements InsightRepository {
  const UnconfiguredInsightRepository();

  @override
  Stream<WeeklyInsight?> watchInsight(String userId, String weekId) =>
      Stream.value(null);

  @override
  Future<InsightStatus> request({bool regenerate = false}) => Future.error(
    const InsightRefused('Weekly Insights need a connection to FitSocial.'),
  );

  @override
  Stream<InsightRating?> watchRating(String userId, String weekId) =>
      Stream.value(null);

  @override
  Future<void> rate(String userId, String weekId, InsightRating rating) async {}

  @override
  Stream<bool> watchHidden(String userId) => Stream.value(false);

  @override
  Future<void> setHidden(String userId, bool hidden) async {}
}

final insightRepositoryProvider = Provider<InsightRepository>((ref) {
  if (ref.watch(bootstrapStatusProvider).canUseFirebase) {
    return FirestoreInsightRepository(FirebaseFirestore.instance, appFunctions);
  }
  return const UnconfiguredInsightRepository();
});
