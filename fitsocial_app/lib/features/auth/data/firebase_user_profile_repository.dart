import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cross_file/cross_file.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../domain/auth_models.dart';
import '../domain/body_metrics.dart';
import '../domain/username.dart';
import 'firebase_username_repository.dart';
import 'user_profile_repository_contract.dart';

class FirebaseUserProfileRepository implements UserProfileRepository {
  FirebaseUserProfileRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? firebaseAuth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _firebaseAuth;

  @override
  Future<UserProfileDraft?> loadCurrentProfile() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;

    final snapshot = await _firestore.collection('users').doc(user.uid).get();
    if (!snapshot.exists) return null;

    final data = snapshot.data() ?? const <String, dynamic>{};
    return UserProfileDraft(
      displayName: (data['displayName'] as String?) ?? user.displayName ?? 'FitSocial User',
      handle: normalizeUsername(data['handle'] as String?),
      bio: (data['bio'] as String?) ?? '',
      location: (data['location'] as String?) ?? '',
      avatarUrl: data['avatarUrl'] as String?,
      pronouns: (data['pronouns'] as String?) ?? '',
      links: (data['links'] as String?) ?? '',
      handleChangedAt: (data['handleChangedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Writes the profile, claiming the username in the same transaction.
  ///
  /// The claim cannot be a separate step. If the reservation were written
  /// first and the profile write then failed, the name would be held by an
  /// account that does not display it; if the profile went first, two accounts
  /// could show the same username while only one held the reservation. One
  /// transaction is what keeps the two facts from ever disagreeing.
  ///
  /// The avatar upload is the exception, and has to be: Cloud Storage is not
  /// part of a Firestore transaction. It runs first, so the worst case is an
  /// orphaned image rather than a profile pointing at a file that was never
  /// written.
  @override
  Future<UserProfileDraft> saveProfile({
    required String displayName,
    required String handle,
    required String bio,
    required String location,
    String? avatarLocalPath,
    String pronouns = '',
    String links = '',
  }) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw StateError('No authenticated Firebase user found for profile save.');
    }

    final requestedHandle = normalizeUsername(handle);
    // Carries its own sentence, and StateError is what the error describer
    // passes through verbatim — so the user reads "Letters, numbers, dots and
    // underscores only" rather than a generic failure.
    final formatError = validateUsernameFormat(requestedHandle);
    if (formatError != null) {
      throw StateError(formatError);
    }

    final userRef = _firestore.collection('users').doc(user.uid);
    final usernames = _firestore.collection(usernamesCollection);

    final uploadedAvatarUrl = avatarLocalPath == null
        ? null
        : await _uploadAvatar(user.uid, avatarLocalPath);

    late UserProfileDraft saved;

    await _firestore.runTransaction((transaction) async {
      // Firestore requires every read in a transaction to precede every write,
      // so the whole picture is gathered up front.
      final userSnapshot = await transaction.get(userRef);
      final existing = userSnapshot.data() ?? const <String, dynamic>{};
      final currentHandle = normalizeUsername(existing['handle'] as String?);
      final isRename =
          currentHandle.isNotEmpty && currentHandle != requestedHandle;
      final isNewClaim = currentHandle != requestedHandle;

      DocumentSnapshot<Map<String, dynamic>>? claimSnapshot;
      DocumentSnapshot<Map<String, dynamic>>? previousSnapshot;
      if (isNewClaim) {
        claimSnapshot = await transaction.get(usernames.doc(requestedHandle));
        if (currentHandle.isNotEmpty) {
          previousSnapshot = await transaction.get(usernames.doc(currentHandle));
        }
      }

      if (isRename) {
        // Only an actual rename is throttled. The first claim on a new account
        // is not a change, and neither is re-saving the name you already have
        // — an edit to the bio must not be refused because of the username.
        final remaining = usernameCooldownRemaining(
          (existing['handleChangedAt'] as Timestamp?)?.toDate(),
        );
        if (remaining != null) {
          throw UsernameChangeTooSoonException(remaining);
        }
      }

      if (isNewClaim) {
        // Re-checked here rather than trusted from the UI's earlier lookup:
        // that was a plain read, and another account can commit in the gap
        // between it and this transaction. This is the check that counts.
        final status = readReservationStatus(
          claimSnapshot?.data(),
          viewerUid: user.uid,
        );
        final claimable = status == UsernameStatus.available ||
            status == UsernameStatus.yours ||
            status == UsernameStatus.reclaimable;
        if (!claimable) {
          throw UsernameTakenException(requestedHandle);
        }

        // A full set, not a merge: taking over a name whose grace period has
        // lapsed must clear the previous holder's releaseAt, or the name would
        // arrive already marked as vacated.
        transaction.set(usernames.doc(requestedHandle), {
          'uid': user.uid,
          'claimedAt': FieldValue.serverTimestamp(),
        });

        // The old name is held, not freed. Releasing it now would let someone
        // take the identity this account just stepped out of, while the
        // cooldown keeps the owner from taking it back — the exact window an
        // impersonator wants.
        if (previousSnapshot != null && previousSnapshot.exists) {
          final previousOwner = previousSnapshot.data()?['uid'] as String?;
          if (previousOwner == user.uid) {
            transaction.set(
              usernames.doc(currentHandle),
              {
                'uid': user.uid,
                'releaseAt': Timestamp.fromDate(
                  DateTime.now().toUtc().add(usernameGracePeriod),
                ),
              },
              SetOptions(merge: true),
            );
          }
        }
      }

      // No new photo picked: carry the stored avatar forward. The write below
      // skips a null avatarUrl, so the document kept its value — but the
      // returned profile populates the in-memory session, and without this the
      // avatar would vanish from the UI after any other profile edit.
      final avatarUrl = uploadedAvatarUrl ?? existing['avatarUrl'] as String?;

      // The profile document is readable by any signed-in user (Explore search
      // needs it), so contact details must not live on it. Email goes to a
      // private subcollection that only the owner can read.
      transaction.set(userRef, {
        'displayName': displayName.trim(),
        'handle': requestedHandle,
        'bio': bio.trim(),
        'location': location.trim(),
        'pronouns': pronouns.trim(),
        'links': links.trim(),
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        // Stamped only on a rename, and always from the server clock. The
        // security rules require it to equal the request time, so a client
        // cannot backdate it to shorten its own cooldown.
        if (isRename) 'handleChangedAt': FieldValue.serverTimestamp(),
        // Strips the legacy public copy for accounts created before the email
        // was moved, so saving a profile self-heals the exposure.
        'email': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      transaction.set(
        userRef.collection('private').doc('account'),
        {
          'email': user.email,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      saved = UserProfileDraft(
        displayName: displayName.trim(),
        handle: requestedHandle,
        bio: bio.trim(),
        location: location.trim(),
        avatarUrl: avatarUrl,
        pronouns: pronouns.trim(),
        links: links.trim(),
        // The server timestamp is not readable until the write lands, so the
        // local clock stands in for the session's copy. Only the stored value
        // is ever used to judge a cooldown; this one just drives the UI until
        // the next load.
        handleChangedAt: isRename
            ? DateTime.now()
            : (existing['handleChangedAt'] as Timestamp?)?.toDate(),
      );
    });

    return saved;
  }

  /// Body metrics live at `users/{uid}/private/body`, alongside the email, and
  /// for the same reason: the profile document above is world-readable to
  /// signed-in users, so anything written there is published to everyone.
  DocumentReference<Map<String, dynamic>> _bodyRef(String userId) =>
      _firestore.collection('users').doc(userId).collection('private').doc('body');

  @override
  Future<BodyMetrics> loadBodyMetrics() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return const BodyMetrics();

    final snapshot = await _bodyRef(user.uid).get();
    return BodyMetrics.fromMap(snapshot.data());
  }

  @override
  Future<void> saveBodyMetrics(BodyMetrics metrics) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw StateError('No authenticated Firebase user found for body save.');
    }

    // Merged, so clearing one field leaves the other standing — the calculator
    // lets a user set a height now and a weight later.
    await _bodyRef(user.uid).set(
      {
        ...metrics.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<String> _uploadAvatar(String userId, String localFilePath) async {
    final ref = FirebaseStorage.instance
        .ref()
        .child('profiles/$userId/avatar.jpg');

    // Uploading bytes rather than a dart:io File keeps this working on every
    // platform: on mobile XFile reads the picked file from disk, and on web it
    // fetches the blob: URL that image_picker returns in place of a real path.
    // Avatars are small, so holding one in memory is not a concern.
    final bytes = await XFile(localFilePath).readAsBytes();

    final uploadTask = ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }
}
