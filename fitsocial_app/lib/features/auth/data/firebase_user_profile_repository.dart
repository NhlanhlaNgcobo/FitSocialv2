import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cross_file/cross_file.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../domain/auth_models.dart';
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
      handle: (data['handle'] as String?) ?? '@fitsocial',
      bio: (data['bio'] as String?) ?? '',
      location: (data['location'] as String?) ?? '',
      avatarUrl: data['avatarUrl'] as String?,
      pronouns: (data['pronouns'] as String?) ?? '',
      links: (data['links'] as String?) ?? '',
    );
  }

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

    final userRef = _firestore.collection('users').doc(user.uid);

    String? avatarUrl;
    if (avatarLocalPath != null) {
      avatarUrl = await _uploadAvatar(user.uid, avatarLocalPath);
    } else {
      // No new photo picked: carry the stored avatar forward. The Firestore
      // write below skips a null avatarUrl, so the document kept its value —
      // but the returned profile populates the in-memory session, and without
      // this the avatar would vanish from the UI after any other profile edit.
      final existing = await userRef.get();
      avatarUrl = existing.data()?['avatarUrl'] as String?;
    }

    final profile = UserProfileDraft(
      displayName: displayName.trim(),
      handle: handle.trim(),
      bio: bio.trim(),
      location: location.trim(),
      avatarUrl: avatarUrl,
      pronouns: pronouns.trim(),
      links: links.trim(),
    );

    // The profile document is readable by any signed-in user (Explore search
    // needs it), so contact details must not live on it. Email goes to a
    // private subcollection that only the owner can read.
    final batch = _firestore.batch();

    batch.set(userRef, {
      'displayName': profile.displayName,
      'handle': profile.handle,
      'bio': profile.bio,
      'location': profile.location,
      'pronouns': profile.pronouns,
      'links': profile.links,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      // Strips the legacy public copy for accounts created before the email
      // was moved, so saving a profile self-heals the exposure.
      'email': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(userRef.collection('private').doc('account'), {
      'email': user.email,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();

    return profile;
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
