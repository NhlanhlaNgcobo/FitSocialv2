import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../domain/notification_models.dart';
import 'firestore_notification_repository.dart';
import 'notification_repository_contract.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  final status = ref.watch(bootstrapStatusProvider);
  if (status.canUseFirebase) {
    return FirestoreNotificationRepository(FirebaseFirestore.instance);
  }
  return const UnconfiguredNotificationRepository();
});

/// Stand-in used when Firebase was never configured for this build.
///
/// An empty inbox rather than an error: notifications are something the app
/// shows alongside everything else, and a build without a backend should still
/// render the screen and say there is nothing in it.
class UnconfiguredNotificationRepository implements NotificationRepository {
  const UnconfiguredNotificationRepository();

  @override
  Stream<List<FitNotification>> watchNotifications(String userId) =>
      Stream.value(const []);

  @override
  Future<void> markAllRead(String userId) async {}
}
