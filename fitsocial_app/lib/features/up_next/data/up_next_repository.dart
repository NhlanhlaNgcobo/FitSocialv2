import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../../../core/config/functions_region.dart';
import '../domain/up_next.dart';

abstract class UpNextRepository {
  /// [dayKey]'s suggestions, dismissed ones already left out.
  Stream<List<UpNextSuggestion>> watchDay(String userId, String dayKey);

  /// Asks the server to rebuild today's suggestions. No model behind it, so
  /// it is cheap; the app still throttles it.
  Future<void> refresh();

  /// Adds [suggestionId] to the day's dismissed list. Final for the day.
  Future<void> dismiss(String userId, String dayKey, String suggestionId);
}

class FirestoreUpNextRepository implements UpNextRepository {
  FirestoreUpNextRepository(this._firestore, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  DocumentReference<Map<String, dynamic>> _day(String userId, String dayKey) =>
      _firestore
          .collection('users')
          .doc(userId)
          .collection('upNext')
          .doc(dayKey);

  @override
  Stream<List<UpNextSuggestion>> watchDay(String userId, String dayKey) =>
      _day(userId, dayKey)
          .snapshots()
          .map((doc) => visibleSuggestions(doc.data()));

  @override
  Future<void> refresh() =>
      _functions.httpsCallable('refreshUpNext').call<void>();

  @override
  Future<void> dismiss(String userId, String dayKey, String suggestionId) =>
      _day(userId, dayKey).update({
        'dismissed': FieldValue.arrayUnion([suggestionId]),
      });
}

/// Without Firebase: no suggestions.
class UnconfiguredUpNextRepository implements UpNextRepository {
  const UnconfiguredUpNextRepository();

  @override
  Stream<List<UpNextSuggestion>> watchDay(String userId, String dayKey) =>
      Stream.value(const []);

  @override
  Future<void> refresh() async {}

  @override
  Future<void> dismiss(
    String userId,
    String dayKey,
    String suggestionId,
  ) async {}
}

final upNextRepositoryProvider = Provider<UpNextRepository>((ref) {
  if (ref.watch(bootstrapStatusProvider).canUseFirebase) {
    return FirestoreUpNextRepository(FirebaseFirestore.instance, appFunctions);
  }
  return const UnconfiguredUpNextRepository();
});
