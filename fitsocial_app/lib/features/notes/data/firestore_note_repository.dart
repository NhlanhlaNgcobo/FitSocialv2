import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/async/combine_latest.dart';
import '../../auth/domain/auth_models.dart';
import '../../main/domain/app_models.dart' show PublicAuthorName;
import '../../notifications/data/firestore_notification_repository.dart';
import '../../notifications/domain/notification_models.dart';
import '../domain/note_models.dart';
import 'note_repository_contract.dart';

/// Firestore-backed Notes.
///
/// Layout:
///   notes/{authorId}                  — that person's one current Note
///   notes/{authorId}/hearts/{userId}  — who hearted it, tagged with noteId
///
/// One document per person, keyed by them, is what makes "answering again
/// replaces the last answer" a plain overwrite. It also means old Notes never
/// pile up, so the reads filter expiry on the client rather than in the query,
/// and the query needs no composite index.
///
/// Replies are not stored here at all. A reply is a notification in the
/// author's inbox and nowhere else, which is what makes it private.
class FirestoreNoteRepository implements NoteRepository {
  FirestoreNoteRepository(this._firestore, {FirebaseAuth? firebaseAuth})
      : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _firebaseAuth;

  /// Ten per `whereIn`, for the same reason as Pulses: the read rule looks up
  /// a follower document per distinct author, and rules allow 20 lookups per
  /// query.
  static const int _authorChunkSize = 10;

  /// Same audience cap as the Pulse tray, which this rides alongside.
  static const int _maxAuthors = 100;

  /// Longest reply. A reply lands in a notification row, so it is kept to
  /// something that reads in one.
  static const int maxReplyLength = 200;

  CollectionReference<Map<String, dynamic>> get _notes =>
      _firestore.collection('notes');

  CollectionReference<Map<String, dynamic>> _hearts(String authorId) =>
      _notes.doc(authorId).collection('hearts');

  @override
  Stream<List<FitNote>> watchNotes(Set<String> authorIds) {
    if (authorIds.isEmpty) return Stream.value(const []);

    final ids = authorIds.take(_maxAuthors).toList(growable: false);
    final chunks = <Stream<List<FitNote>>>[];
    for (var i = 0; i < ids.length; i += _authorChunkSize) {
      final chunk = ids.skip(i).take(_authorChunkSize).toList(growable: false);
      chunks.add(
        // On authorId rather than the document id: the read rule is written
        // against the field, and a list query is only allowed when the rule
        // can be checked against what the query asks for.
        _notes.where('authorId', whereIn: chunk).snapshots().map(
              (snapshot) => [
                for (final doc in snapshot.docs)
                  if (_noteFromDoc(doc.data()) case final note?) note,
              ],
            ),
      );
    }
    return combineLatestLists(chunks);
  }

  @override
  Future<FitNote> publish(UserProfileDraft? profile, NoteDraft draft) async {
    if (!draft.isPublishable) {
      throw ArgumentError(
        'A note is 1 to ${NoteTiming.maxLength} characters.',
      );
    }
    final user = _requireCurrentUser();
    final authorName = await _resolveName(profile, user.uid);
    final authorAvatarUrl = await _resolveAvatarUrl(profile, user.uid);

    // The hearts on the old answer belonged to the old answer.
    await _clearHearts(user.uid);

    final noteRef = _notes.doc(user.uid);
    final noteId = _notes.doc().id;
    // expiresAt is concrete for the same reason a Pulse's is: every client
    // filters on it, and none can filter on an unresolved sentinel.
    final now = DateTime.now();
    final expiresAt = now.add(NoteTiming.lifetime);
    await noteRef.set({
      'authorId': user.uid,
      'authorName': authorName,
      if (authorAvatarUrl != null) 'authorAvatarUrl': authorAvatarUrl,
      'noteId': noteId,
      'text': draft.trimmed,
      'promptId': draft.prompt.id,
      'promptText': draft.prompt.text,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
    });

    return FitNote(
      authorId: user.uid,
      authorName: authorName,
      authorAvatarUrl: authorAvatarUrl,
      noteId: noteId,
      text: draft.trimmed,
      promptId: draft.prompt.id,
      promptText: draft.prompt.text,
      createdAt: now,
      expiresAt: expiresAt,
    );
  }

  @override
  Future<void> deleteNote() async {
    final user = _requireCurrentUser();
    // Hearts first, while the Note still exists for the rule that lets the
    // author clear them to read.
    await _clearHearts(user.uid);
    await _notes.doc(user.uid).delete();
  }

  @override
  Stream<List<NoteHeart>> watchHearts(String noteId) {
    final user = _firebaseAuth.currentUser;
    if (user == null) return Stream.value(const []);
    return _hearts(user.uid)
        .where('noteId', isEqualTo: noteId)
        .snapshots()
        .map((snapshot) {
      final hearts = [
        for (final doc in snapshot.docs)
          NoteHeart(
            userId: doc.id,
            userName: PublicAuthorName.sanitize(
              doc.data()['userName'] as String?,
            ),
            userAvatarUrl: doc.data()['userAvatarUrl'] as String?,
            noteId: noteId,
            createdAt: _readTimestamp(doc.data()['createdAt']),
          ),
      ]..sort((a, b) {
          final at = a.createdAt, bt = b.createdAt;
          if (at == null || bt == null) return 0;
          return bt.compareTo(at);
        });
      return hearts;
    });
  }

