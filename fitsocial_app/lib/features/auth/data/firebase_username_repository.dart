import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/username.dart';
import 'username_repository_contract.dart';

/// The collection whose document ids *are* the usernames.
///
/// Firestore has no unique-column constraint, so the document id is the only
/// primitive that can enforce one. Making the username the id turns "is this
/// taken" into a single point read and "claim it" into a create that the
/// security rules can refuse when the document already exists.
const String usernamesCollection = 'usernames';

class FirebaseUsernameRepository implements UsernameRepository {
  FirebaseUsernameRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? firebaseAuth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _firebaseAuth;

  @override
  Future<UsernameAvailability> checkAvailability(String candidate) async {
    final formatError = validateUsernameFormat(candidate);
    if (formatError != null) {
      return UsernameAvailability.malformed(formatError);
    }

    final username = normalizeUsername(candidate);
    final snapshot =
        await _firestore.collection(usernamesCollection).doc(username).get();

    if (!snapshot.exists) {
      return const UsernameAvailability(status: UsernameStatus.available);
    }

    return UsernameAvailability(
      status: readReservationStatus(
        snapshot.data(),
        viewerUid: _firebaseAuth.currentUser?.uid,
      ),
    );
  }
}

/// What a reservation document means to the account looking at it.
///
/// Split out from the repository so the rules this encodes can be tested
/// without Firestore, and so the profile save can reuse the same reading
/// rather than writing a second, subtly different one.
///
/// [data] is the stored reservation; null or empty means no reservation, which
/// is [UsernameStatus.available].
UsernameStatus readReservationStatus(
  Map<String, dynamic>? data, {
  required String? viewerUid,
  DateTime? now,
}) {
  if (data == null || data.isEmpty) return UsernameStatus.available;

  final ownerUid = data['uid'] as String?;
  final releaseAt = (data['releaseAt'] as Timestamp?)?.toDate();
  final isOwner = ownerUid != null && ownerUid == viewerUid;

  // No releaseAt means the reservation is live: somebody is using this name
  // right now.
  if (releaseAt == null) {
    return isOwner ? UsernameStatus.yours : UsernameStatus.taken;
  }

  // Past its grace period, a vacated name is nobody's.
  final current = now ?? DateTime.now();
  if (!releaseAt.isAfter(current)) return UsernameStatus.available;

  // Inside the grace period. The account that left it may take it back;
  // everyone else sees it as taken, which is the whole point of the hold.
  return isOwner ? UsernameStatus.reclaimable : UsernameStatus.heldByPrevious;
}
