import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/explore_models.dart';

/// A post carrying only the fields the Explore ranking and filters read.
FeedPost _post({
  String id = 'p1',
  String activity = '',
  int likes = 0,
  int comments = 0,
  List<String> metricLabels = const [],
  List<RoutePoint> routePoints = const [],
  PostType postType = PostType.text,
  String? imageUrl,
  Map<String, dynamic>? workoutData,
}) {
  return FeedPost(
    id: id,
    authorId: 'a1',
    userName: 'Test User',
    activity: activity,
    caption: '',
    metricLabels: metricLabels,
    timestamp: 'now',
    likes: likes,
    comments: comments,
    backgroundColors: const [],
    likedBy: const [],
    postType: postType,
    imageUrl: imageUrl,
    workoutData: workoutData,
    routePoints: routePoints,
  );
}

void main() {
  final now = DateTime(2026, 8, 6, 12);

  double score({
    required int likes,
    int comments = 0,
    required Duration age,
  }) {
    return TrendingScore.of(
      likes: likes,
      comments: comments,
      createdAt: now.subtract(age),
      now: now,
    );
  }

  group('TrendingScore', () {
    test('a fresh post outranks an older one with the same engagement', () {
      final fresh = score(likes: 10, age: const Duration(hours: 1));
      final stale = score(likes: 10, age: const Duration(days: 7));
      expect(fresh, greaterThan(stale));
    });

    test('the all-time winner no longer holds the grid forever', () {
      // The exact case the old `likesCount desc` ordering got wrong: a post
      // with far more likes, but a month old, must yield to today's activity.
      final lastMonthsHit = score(likes: 500, age: const Duration(days: 30));
      final todaysPost = score(likes: 3, age: const Duration(hours: 4));
      expect(todaysPost, greaterThan(lastMonthsHit));
    });

    test('comments are worth double a like', () {
      final withComments = score(likes: 0, comments: 5, age: Duration.zero);
      final withLikes = score(likes: 10, comments: 0, age: Duration.zero);
      expect(withComments, closeTo(withLikes, 1e-9));
    });

    test('a brand-new post with no engagement still beats an old one', () {
      final brandNew = score(likes: 0, age: Duration.zero);
      final oldAndLiked = score(likes: 5, age: const Duration(days: 14));
      expect(brandNew, greaterThan(oldAndLiked));
    });

    test('a missing timestamp is aged rather than favoured', () {
      final undated = TrendingScore.of(
        likes: 100,
        comments: 0,
        createdAt: null,
        now: now,
      );
      // Scored as a week old: beaten by anything current...
      expect(undated, lessThan(score(likes: 1, age: const Duration(hours: 1))));
      // ...but not discarded outright.
      expect(undated, greaterThan(0));
    });

    test('a future timestamp does not invert the decay', () {
      // Clock skew between the server stamp and the device can put createdAt
      // ahead of now; that must not produce a negative age and an inflated
      // score.
      final skewed = TrendingScore.of(
        likes: 1,
        comments: 0,
        createdAt: now.add(const Duration(hours: 6)),
        now: now,
      );
      expect(skewed, closeTo(score(likes: 1, age: Duration.zero), 1e-9));
    });
  });

  group('ExploreFilter', () {
    test('all matches everything', () {
      expect(ExploreFilter.all.matches(_post()), isTrue);
    });

    test('runs match a GPS route', () {
      final tracked = _post(
        routePoints: const [
          RoutePoint(latitude: -29.85, longitude: 31.02),
          RoutePoint(latitude: -29.86, longitude: 31.03),
        ],
      );
      expect(ExploreFilter.runs.matches(tracked), isTrue);
    });

    test('runs match a manually entered run, which has no route', () {
      expect(ExploreFilter.runs.matches(_post(activity: 'Run')), isTrue);
    });

    test('a single GPS fix is not a route', () {
      final oneFix = _post(
        routePoints: const [RoutePoint(latitude: -29.85, longitude: 31.02)],
      );
      expect(ExploreFilter.runs.matches(oneFix), isFalse);
    });

    test('workouts match on type or payload', () {
      expect(
        ExploreFilter.workouts.matches(_post(postType: PostType.workout)),
        isTrue,
      );
      expect(
        ExploreFilter.workouts.matches(_post(workoutData: const {'a': 1})),
        isTrue,
      );
      expect(ExploreFilter.workouts.matches(_post()), isFalse);
    });

    test('meals are identified by their kcal metric', () {
      final meal = _post(metricLabels: const ['420 kcal', '30g protein']);
      expect(ExploreFilter.meals.matches(meal), isTrue);
      expect(ExploreFilter.meals.matches(_post()), isFalse);
    });

    test('a photographed meal is both a meal and a photo', () {
      final meal = _post(
        metricLabels: const ['420 kcal'],
        imageUrl: 'https://example.test/plate.jpg',
      );
      expect(ExploreFilter.meals.matches(meal), isTrue);
      expect(ExploreFilter.photos.matches(meal), isTrue);
    });

    test('an empty image url is not a photo', () {
      expect(ExploreFilter.photos.matches(_post(imageUrl: '')), isFalse);
    });
  });

  group('applyExploreFilter', () {
    test('preserves the ranked order of what survives', () {
      final posts = [
        _post(id: 'a', activity: 'Run'),
        _post(id: 'b', postType: PostType.workout),
        _post(id: 'c', activity: 'Run'),
      ];
      final runs = applyExploreFilter(posts, ExploreFilter.runs);
      expect(runs.map((post) => post.id), ['a', 'c']);
    });

    test('all returns the same list untouched', () {
      final posts = [_post(id: 'a'), _post(id: 'b')];
      expect(applyExploreFilter(posts, ExploreFilter.all), same(posts));
    });
  });
}
