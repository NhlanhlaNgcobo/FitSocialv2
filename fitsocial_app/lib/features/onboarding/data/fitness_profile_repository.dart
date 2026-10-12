import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/fitness_profile.dart';

/// `users/{uid}/private/fitness`.
abstract interface class FitnessProfileRepository {
  /// The stored profile, or null when the account has never had one — every
  /// account made before onboarding existed.
  Future<FitnessProfile?> load(String uid);

  Future<void> save(String uid, FitnessProfile profile);
}

class FirestoreFitnessProfileRepository implements FitnessProfileRepository {
  FirestoreFitnessProfileRepository({FirebaseFirestore? firestore})
      : _injected = firestore;

  /// Resolved on first use rather than at construction, because the session
  /// builds this, and widget tests build sessions with no Firebase app.
  final FirebaseFirestore? _injected;
  FirebaseFirestore get _firestore => _injected ?? FirebaseFirestore.instance;

  /// Private, next to `body` and `account`: goals and equipment are nobody
  /// else's business, and the profile document is readable by every signed-in
  /// user.
  DocumentReference<Map<String, dynamic>> _ref(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('private')
      .doc('fitness');

  @override
  Future<FitnessProfile?> load(String uid) async {
    final snapshot = await _ref(uid).get();
    final data = snapshot.data();
    return data == null ? null : FitnessProfile.fromMap(data);
  }

  @override
  Future<void> save(String uid, FitnessProfile profile) {
    // A full set rather than a merge: the rules check the whole document, and
    // a merge would carry forward a field this version of the app no longer
    // writes.
    return _ref(uid).set({
      ...profile.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
