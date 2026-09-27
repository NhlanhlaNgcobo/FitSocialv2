import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/notifications/data/notification_repository.dart';
import 'package:fitsocial_app/features/notifications/data/notification_repository_contract.dart';
import 'package:fitsocial_app/features/notifications/domain/notification_models.dart';
import 'package:fitsocial_app/features/main/presentation/post_detail_screen.dart';
import 'package:fitsocial_app/features/notifications/presentation/notifications_screen.dart';
import 'package:fitsocial_app/features/settings/presentation/settings_screen.dart';
import 'package:fitsocial_app/shared/reactions/fit_reaction.dart';

import 'shot_data.dart';
import 'shot_fakes.dart';
import 'shot_harness.dart';

List<FitNotification> inbox() {
  final now = DateTime.now();
  FitNotification n(String id, FitNotificationType type, String who, int minsAgo,
          {bool read = false, String? postId, String? postType, FitReaction? reaction,
          String? challengeId, String? challengeTitle}) =>
      FitNotification(
        id: id, type: type, actorId: 'u-${who.split(' ').first.toLowerCase()}',
        actorName: who, isRead: read, createdAt: now.subtract(Duration(minutes: minsAgo)),
        postId: postId, postType: postType, reaction: reaction,
        challengeId: challengeId, challengeTitle: challengeTitle,
      );
  return [
    n('1', FitNotificationType.like, 'Ayanda Zulu', 2, postId: 'p-sipho-run', postType: 'run', reaction: FitReaction.fire),
    n('2', FitNotificationType.reply, 'Lerato Mokoena', 9, postId: 'p-sipho-run', postType: 'run'),
    n('3', FitNotificationType.challengeInvite, 'Neo Mahlangu', 26, challengeId: 'ch-seapoint', challengeTitle: 'Sea Point Sunsets: 50 km'),
    n('4', FitNotificationType.tag, 'Thandi Khumalo', 58, postId: 'p-thandi-legs', postType: 'workout'),
    n('5', FitNotificationType.pulseShare, 'Lerato Mokoena', 95, postId: 'p-sipho-run', postType: 'run'),
    n('6', FitNotificationType.follow, 'Neo Mahlangu', 180, read: true),
    n('7', FitNotificationType.challengeAccepted, 'Ayanda Zulu', 300, read: true, challengeId: 'ch-100k', challengeTitle: 'Road to Comrades: 100 km'),
    n('8', FitNotificationType.comment, 'Thandi Khumalo', 420, read: true, postId: 'p-sipho-run', postType: 'run'),
  ];
}

class _Inbox implements NotificationRepository {
  @override
  Stream<List<FitNotification>> watchNotifications(String userId) => Stream.value(inbox());
  @override
  Future<void> markAllRead(String userId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> inboxOverrides() => [
      ...signedIn(),
      notificationRepositoryProvider.overrideWithValue(_Inbox()),
    ];

void main() {
  testWidgets('notifications', (tester) async {
    await shoot(tester, 'notifications',
        shotApp(const NotificationsScreen(), pushed: true, overrides: inboxOverrides()));
  });
  testWidgets('settings', (tester) async {
    await shoot(tester, 'settings',
        shotApp(const SettingsScreen(), pushed: true, overrides: inboxOverrides()), height: 1800);
  });
  testWidgets('post detail', (tester) async {
    await shoot(tester, 'post_detail',
        shotApp(PostDetailScreen(postId: 'p-sipho-run', initialPost: homeFeedPosts.first),
            pushed: true, overrides: inboxOverrides()),
        height: 1500);
  });
}
