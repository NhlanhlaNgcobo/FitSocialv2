import 'package:flutter_test/flutter_test.dart';
import 'package:fitsocial_app/features/main/data/firestore_mappers.dart';
import 'package:fitsocial_app/features/main/data/firestore_models.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';

/// A stored post carrying [metricLabels] and nothing else worth asserting on.
FirestorePostRecord recordWithMetrics(List<String> metricLabels) {
  return FirestorePostRecord(
    id: 'p1',
    authorId: 'u1',
    authorName: 'Neo M.',
    activity: 'Status Update',
    caption: 'Shared a FitSocial update.',
    metricLabels: metricLabels,
    likesCount: 0,
    commentsCount: 0,
    timestampLabel: 'now',
    themeKey: 'sunset',
    likedBy: const [],
    postType: 'image',
    imageUrl: 'https://example.test/photo.jpg',
  );
}

void main() {
  // The metric strip is drawn over the bottom of a post's photo, so only real
  // measurements belong in it. Enforced on write for new posts, and again on
  // read so photos shared before the rule existed come back clean.
  group('write path — PostMetricLabels.measured', () {
    test('drops the filler a plain photo share used to carry', () {
      expect(
        PostMetricLabels.measured(const ['Post', 'Community', 'Now']),
        isEmpty,
      );
    });

    test('keeps a run\'s distance, time and pace', () {
      const run = ['5.20 km', '00:32:10', '6:10 /km'];
      expect(PostMetricLabels.measured(run), run);
    });

    test('keeps a meal\'s macros', () {
      const meal = ['450 kcal', '30g protein', '12g fat'];
      expect(PostMetricLabels.measured(meal), meal);
    });

    test('drops the units left behind by unfilled meal fields', () {
      expect(
        PostMetricLabels.measured(const [' kcal', 'g protein', 'g fat']),
        isEmpty,
      );
    });

    test('keeps the macros that were filled in and drops the rest', () {
      expect(
        PostMetricLabels.measured(const ['450 kcal', 'g protein', 'g fat']),
        ['450 kcal'],
      );
    });

    test('trims the labels it keeps', () {
      expect(PostMetricLabels.measured(const ['  8 moves  ']), ['8 moves']);
    });
  });

  group('read path — posts stored before the rule', () {
    test('a photo post no longer surfaces the filler strip', () {
      final post = FirestoreMapper.toFeedPost(
        recordWithMetrics(const ['Post', 'Community', 'Now']),
      );
      expect(post.metricLabels, isEmpty);
    });

    test('a workout post keeps the numbers it measured', () {
      const metrics = ['45 min', '320 kcal', '8 moves'];
      final post = FirestoreMapper.toFeedPost(recordWithMetrics(metrics));
      expect(post.metricLabels, metrics);
    });
  });
}
