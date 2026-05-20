import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
    );
  }

  @override
  Future<UserProfileDraft> saveProfile({
    required String displayName,
    required String handle,
    required String bio,
    required String location,
  }) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw StateError('No authenticated Firebase user found for profile save.');
    }

    final profile = UserProfileDraft(
      displayName: displayName.trim(),
      handle: handle.trim(),
      bio: bio.trim(),
      location: location.trim(),
    );

    await _firestore.collection('users').doc(user.uid).set({
      'displayName': profile.displayName,
      'handle': profile.handle,
      'bio': profile.bio,
      'location': profile.location,
      'email': user.email,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return profile;
  }
}