  @override
  Stream<bool> watchMyHeart(String authorId, String noteId) {
    final user = _firebaseAuth.currentUser;
    if (user == null) return Stream.value(false);
    return _hearts(authorId).doc(user.uid).snapshots().map(
          (doc) => doc.exists && doc.data()?['noteId'] == noteId,
        );
  }

  @override
  Future<void> setHeart(
    FitNote note, {
    required bool hearted,
    UserProfileDraft? profile,
  }) async {
    final user = _requireCurrentUser();
    if (note.authorId == user.uid) return;

    final heartRef = _hearts(note.authorId).doc(user.uid);
    final notifications = NotificationWrites(_firestore);
    final notificationRef = notifications.ref(
      note.authorId,
      NotificationIds.noteHeart(note.noteId, user.uid),
    );

    final batch = _firestore.batch();
    if (hearted) {
      final name = await _resolveName(profile, user.uid);
      final avatarUrl = await _resolveAvatarUrl(profile, user.uid);
      batch.set(heartRef, {
        'userId': user.uid,
        'userName': name,
        if (avatarUrl != null) 'userAvatarUrl': avatarUrl,
        'noteId': note.noteId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(
        notificationRef,
        notifications.noteHeartPayload(
          actorId: user.uid,
          actorName: name,
          actorAvatarUrl: avatarUrl,
          noteText: note.text,
        ),
      );
    } else {
      batch.delete(heartRef);
      batch.delete(notificationRef);
    }
    await batch.commit();
  }

  @override
  Future<void> reply(
    FitNote note,
    String text,
    UserProfileDraft? profile,
  ) async {
    final user = _requireCurrentUser();
    final said = text.trim();
    if (said.isEmpty) return;
    if (said.length > maxReplyLength) {
      throw ArgumentError('A reply is at most $maxReplyLength characters.');
    }
    if (note.authorId == user.uid) return;

    final name = await _resolveName(profile, user.uid);
    final avatarUrl = await _resolveAvatarUrl(profile, user.uid);
    final notifications = NotificationWrites(_firestore);
    // Every reply is its own row: two things said are two things to read.
    await notifications.ref(note.authorId, 'noteReply_${_notes.doc().id}').set(
          notifications.noteReplyPayload(
            actorId: user.uid,
            actorName: name,
            actorAvatarUrl: avatarUrl,
            noteText: note.text,
            replyText: said,
          ),
        );
  }

  Future<void> _clearHearts(String authorId) async {
    final existing = await _hearts(authorId).get();
    if (existing.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in existing.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// Null for a document missing what a bubble needs, so a malformed write
  /// drops one bubble instead of the whole tray.
  static FitNote? _noteFromDoc(Map<String, dynamic> data) {
    final authorId = data['authorId'] as String?;
    final text = (data['text'] as String?)?.trim();
    final expiresAt = _readTimestamp(data['expiresAt']);
    if (authorId == null || text == null || text.isEmpty || expiresAt == null) {
      return null;
    }
    return FitNote(
      authorId: authorId,
      authorName: PublicAuthorName.sanitize(data['authorName'] as String?),
      authorAvatarUrl: data['authorAvatarUrl'] as String?,
      noteId: (data['noteId'] as String?) ?? '',
      text: text,
      promptId: (data['promptId'] as String?) ?? '',
      promptText: (data['promptText'] as String?) ?? '',
      // A Note just written has no server time yet on the writer's own
      // snapshot; its expiry minus the lifetime is the same moment.
      createdAt: _readTimestamp(data['createdAt']) ??
          expiresAt.subtract(NoteTiming.lifetime),
      expiresAt: expiresAt,
    );
  }

  Future<String> _resolveName(UserProfileDraft? profile, String uid) async {
    final fromSession = PublicAuthorName.firstSafe([
      profile?.displayName,
      profile?.handle,
    ]);
    if (fromSession != PublicAuthorName.fallback) return fromSession;
    try {
      final stored = await _firestore.collection('users').doc(uid).get();
      final data = stored.data() ?? const <String, dynamic>{};
      return PublicAuthorName.firstSafe([
        data['displayName'] as String?,
        data['handle'] as String?,
      ]);
    } catch (_) {
      return PublicAuthorName.fallback;
    }
  }

  Future<String?> _resolveAvatarUrl(
      UserProfileDraft? profile, String uid) async {
    final fromSession = profile?.avatarUrl;
    if (fromSession != null && fromSession.isNotEmpty) return fromSession;
    try {
      final stored = await _firestore.collection('users').doc(uid).get();
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
