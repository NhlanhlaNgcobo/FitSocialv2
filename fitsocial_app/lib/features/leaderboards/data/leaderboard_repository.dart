import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../domain/leaderboard.dart';

abstract class LeaderboardRepository {
  /// The entries [userIds] have for [periodId]. Ids with no entry are simply
  /// absent from the result — they are not on this board.
  Future<List<LeaderboardEntry>> fetchEntries({
    required List<String> userIds,
    required String periodId,
  });

  /// Whether [userId] has taken themselves off the boards.
  Stream<bool> watchOptOut(String userId);

  /// Sets the opt-out. The server clears the entries that already exist, so
  /// nothing here has to.
  Future<void> setOptOut(String userId, bool optedOut);
}

class FirestoreLeaderboardRepository implements LeaderboardRepository {
  const FirestoreLeaderboardRepository(this._firestore);

  /// How many people one query asks about.
  ///
  /// Ten, not the thirty Firestore allows, and the number is set by the security
  /// rules rather than by the query: the rule on `/leaderboardEntries` checks
  /// each returned document against a follower lookup, and the rules engine
  /// permits 20 document lookups per query. Identical lookups are cached, so the
  /// cost is one per distinct person in the result — the same arithmetic, and
  /// the same number, as the Pulse tray's author chunks.
  static const int chunkSize = 10;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _entries =>
      _firestore.collection('leaderboardEntries');

  @override
  Future<List<LeaderboardEntry>> fetchEntries({
    required List<String> userIds,
    required String periodId,
  }) async {
    if (userIds.isEmpty) return const [];

    // Queried by document id, which an entry's id makes possible:
    // `<uid>_<periodId>` is something the client can build for everybody it is
    // asking about. That keeps the whole board to one index-free query per
    // chunk, and it means somebody with no entry for the period costs nothing
    // rather than coming back as a row of zeros.
    final ids = [for (final id in userIds) '${id}_$periodId'];

    final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    for (var i = 0; i < ids.length; i += chunkSize) {
      futures.add(
        _entries
            .where(
              FieldPath.documentId,
              whereIn: ids.skip(i).take(chunkSize).toList(growable: false),
            )
            .get(),
      );
    }

    final snapshots = await Future.wait(futures);
    final entries = <LeaderboardEntry>[];
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        final data = doc.data();
        // The uid off the document rather than off its id: an id is a string
        // this client built, and the document is what says who it is about.
        final userId = data['userId'] as String?;
        if (userId == null || userId.isEmpty) continue;
        entries.add(LeaderboardEntry.fromMap(userId, data));
      }
    }
    return entries;
  }

  @override
  Stream<bool> watchOptOut(String userId) => _firestore
      .collection('users')
      .doc(userId)
      .snapshots()
      .map((doc) => doc.data()?['leaderboardOptOut'] == true);

  @override
  Future<void> setOptOut(String userId, bool optedOut) =>
      _firestore.collection('users').doc(userId).set(
        {'leaderboardOptOut': optedOut},
        SetOptions(merge: true),
      );
}

/// Without Firebase — widget tests, a checkout with no `firebase_options.dart`
/// — every board is empty and the opt-out is off.
class UnconfiguredLeaderboardRepository implements LeaderboardRepository {
  const UnconfiguredLeaderboardRepository();

  @override
  Future<List<LeaderboardEntry>> fetchEntries({
    required List<String> userIds,
    required String periodId,
  }) async =>
      const [];

  @override
  Stream<bool> watchOptOut(String userId) => Stream.value(false);

  @override
  Future<void> setOptOut(String userId, bool optedOut) async {}
}

final leaderboardRepositoryProvider = Provider<LeaderboardRepository>((ref) {
  if (ref.watch(bootstrapStatusProvider).canUseFirebase) {
    return FirestoreLeaderboardRepository(FirebaseFirestore.instance);
  }
  return const UnconfiguredLeaderboardRepository();
});
