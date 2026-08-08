import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/notifications/application/notification_providers.dart';
import 'package:fitsocial_app/features/notifications/data/notification_repository.dart';
import 'package:fitsocial_app/features/notifications/data/notification_repository_contract.dart';
import 'package:fitsocial_app/features/notifications/domain/notification_models.dart';
import 'package:fitsocial_app/features/notifications/presentation/notifications_screen.dart';

class _FakeNotificationRepository implements NotificationRepository {
  _FakeNotificationRepository(this._items);

  final List<FitNotification> _items;
  final _controller = StreamController<List<FitNotification>>.broadcast();
  int markReadCalls = 0;

  @override
  Stream<List<FitNotification>> watchNotifications(String userId) async* {
    yield _items;
    yield* _controller.stream;
  }

  @override
  Future<void> markAllRead(String userId) async {
    markReadCalls++;
    // What the real one does, seen from the reader's side: the same stream
    // reports the flags cleared a moment later.
    _controller.add([
      for (final item in _items)
        FitNotification(
          id: item.id,
          type: item.type,
          actorId: item.actorId,
          actorName: item.actorName,
          isRead: true,
          createdAt: item.createdAt,
          postId: item.postId,
          postType: item.postType,
        ),
    ]);
  }

  void dispose() => _controller.close();
}

/// Only the follow-state stream is needed: the follow-back button on a follow
/// row watches it.
class _StubContentRepository extends UnconfiguredContentRepository {
  @override
  Stream<bool> watchIsFollowing(String currentUserId, String targetUserId) =>
      Stream.value(false);
}

FitNotification followFrom(String name, {bool isRead = false}) {
  return FitNotification(
    id: 'n-$name',
    type: FitNotificationType.follow,
    actorId: 'u-$name',
    actorName: name,
    isRead: isRead,
    createdAt: DateTime.now().subtract(const Duration(hours: 3)),
  );
}

FitNotification likeFrom(String name, {String postType = 'image'}) {
  return FitNotification(
    id: 'n-like-$name',
    type: FitNotificationType.like,
    actorId: 'u-$name',
    actorName: name,
    isRead: false,
    createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
    postId: 'p1',
    postType: postType,
  );
}

Widget harness(NotificationRepository repository) {
  return ProviderScope(
    overrides: [
      notificationRepositoryProvider.overrideWithValue(repository),
      contentRepositoryProvider.overrideWithValue(_StubContentRepository()),
      currentUserIdProvider.overrideWithValue('me'),
    ],
    child: const MaterialApp(home: NotificationsScreen()),
  );
}

void main() {
  group('notifications screen', () {
    testWidgets('says who followed you and what they liked', (tester) async {
      final repository = _FakeNotificationRepository([
        followFrom('Neo Mokoena'),
        likeFrom('Thandi', postType: 'run'),
      ]);
      addTearDown(repository.dispose);

      await tester.pumpWidget(harness(repository));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Neo Mokoena started following you',
            findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Thandi liked your run', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('offers to follow back, and only on the follow row',
        (tester) async {
      final repository = _FakeNotificationRepository([
        followFrom('Neo Mokoena'),
        likeFrom('Thandi'),
      ]);
      addTearDown(repository.dispose);

      await tester.pumpWidget(harness(repository));
      await tester.pumpAndSettle();

      expect(find.text('Follow'), findsOneWidget);
    });

    testWidgets('opening the list is what marks it read', (tester) async {
      final repository = _FakeNotificationRepository([
        followFrom('Neo Mokoena'),
        likeFrom('Thandi'),
      ]);
      addTearDown(repository.dispose);

      await tester.pumpWidget(harness(repository));
      await tester.pumpAndSettle();

      expect(repository.markReadCalls, 1);
    });

    testWidgets('nothing unread means nothing to mark', (tester) async {
      final repository = _FakeNotificationRepository([
        followFrom('Neo Mokoena', isRead: true),
      ]);
      addTearDown(repository.dispose);

      await tester.pumpWidget(harness(repository));
      await tester.pumpAndSettle();

      expect(repository.markReadCalls, 0);
    });

    testWidgets('an empty inbox says so', (tester) async {
      final repository = _FakeNotificationRepository([]);
      addTearDown(repository.dispose);

      await tester.pumpWidget(harness(repository));
      await tester.pumpAndSettle();

      expect(find.text('Nothing here yet'), findsOneWidget);
    });
  });

  group('unread count', () {
    test('counts only what has not been read', () async {
      final repository = _FakeNotificationRepository([
        followFrom('Neo Mokoena'),
        followFrom('Thandi', isRead: true),
        likeFrom('Sipho'),
      ]);
      addTearDown(repository.dispose);

      final container = ProviderContainer(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(repository),
          currentUserIdProvider.overrideWithValue('me'),
        ],
      );
      addTearDown(container.dispose);

      // Resolve the stream's first event before reading the derived count.
      await container.read(notificationsProvider.future);
      expect(container.read(unreadNotificationCountProvider), 2);
    });
  });
}
