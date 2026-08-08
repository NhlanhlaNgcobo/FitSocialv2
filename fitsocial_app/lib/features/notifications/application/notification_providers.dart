import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/app_session.dart';
import '../../main/application/content_providers.dart' show currentUserIdProvider;
import '../data/notification_repository.dart';
import '../domain/notification_models.dart';

/// The signed-in user's inbox, live.
///
/// One stream feeds both the list and the badge on the home bell: the unread
/// count is derived from the same documents rather than counted by a second
/// query, so the badge can never disagree with what the list shows.
final notificationsProvider = StreamProvider<List<FitNotification>>((ref) {
  // Re-subscribe on sign-in/out: the query is scoped to one uid, and the
  // account switcher can replace it without the app restarting.
  ref.watch(appSessionProvider);

  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const <FitNotification>[]);
  return ref.watch(notificationRepositoryProvider).watchNotifications(userId);
});

/// How many notifications the user has not seen yet. Zero while the stream is
/// still loading, so the badge appears with the data instead of flickering.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final items = ref.watch(notificationsProvider).valueOrNull;
  if (items == null) return 0;
  return items.where((item) => !item.isRead).length;
});

/// Clears the unread flags. The list is a live stream, so nothing needs
/// invalidating afterwards — the change comes back on its own.
final markNotificationsReadProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    await ref.read(notificationRepositoryProvider).markAllRead(userId);
  };
});
