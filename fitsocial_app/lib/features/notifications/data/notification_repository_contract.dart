import '../domain/notification_models.dart';

/// Read side of the notifications inbox.
///
/// Writes are deliberately absent. A notification is always a side effect of
/// some other action — a follow, a like — and it is written into that action's
/// own batch by the repository performing it, so the two can never disagree.
/// See `NotificationWrites` for the document shape both sides share.
abstract class NotificationRepository {
  /// The signed-in user's inbox, newest first, live.
  Stream<List<FitNotification>> watchNotifications(String userId);

  /// Clears the unread flag on everything currently unread. Called when the
  /// list is opened, which is the moment the badge should stop nagging.
  Future<void> markAllRead(String userId);
}
