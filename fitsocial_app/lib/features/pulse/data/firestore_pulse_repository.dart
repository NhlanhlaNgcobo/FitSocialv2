import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cross_file/cross_file.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../shared/async/combine_latest.dart';
import '../../../shared/reactions/fit_reaction.dart';
import '../../auth/domain/auth_models.dart';
import '../../main/domain/app_models.dart' show Comment, PublicAuthorName;
import '../../main/domain/shared_post.dart';
import '../domain/pulse_models.dart';
import 'pulse_repository_contract.dart';

/// Firestore-backed Pulses.
///
/// Layout:
///   pulses/{pulseId}                      — one segment, with an expiresAt
///   pulses/{pulseId}/views/{viewerId}     — who watched it
///   pulses/{pulseId}/reactions/{userId}   — which reaction they picked
///   pulses/{pulseId}/comments/{commentId} — the conversation under it
///   users/{uid}/pulseSeen/{authorId}      — that viewer's per-author cursor
///
/// The per-reaction totals live on the Pulse document as a `reactionCounts`
/// map, moved by increment alongside each reaction write. That denormalisation is
/// what lets the reaction bar draw a live count during playback without a
/// second query per segment; the reactions subcollection is only read when
/// someone opens the breakdown.
///
/// Expiry is belt-and-braces. `expiresAt` is written so a Firestore TTL policy
/// can sweep the documents server-side, but TTL deletion is only guaranteed
/// within 24 hours of the expiry time — so reads filter on it as well and a
/// Pulse disappears from the app the moment it lapses.
class FirestorePulseRepository implements PulseRepository {
  FirestorePulseRepository(
    this._firestore, {
    FirebaseAuth? firebaseAuth,
    FirebaseStorage? storage,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _firebaseAuth;
  final FirebaseStorage _storage;

  /// How many authors go into one `whereIn` filter.
  ///
  /// Ten, not the thirty Firestore allows — this number is set by the security
  /// rules, not by the query. The rule on `/pulses` checks each returned
  /// document against a follower lookup, and the rules engine permits 20
  /// document lookups per query. Identical lookups are cached, so the cost is
  /// one per distinct author in the result: keeping chunks at ten leaves that
  /// comfortably inside the budget.
  static const int _authorChunkSize = 10;

  /// Ceiling on how many live Pulses one chunk will consider. Well clear of
  /// anything ten accounts produce in a day, and it keeps one runaway account
  /// from unbounding the query.
  static const int _chunkLimit = 100;

  /// Upper bound on the audience a single tray will query for.
  ///
  /// Each chunk is a live listener, so this is really a cap on open listeners
  /// — ten of them here. Someone following more people than this gets a tray
  /// built from the first hundred; past that the right shape is a fan-out
  /// inbox written server-side, not more sockets.
  static const int _maxTrayAuthors = 100;

  static const Duration _imageUploadTimeout = Duration(seconds: 60);
  static const Duration _videoUploadTimeout = Duration(minutes: 3);

  /// How many reactors and comments a single Pulse will load.
  ///
  /// Both are sheets a person scrolls, not feeds — and a Pulse only lives for a
  /// day, so there is a natural ceiling on how much either can accumulate.
  static const int _reactionsLimit = 200;
  static const int _commentsLimit = 200;

  /// Longest a Pulse comment may be. Generous enough for a real sentence,
  /// short enough that one comment can't fill the sheet.
  static const int _maxCommentLength = 500;

  CollectionReference<Map<String, dynamic>> get _pulses =>
      _firestore.collection('pulses');

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> _views(String pulseId) =>
      _pulses.doc(pulseId).collection('views');

  CollectionReference<Map<String, dynamic>> _reactions(String pulseId) =>
      _pulses.doc(pulseId).collection('reactions');

  CollectionReference<Map<String, dynamic>> _comments(String pulseId) =>
      _pulses.doc(pulseId).collection('comments');

  CollectionReference<Map<String, dynamic>> _seenMarkers(String userId) =>
      _users.doc(userId).collection('pulseSeen');

  @override
  Stream<List<PulseSegment>> watchActivePulses(Set<String> authorIds) {
    if (authorIds.isEmpty) return Stream.value(const []);

    final ids = authorIds.take(_maxTrayAuthors).toList(growable: false);

    final chunks = <Stream<List<PulseSegment>>>[];
    for (var i = 0; i < ids.length; i += _authorChunkSize) {
      final chunk = ids.skip(i).take(_authorChunkSize).toList(growable: false);
      chunks.add(
        // Ordering by expiresAt is equivalent to ordering by createdAt — every
        // Pulse has the same lifetime — and it is the field the range filter
        // is on, which Firestore requires the first orderBy to match.
        _pulses
            .where('authorId', whereIn: chunk)
            .where('expiresAt', isGreaterThan: Timestamp.now())
            .orderBy('expiresAt', descending: true)
            .limit(_chunkLimit)
            .snapshots()
            .map((snapshot) => snapshot.docs
                .map((doc) => _segmentFromDoc(doc.id, doc.data()))
                .toList(growable: false)),
      );
    }

    return combineLatestLists(chunks);
  }

  @override
  Stream<Map<String, DateTime>> watchSeenMarkers(String userId) {
    return _seenMarkers(userId).snapshots().map((snapshot) {
      final markers = <String, DateTime>{};
      for (final doc in snapshot.docs) {
        final lastSeenAt = _readTimestamp(doc.data()['lastSeenAt']);
        if (lastSeenAt != null) markers[doc.id] = lastSeenAt;
      }
      return markers;
    });
  }

  @override
  Future<PulseSegment> publish(
    UserProfileDraft? profile,
    PulseDraft draft,
  ) async {
    if (!draft.isPublishable) {
      throw ArgumentError('This Pulse has nothing in it yet.');
    }

    final user = _requireCurrentUser();
    final authorName = await _resolveAuthorName(profile);
    final authorAvatarUrl = await _resolveAuthorAvatarUrl(profile);

    String? mediaUrl;
    if (draft.type.carriesMedia) {
      mediaUrl = await _uploadMedia(
        draft.localFilePath!,
        isVideo: draft.type == PulseMediaType.video,
      );
    }

    // createdAt is the server's clock, but expiresAt has to be a concrete
    // value: it is both what the TTL policy reads and what every client
    // filters on, and neither can work against an unresolved sentinel.
    final now = DateTime.now();
    final expiresAt = now.add(PulseTiming.lifetime);
    final document = _pulses.doc();

    await document.set({
      'authorId': user.uid,
      'authorName': authorName,
      if (authorAvatarUrl != null) 'authorAvatarUrl': authorAvatarUrl,
      'type': draft.type.key,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      // A snapshot of the shared post, not a pointer to it: the people who see
      // this Pulse may not be allowed to read that post, and the card is drawn
      // on every frame of playback. See [SharedPostRef].
      if (draft.sharedPost != null) 'sharedPost': draft.sharedPost!.toMap(),
      if (draft.text.trim().isNotEmpty) 'text': draft.text.trim(),
      'gradientKey': draft.gradientKey,
      if (draft.aspectRatio != null) 'aspectRatio': draft.aspectRatio,
      if (draft.videoDuration != null)
        'videoDurationMs': draft.videoDuration!.inMilliseconds,
      'viewCount': 0,
      // Seeded empty so the map is always a map: the rule that guards a
      // reaction write diffs it against what is already there, and starting
      // from a present-but-empty field keeps that comparison uniform.
      'reactionCounts': const <String, int>{},
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
    });

    return PulseSegment(
      id: document.id,
      authorId: user.uid,
      authorName: authorName,
      authorAvatarUrl: authorAvatarUrl,
      type: draft.type,
      mediaUrl: mediaUrl,
      text: draft.text.trim(),
      gradientKey: draft.gradientKey,
      createdAt: now,
      expiresAt: expiresAt,
      videoDuration: draft.videoDuration,
      aspectRatio: draft.aspectRatio,
      sharedPost: draft.sharedPost,
    );
  }

  @override
  Future<void> markSeen(String authorId, DateTime lastSeenAt) async {
    final user = _requireCurrentUser();
    final markerRef = _seenMarkers(user.uid).doc(authorId);

    // Rewinding the cursor would light a ring back up for content the user has
    // already watched, so an out-of-order write is dropped rather than applied.
    final existing = await markerRef.get();
    final stored = _readTimestamp(existing.data()?['lastSeenAt']);
    if (stored != null && !lastSeenAt.isAfter(stored)) return;

    await markerRef.set({
      'authorId': authorId,
      'lastSeenAt': Timestamp.fromDate(lastSeenAt),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> recordView(String pulseId, UserProfileDraft? profile) async {
    final user = _requireCurrentUser();
    final pulseRef = _pulses.doc(pulseId);
    final viewRef = _views(pulseId).doc(user.uid);

    final snapshot = await pulseRef.get();
    if (!snapshot.exists) return;
    // Your own views don't count, matching what people expect from a viewer
    // list: it should show the audience, not the poster.
    if (snapshot.data()?['authorId'] == user.uid) return;

    final existing = await viewRef.get();
    if (existing.exists) return;

    final viewerName = await _resolveAuthorName(profile);
    final viewerAvatarUrl = await _resolveAuthorAvatarUrl(profile);

    // The count and the record move together — a bare increment would let the
    // number drift away from the list that explains it.
    final batch = _firestore.batch();
    batch.set(viewRef, {
      'viewerId': user.uid,
      'viewerName': viewerName,
      if (viewerAvatarUrl != null) 'viewerAvatarUrl': viewerAvatarUrl,
      'viewedAt': FieldValue.serverTimestamp(),
    });
    batch.update(pulseRef, {'viewCount': FieldValue.increment(1)});
    await batch.commit();
  }

  @override
  Future<void> deletePulse(String pulseId) async {
    final user = _requireCurrentUser();
    final pulseRef = _pulses.doc(pulseId);

    final snapshot = await pulseRef.get();
    if (!snapshot.exists) return;

    final data = snapshot.data() ?? const <String, dynamic>{};
    // Checked here as well as in the rules, so the user gets a readable
    // message instead of a raw permission-denied.
    if (data['authorId'] != user.uid) {
      throw StateError('You can only delete your own Pulse.');
    }

    // Firestore does not cascade into subcollections, so everything hanging off
    // the Pulse goes first — the rules that let the author clear these read the
    // parent Pulse, which has to still exist for those checks to pass.
    await _clearSubcollection(_views(pulseId));
    await _clearSubcollection(_reactions(pulseId));
    await _clearSubcollection(_comments(pulseId));

    await pulseRef.delete();

    // Best effort: the upload is orphaned the moment the document is gone and
    // keeps costing storage, but the Pulse is already deleted either way.
    final mediaUrl = data['mediaUrl'] as String?;
    if (mediaUrl != null && mediaUrl.isNotEmpty) {
      try {
        await _storage.refFromURL(mediaUrl).delete();
      } catch (_) {
        // Already gone, or a URL we can't resolve — nothing to recover.
      }
    }
  }

  @override
  Stream<List<PulseViewerRecord>> watchViewers(String pulseId) {
    return _views(pulseId)
        .orderBy('viewedAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return PulseViewerRecord(
                userId: doc.id,
                name: PublicAuthorName.sanitize(data['viewerName'] as String?),
                avatarUrl: data['viewerAvatarUrl'] as String?,
                viewedAt: _readTimestamp(data['viewedAt']) ?? DateTime.now(),
              );
            }).toList(growable: false));
  }

  @override
  Stream<FitReaction?> watchMyReaction(String pulseId) {
    final user = _firebaseAuth.currentUser;
    if (user == null) return Stream.value(null);

    return _reactions(pulseId).doc(user.uid).snapshots().map(
          (doc) => FitReaction.fromKey(doc.data()?['reaction'] as String?),
        );
  }

  @override
  Future<void> setReaction(
    String pulseId,
    FitReaction? reaction,
    UserProfileDraft? profile,
  ) async {
    final user = _requireCurrentUser();
    final reactionRef = _reactions(pulseId).doc(user.uid);
    final pulseRef = _pulses.doc(pulseId);

    final existing = await reactionRef.get();
    final previous =
        FitReaction.fromKey(existing.data()?['reaction'] as String?);
    // Picking the reaction you already hold is not an event. Returning here
    // is what makes a double tap harmless rather than a double count.
    if (previous == reaction) return;

    // Resolved before the batch, because a batch may not read.
    final reactorName =
        reaction == null ? null : await _resolveAuthorName(profile);
    final reactorAvatarUrl =
        reaction == null ? null : await _resolveAuthorAvatarUrl(profile);

    // The record and the counters move together. Split into two writes, a
    // failure between them would leave a reaction on the bar that nobody gave, or
    // a reaction in the list that the count denies.
    final batch = _firestore.batch();

    if (reaction == null) {
      batch.delete(reactionRef);
    } else {
      batch.set(reactionRef, {
        'reactorId': user.uid,
        'reactorName': reactorName,
        if (reactorAvatarUrl != null) 'reactorAvatarUrl': reactorAvatarUrl,
        'reaction': reaction.key,
        // Rewritten on a change of reaction, so the breakdown is ordered by when
        // someone last felt something rather than when they first tapped.
        'reactedAt': FieldValue.serverTimestamp(),
        'expiresAt': _subdocumentExpiry(),
      });
    }

    // Dotted paths, so the two counters move inside one map without either
    // client having to read and rewrite the whole thing.
    batch.update(pulseRef, {
      if (previous != null)
        'reactionCounts.${previous.key}': FieldValue.increment(-1),
      if (reaction != null)
        'reactionCounts.${reaction.key}': FieldValue.increment(1),
    });

    await batch.commit();
  }

  @override
  Stream<List<FitReactionRecord>> watchReactions(String pulseId) {
    return _reactions(pulseId)
        .orderBy('reactedAt', descending: true)
        .limit(_reactionsLimit)
        .snapshots()
        .map((snapshot) {
      final records = <FitReactionRecord>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final reaction = FitReaction.fromKey(data['reaction'] as String?);
        // A reaction this build doesn't know is skipped rather than guessed at.
        if (reaction == null) continue;
        records.add(
          FitReactionRecord(
            userId: doc.id,
            name: PublicAuthorName.sanitize(data['reactorName'] as String?),
            avatarUrl: data['reactorAvatarUrl'] as String?,
            reaction: reaction,
            reactedAt: _readTimestamp(data['reactedAt']) ?? DateTime.now(),
          ),
        );
      }
      return records;
    });
  }

  @override
  Stream<List<Comment>> watchComments(String pulseId) {
    return _comments(pulseId)
        .orderBy('createdAt', descending: false)
        .limit(_commentsLimit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return Comment(
                id: doc.id,
                authorId: (data['authorId'] as String?) ?? '',
                authorName:
                    PublicAuthorName.sanitize(data['authorName'] as String?),
                authorAvatarUrl: data['authorAvatarUrl'] as String?,
                text: (data['text'] as String?) ?? '',
                // A comment reaches its own writer from the local cache before
                // the server has stamped createdAt; treating that window as
                // "now" keeps it at the bottom of the thread, which is where
                // the person who just wrote it expects to find it.
                createdAt: _readTimestamp(data['createdAt']) ?? DateTime.now(),
              );
            }).toList(growable: false));
  }

  @override
  Future<Comment> addComment(
    String pulseId,
    String text,
    UserProfileDraft? profile,
  ) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('A comment needs something in it.');
    }
    if (trimmed.length > _maxCommentLength) {
      throw ArgumentError(
        'That comment is too long — keep it under $_maxCommentLength '
        'characters.',
      );
    }

    final user = _requireCurrentUser();
    final authorName = await _resolveAuthorName(profile);
    final authorAvatarUrl = await _resolveAuthorAvatarUrl(profile);
    final commentRef = _comments(pulseId).doc();

    await commentRef.set({
      'authorId': user.uid,
      'authorName': authorName,
      if (authorAvatarUrl != null) 'authorAvatarUrl': authorAvatarUrl,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': _subdocumentExpiry(),
    });

    return Comment(
      id: commentRef.id,
      authorId: user.uid,
      authorName: authorName,
      authorAvatarUrl: authorAvatarUrl,
      text: trimmed,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> deleteComment(String pulseId, String commentId) async {
    // Authorisation is the rules' job here: the writer and the Pulse's author
    // may both remove a comment, and only the server can tell whether the
    // caller is either.
    await _comments(pulseId).doc(commentId).delete();
  }

  /// Expiry stamp for a reaction or a comment.
  ///
  /// Measured from now rather than copied off the parent Pulse, which would
  /// cost a read on every tap. The two differ by at most a Pulse's lifetime,
  /// and this value is only ever read by the TTL sweep — which is itself
  /// guaranteed only to within a day — so buying exactness here would be
  /// paying for precision that the mechanism cannot use.
  ///
  /// It exists at all because Firestore does not cascade: a Pulse removed by
  /// the TTL policy rather than by its author leaves its subcollections behind,
  /// billable and unreachable. Enable the matching policies once per project,
  /// either in the Cloud console — Firestore > Databases > (default) >
  /// Time-to-live > Create Policy, one per collection group, field `expiresAt`
  /// — or, if the CLI is installed:
  ///
  ///   gcloud firestore fields ttls update expiresAt \
  ///     --collection-group=reactions --enable-ttl --project=fitsocialv2
  ///   gcloud firestore fields ttls update expiresAt \
  ///     --collection-group=comments --enable-ttl --project=fitsocialv2
  ///
  /// The console only lists collection groups that already hold a document, so
  /// neither policy can be created until someone has actually reacted and
  /// commented. That ordering is harmless — there is nothing to sweep until
  /// then — but it does mean this is a step to come back to after the first
  /// real use, not one that can be done up front.
  ///
  /// A policy applies to a collection GROUP, and `comments` is a name this app
  /// uses twice. Post comments are unaffected only because TTL touches nothing
  /// that lacks the field, and those never have it — so `expiresAt` must never
  /// be written onto a post comment.
  static Timestamp _subdocumentExpiry() =>
      Timestamp.fromDate(DateTime.now().add(PulseTiming.lifetime));

  /// Empties a Pulse subcollection in batches, staying under Firestore's
  /// 500-write ceiling.
  Future<void> _clearSubcollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    final snapshot = await collection.get();
    for (var i = 0; i < snapshot.docs.length; i += 500) {
      final batch = _firestore.batch();
      for (final doc in snapshot.docs.skip(i).take(500)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  Future<String> _uploadMedia(
    String localFilePath, {
    required bool isVideo,
  }) async {
    final user = _requireCurrentUser();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref().child(
          'pulses/${user.uid}/$timestamp.${isVideo ? 'mp4' : 'jpg'}',
        );

    // Bytes rather than a dart:io File, so this works on every platform — the
    // same reason the post and meal uploads do it this way.
    final bytes = await XFile(localFilePath).readAsBytes();
    final task = ref.putData(
      bytes,
      SettableMetadata(contentType: isVideo ? 'video/mp4' : 'image/jpeg'),
    );
    final snapshot = await task.timeout(
      isVideo ? _videoUploadTimeout : _imageUploadTimeout,
      onTimeout: () => throw PulseUploadTimeout(
        isVideo
            ? 'That video took too long to upload. Try a shorter clip.'
            : 'That photo took too long to upload.',
      ),
    );
    return snapshot.ref.getDownloadURL();
  }

  PulseSegment _segmentFromDoc(String id, Map<String, dynamic> data) {
    final expiresAt =
        _readTimestamp(data['expiresAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    // A just-written document reaches its author from the local cache before
    // the server has stamped createdAt. Deriving it from expiresAt keeps the
    // segment orderable during that window instead of sorting as epoch zero.
    final createdAt = _readTimestamp(data['createdAt']) ??
        expiresAt.subtract(PulseTiming.lifetime);
    final videoDurationMs = (data['videoDurationMs'] as num?)?.toInt();

    return PulseSegment(
      id: id,
      authorId: (data['authorId'] as String?) ?? '',
      // Sanitised on read as well as write: this name is shown to everyone,
      // and older records may predate the write-path guard.
      authorName: PublicAuthorName.sanitize(data['authorName'] as String?),
      authorAvatarUrl: data['authorAvatarUrl'] as String?,
      type: PulseMediaType.fromKey(data['type'] as String?),
      mediaUrl: data['mediaUrl'] as String?,
      text: (data['text'] as String?) ?? '',
      gradientKey: (data['gradientKey'] as String?) ?? 'ember',
      createdAt: createdAt,
      expiresAt: expiresAt,
      viewCount: (data['viewCount'] as num?)?.toInt() ?? 0,
      reactions: readFitReactionCounts(data['reactionCounts']),
      videoDuration: videoDurationMs == null
          ? null
          : Duration(milliseconds: videoDurationMs),
      aspectRatio: (data['aspectRatio'] as num?)?.toDouble(),
      sharedPost: SharedPostRef.fromMap(data['sharedPost']),
    );
  }

  /// Public name to attribute a Pulse to.
  ///
  /// Deliberately never consults the auth email — Pulses are visible to the
  /// whole community. Prefers the in-memory session profile and only falls
  /// back to a stored read when the session has nothing usable.
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
  /// than throwing — a missing avatar must never block a Pulse.
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

/// Raised when an upload exceeds its budget, so the composer can say something
/// useful instead of hanging on a stalled connection.
class PulseUploadTimeout implements Exception {
  const PulseUploadTimeout(this.message);
  final String message;

  @override
  String toString() => message;
}
