import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/notification_models.dart';
import 'notification_repository_contract.dart';

/// Firestore-backed notifications.
///
/// Layout: `users/{recipientId}/notifications/{notificationId}` — the inbox
/// hangs off the person it belongs to, so reading it is one subcollection
/// query and the security rule is "owner only" with nothing to qualify.
///
/// Ids are deterministic (see [NotificationIds]), which is what makes the
/// inbox self-correcting: unfollowing or unliking deletes the exact document
/// the action created, so the list never keeps claiming something that has
/// been taken back.
class FirestoreNotificationRepository implements NotificationRepository {
  FirestoreNotificationRepository(this._firestore);

  final FirebaseFirestore _firestore;

  /// How far back the inbox reads. Notifications age out of usefulness fast,
  /// and one screenful of history is what the list is for.
  static const int _pageLimit = 60;

  /// Ceiling on a single mark-all-read pass. A batch is capped at 500 writes,
  /// and anyone with more than this unread will clear the rest on their next
  /// visit rather than having the write rejected outright.
  static const int _markReadLimit = 400;

  CollectionReference<Map<String, dynamic>> _inbox(String userId) =>
      _firestore.collection('users').doc(userId).collection('notifications');

  @override
  Stream<List<FitNotification>> watchNotifications(String userId) {
    return _inbox(userId)
        .orderBy('createdAt', descending: true)
        .limit(_pageLimit)
        .snapshots()
        .map((snapshot) {
      final items = <FitNotification>[];
      for (final doc in snapshot.docs) {
        final notification = _fromDoc(doc.id, doc.data());
        if (notification != null) items.add(notification);
      }
      return items;
    });
  }

  @override
  Future<void> markAllRead(String userId) async {
    final unread = await _inbox(userId)
        .where('read', isEqualTo: false)
        .limit(_markReadLimit)
        .get();
    if (unread.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in unread.docs) {
      // `read` alone: the rule that lets the owner touch their own
      // notification permits that one key and nothing else.
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  /// Null for a document whose `type` this build doesn't know, so an older app
  /// skips the row instead of rendering an empty one.
  static FitNotification? _fromDoc(String id, Map<String, dynamic> data) {
    final type = FitNotificationType.fromKey(data['type'] as String?);
    if (type == null) return null;

    final createdAt = data['createdAt'];
    return FitNotification(
      id: id,
      type: type,
      actorId: (data['actorId'] as String?) ?? '',
      actorName: (data['actorName'] as String?) ?? 'FitSocial Member',
      actorAvatarUrl: data['actorAvatarUrl'] as String?,
      isRead: (data['read'] as bool?) ?? false,
      createdAt: createdAt is Timestamp ? createdAt.toDate() : null,
      postId: data['postId'] as String?,
      postImageUrl: data['postImageUrl'] as String?,
      postType: data['postType'] as String?,
    );
  }
}

/// The write side of the same documents.
///
/// Handed to whichever repository performs the action that earns the
/// notification, so the notification can ride in that action's own batch or
/// transaction. A follow that moved the counters but never reached the other
/// person's inbox is the failure mode this exists to rule out.
class NotificationWrites {
  const NotificationWrites(this._firestore);

  final FirebaseFirestore _firestore;

  /// Where a notification for [recipientId] lives.
  DocumentReference<Map<String, dynamic>> ref(
    String recipientId,
    String notificationId,
  ) {
    return _firestore
        .collection('users')
        .doc(recipientId)
        .collection('notifications')
        .doc(notificationId);
  }

  Map<String, dynamic> followPayload({
    required String actorId,
    required String actorName,
    String? actorAvatarUrl,
  }) {
    return _payload(
      type: FitNotificationType.follow,
      actorId: actorId,
      actorName: actorName,
      actorAvatarUrl: actorAvatarUrl,
    );
  }

  Map<String, dynamic> likePayload({
    required String actorId,
    required String actorName,
    required String postId,
    String? actorAvatarUrl,
    String? postImageUrl,
    String? postType,
  }) {
    return _payload(
      type: FitNotificationType.like,
      actorId: actorId,
      actorName: actorName,
      actorAvatarUrl: actorAvatarUrl,
      extra: {
        'postId': postId,
        if (postImageUrl != null && postImageUrl.isNotEmpty)
          'postImageUrl': postImageUrl,
        if (postType != null && postType.isNotEmpty) 'postType': postType,
      },
    );
  }

  Map<String, dynamic> _payload({
    required FitNotificationType type,
    required String actorId,
    required String actorName,
    String? actorAvatarUrl,
    Map<String, dynamic> extra = const {},
  }) {
    return {
      'type': type.key,
      'actorId': actorId,
      'actorName': actorName,
      if (actorAvatarUrl != null && actorAvatarUrl.isNotEmpty)
        'actorAvatarUrl': actorAvatarUrl,
      // Written fresh on every re-follow or re-like, so an action taken again
      // after being undone surfaces at the top of the list rather than at the
      // age of the first time it happened.
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
      ...extra,
    };
  }
}
