import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../../auth/domain/auth_models.dart';
import '../../main/domain/activity_kind.dart';
import '../../main/domain/app_models.dart' show PublicAuthorName;
import '../domain/live_activity_share.dart';
import 'live_share_repository.dart';

/// Firestore-backed live activity shares.
///
/// Layout:
///   liveActivities/{shareId} — one activity in progress, or just finished
///
/// The document id is a random UUID and is the only credential a viewer
/// holds: the rules allow a `get` by id to any signed-in user and forbid
/// listing the collection, so knowing the link is what grants the view. That
/// is also why the id is minted here rather than left to Firestore's own
/// generator — an auto-id is unique, but it is not designed to be a secret.
///
/// Expiry is belt-and-braces, as it is for Pulses: `expiresAt` is written so
/// a Firestore TTL policy on this collection can sweep the documents, and the
/// viewer checks it as well because TTL deletion is only guaranteed within a
/// day of the expiry time. The policy is enabled once per project — Cloud
/// console: Firestore > Databases > (default) > Time-to-live > Create Policy,
/// collection group `liveActivities`, field `expiresAt` — or with the CLI:
///
///   gcloud firestore fields ttls update expiresAt \
///     --collection-group=liveActivities --enable-ttl --project=fitsocialv2
///
/// The console only lists collection groups that already hold a document, so
/// the policy cannot be created until somebody has shared an activity once.
/// Until it exists, ended shares stay in the database; they are unreadable as
/// live locations either way, because the viewer refuses an expired document.
class FirestoreLiveShareRepository implements LiveShareRepository {
  FirestoreLiveShareRepository(
    this._firestore, {
    FirebaseAuth? firebaseAuth,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _firebaseAuth;

  CollectionReference<Map<String, dynamic>> get _shares =>
      _firestore.collection('liveActivities');

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  @override
  Future<String> begin({
    required ActivityKind kind,
    required DateTime startedAt,
    required UserProfileDraft? profile,
  }) async {
    final user = _requireCurrentUser();
    final authorName = await _resolveAuthorName(profile);
    final authorAvatarUrl = await _resolveAuthorAvatarUrl(profile);
    final shareId = const Uuid().v4();

    // expiresAt is a concrete value rather than a server sentinel: it is what
    // the TTL policy reads and what the viewer filters on, and neither can
    // work against an unresolved timestamp.
    await _shares.doc(shareId).set({
      'authorId': user.uid,
      'authorName': authorName,
      if (authorAvatarUrl != null) 'authorAvatarUrl': authorAvatarUrl,
      'activityType': kind.wireName,
      'status': LiveSharePhase.live.wireName,
      'startedAt': Timestamp.fromDate(startedAt),
      'updatedAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(startedAt.add(LiveActivityShare.lifetime)),
      'distanceKm': 0.0,
      'elapsedSeconds': 0,
      'paceLabel': '--',
      'isPaused': false,
      'trail': const <Map<String, double>>[],
    });
    return shareId;
  }

  @override
  Future<void> update(String shareId, LiveShareSnapshot snapshot) {
    return _shares.doc(shareId).update({
      ...snapshot.toUpdate(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> end(String shareId, LiveShareSnapshot snapshot) {
    return _shares.doc(shareId).update({
      ...snapshot.toUpdate(),
      'status': LiveSharePhase.ended.wireName,
      'endedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> discard(String shareId) => _shares.doc(shareId).delete();

  @override
  Stream<LiveActivityShare?> watch(String shareId) {
    return _shares.doc(shareId).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      return LiveActivityShare.fromMap(doc.id, {
        ...data,
        'startedAt': _readTimestamp(data['startedAt']),
        'updatedAt': _readTimestamp(data['updatedAt']),
        'expiresAt': _readTimestamp(data['expiresAt']),
        'endedAt': _readTimestamp(data['endedAt']),
      });
    });
  }

  /// Public name to attribute the share to. Never the auth email: the link
  /// can be forwarded to anyone. Prefers the in-memory session profile and
  /// only falls back to a stored read when that has nothing usable.
  Future<String> _resolveAuthorName(UserProfileDraft? profile) async {
    final fromSession = PublicAuthorName.firstSafe([
      profile?.displayName,
      profile?.handle,
    ]);
    if (fromSession != PublicAuthorName.fallback) return fromSession;

    try {
      final user = _requireCurrentUser();
      final stored = await _users.doc(user.uid).get();
      final data = stored.data() ?? const <String, dynamic>{};
      return PublicAuthorName.firstSafe([
        data['displayName'] as String?,
        data['handle'] as String?,
      ]);
    } catch (_) {
      return PublicAuthorName.fallback;
    }
  }

  /// Mirrors [_resolveAuthorName] for the profile photo. Returns null rather
  /// than throwing — a missing avatar must never block a share.
  Future<String?> _resolveAuthorAvatarUrl(UserProfileDraft? profile) async {
    final fromSession = profile?.avatarUrl;
    if (fromSession != null && fromSession.isNotEmpty) return fromSession;

    try {
      final user = _requireCurrentUser();
      final stored = await _users.doc(user.uid).get();
      final avatarUrl = stored.data()?['avatarUrl'] as String?;
      return (avatarUrl != null && avatarUrl.isNotEmpty) ? avatarUrl : null;
    } catch (_) {
      return null;
    }
  }

  User _requireCurrentUser() {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw StateError('A Firebase user must be signed in for this action.');
    }
    return user;
  }

  static DateTime? _readTimestamp(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
