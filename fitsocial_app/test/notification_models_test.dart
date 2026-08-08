import 'package:fitsocial_app/features/notifications/domain/notification_models.dart';
import 'package:flutter_test/flutter_test.dart';

FitNotification like({String? postType, String? postId = 'p1'}) {
  return FitNotification(
    id: 'n1',
    type: FitNotificationType.like,
    actorId: 'u2',
    actorName: 'Neo Mokoena',
    isRead: false,
    postId: postId,
    postType: postType,
  );
}

const follow = FitNotification(
  id: 'n2',
  type: FitNotificationType.follow,
  actorId: 'u3',
  actorName: 'Thandi',
  isRead: true,
);

void main() {
  group('notification type keys', () {
    test('round-trip through their stored form', () {
      for (final type in FitNotificationType.values) {
        expect(FitNotificationType.fromKey(type.key), type);
      }
    });

    test('an unknown key resolves to null so the row can be dropped', () {
      expect(FitNotificationType.fromKey('comment'), isNull);
      expect(FitNotificationType.fromKey(null), isNull);
    });
  });

  group('notification ids', () {
    test('are the same for the same relationship, so following twice is one '
        'notification', () {
      expect(NotificationIds.follow('u2'), NotificationIds.follow('u2'));
      expect(NotificationIds.like('p1', 'u2'), NotificationIds.like('p1', 'u2'));
    });

    test('separate different actors and different posts', () {
      expect(NotificationIds.follow('u2'), isNot(NotificationIds.follow('u3')));
      expect(
        NotificationIds.like('p1', 'u2'),
        isNot(NotificationIds.like('p2', 'u2')),
      );
    });
  });

  group('message', () {
    test('names what was liked', () {
      expect(like(postType: 'image').message, 'liked your photo');
      expect(like(postType: 'meal').message, 'liked your meal');
      expect(like(postType: 'run').message, 'liked your run');
      expect(like(postType: 'workout').message, 'liked your workout');
    });

    test('falls back to "post" for text and for types this build predates', () {
      expect(like(postType: 'text').message, 'liked your post');
      expect(like(postType: 'something-new').message, 'liked your post');
      expect(like().message, 'liked your post');
    });

    test('reads as a follow without a target', () {
      expect(follow.message, 'started following you');
    });
  });

  group('route', () {
    test('a like opens the post, a follow opens the profile', () {
      expect(like().route, '/post/p1');
      expect(follow.route, '/user/u3');
    });

    test('a like with no post id has nowhere to go', () {
      expect(like(postId: null).route, isNull);
      expect(like(postId: '').route, isNull);
    });
  });

  group('age label', () {
    final now = DateTime(2026, 8, 7, 12);
    String labelFor(Duration age) =>
        notificationAgeLabel(now.subtract(age), now);

    test('counts minutes, hours, days, then weeks', () {
      expect(labelFor(const Duration(minutes: 42)), '42m');
      expect(labelFor(const Duration(hours: 6)), '6h');
      expect(labelFor(const Duration(days: 3)), '3d');
      expect(labelFor(const Duration(days: 21)), '3w');
    });

    test('reads as "now" inside the first minute', () {
      expect(labelFor(const Duration(seconds: 30)), 'now');
    });

    test('a missing or future timestamp reads as "now" rather than a '
        'negative age', () {
      expect(notificationAgeLabel(null, now), 'now');
      expect(notificationAgeLabel(now.add(const Duration(hours: 1)), now), 'now');
    });
  });

  group('initials', () {
    test('take the first and last name', () {
      expect(notificationInitials('Neo Mokoena'), 'NM');
      expect(notificationInitials('  bear   mdlalose '), 'BM');
    });

    test('take one letter from a single name', () {
      expect(notificationInitials('Thandi'), 'T');
      expect(notificationInitials('T'), 'T');
    });

    test('are empty when there is no name at all, so the row shows the '
        'empty-profile glyph instead of invented letters', () {
      expect(notificationInitials('   '), '');
      expect(notificationInitials('FitSocial Member'), '');
    });
  });
}
