import 'package:flutter_test/flutter_test.dart';
import 'package:fitsocial_app/features/main/data/firestore_mappers.dart';
import 'package:fitsocial_app/features/main/data/firestore_models.dart';

/// A post record whose only interesting field is when it was written.
FirestorePostRecord recordAged(Duration age, {String storedLabel = 'now'}) {
  return FirestorePostRecord(
    id: 'p1',
    authorId: 'u1',
    authorName: 'Neo M.',
    activity: '5km Morning Run',
    caption: 'Great way to start the day!',
    metricLabels: const [],
    likesCount: 0,
    commentsCount: 0,
    timestampLabel: storedLabel,
    themeKey: 'sunset',
    likedBy: const [],
    createdAt: age == Duration.zero ? null : DateTime.now().subtract(age),
  );
}

String labelFor(Duration age) => FirestoreMapper.toFeedPost(recordAged(age)).timestamp;

void main() {
  group('feed timestamp', () {
    test('reads as "just now" inside the first minute', () {
      expect(labelFor(const Duration(seconds: 30)), 'just now');
    });

    test('counts minutes, then hours, then days', () {
      expect(labelFor(const Duration(minutes: 5)), '5 minutes ago');
      expect(labelFor(const Duration(hours: 2)), '2 hours ago');
      expect(labelFor(const Duration(days: 3)), '3 days ago');
    });

    test('drops the plural for a single unit', () {
      expect(labelFor(const Duration(minutes: 1)), '1 minute ago');
      expect(labelFor(const Duration(hours: 1)), '1 hour ago');
      expect(labelFor(const Duration(days: 1)), '1 day ago');
    });

    test('rolls up into weeks, months and years', () {
      expect(labelFor(const Duration(days: 10)), '1 week ago');
      expect(labelFor(const Duration(days: 45)), '1 month ago');
      expect(labelFor(const Duration(days: 400)), '1 year ago');
    });

    // The old behaviour: the label was frozen at write time, so a week-old post
    // still claimed to be new. Anything with a createdAt must ignore it.
    test('ignores a stale stored label when the post has a createdAt', () {
      final record = FirestorePostRecord(
        id: 'p1',
        authorId: 'u1',
        authorName: 'Neo M.',
        activity: '',
        caption: '',
        metricLabels: const [],
        likesCount: 0,
        commentsCount: 0,
        timestampLabel: 'now',
        themeKey: 'sunset',
        likedBy: const [],
        createdAt: DateTime.now().subtract(const Duration(hours: 6)),
      );
      expect(FirestoreMapper.toFeedPost(record).timestamp, '6 hours ago');
    });

    test('falls back to the stored label when there is no createdAt', () {
      final record = recordAged(Duration.zero, storedLabel: 'yesterday');
      expect(FirestoreMapper.toFeedPost(record).timestamp, 'yesterday');
    });

    test('a future createdAt from clock skew reads as "just now"', () {
      expect(labelFor(const Duration(minutes: -10)), 'just now');
    });
  });
}
