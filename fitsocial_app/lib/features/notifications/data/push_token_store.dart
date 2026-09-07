import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a device says "push to me".
///
/// One document per device under `users/{uid}/fcmTokens`, the registration
/// token itself as the id. Presence is the whole state — there is no enabled
/// flag that could contradict the document existing — which is the same shape
/// `notifyFor` uses for the profile bell, and for the same reason: two records
/// of one fact is one more than can be kept in step.
///
/// Read by functions/push.js under Admin credentials. firestore.rules keeps
/// these owner-only in both directions, read included: a registration token is
/// an address for somebody's phone, and unlike a password it is not something
/// they can rotate once it is out.
class PushTokenStore {
  const PushTokenStore(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _ref(String userId, String token) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('fcmTokens')
        .doc(token);
  }

  /// Registers [token] against [userId].
  ///
  /// The body carries only what a person reading the database would want in
  /// order to recognise a device; nothing on the sending side reads it, because
  /// the id is the only part a send needs.
  ///
  /// There is no `createdAt`. Merging one in on every save would rewrite it and
  /// leave a field that claims to be a first-seen date and is not.
  Future<void> save(String userId, String token, {required String platform}) {
    return _ref(userId, token).set({
      'platform': platform,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Withdraws a registration — signing out, or turning push off.
  ///
  /// Deleting a document that is not there is not an error in Firestore, so a
  /// caller that has lost track of whether it ever registered can still call
  /// this safely.
  Future<void> remove(String userId, String token) {
    return _ref(userId, token).delete();
  }
}

final pushTokenStoreProvider = Provider<PushTokenStore>((ref) {
  return PushTokenStore(FirebaseFirestore.instance);
});
