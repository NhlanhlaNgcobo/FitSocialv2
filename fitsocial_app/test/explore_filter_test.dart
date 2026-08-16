import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/explore_models.dart';
import 'package:flutter_test/flutter_test.dart';

FeedPost _post({
  String activity = 'Something',
  PostType postType = PostType.text,
  List<String> metricLabels = const [],
  String? imageUrl,
  Map<String, dynamic>? workoutData,
  List<RoutePoint> routePoints = const [],
}) {
  return FeedPost(
    id: 'p1',
    authorId: 'u1',
    userName: 'Neo M.',
    activity: activity,
    caption: '',
    metricLabels: metricLabels,
    timestamp: 'now',
    likes: 0,
    comments: 0,
    backgroundColors: const [],
    likedBy: const [],
    postType: postType,
    imageUrl: imageUrl,
    workoutData: workoutData,
    routePoints: routePoints,
  );
}

const _route = [
  RoutePoint(latitude: -26.2, longitude: 28.0),
  RoutePoint(latitude: -26.3, longitude: 28.1),
];

void main() {
  group('workouts', () {
    test('a workout is matched by its type, not by its title', () {
      // The title is the user's own wording and almost never says "workout".
      final post = _post(activity: 'Leg Day', postType: PostType.workout);

      expect(ExploreFilter.workouts.matches(post), isTrue);
    });

    test('a workout logged before the type existed is caught by its data', () {
      final post = _post(
        activity: 'Push Session',
        workoutData: const {'title': 'Push Session'},
      );

      expect(ExploreFilter.workouts.matches(post), isTrue);
    });

    test('a workout is not also a meal, despite writing a kcal metric', () {
      // The workout flow stamps '0 kcal' on every post it creates, which used
      // to make every shared workout show up under Meals.
      final post = _post(
        activity: 'Leg Day',
        postType: PostType.workout,
        metricLabels: const ['45 min', '0 kcal', '6 moves'],
      );

      expect(ExploreFilter.meals.matches(post), isFalse);
    });
  });

  group('meals', () {
    test('a meal is matched by its type, not by its name', () {
      final post = _post(activity: 'Chicken salad', postType: PostType.meal);

      expect(ExploreFilter.meals.matches(post), isTrue);
    });

    test('a meal logged before the type existed is caught by its macros', () {
      final post = _post(
        activity: 'Chicken salad',
        metricLabels: const ['420 kcal', '38g protein', '12g fat'],
      );

      expect(ExploreFilter.meals.matches(post), isTrue);
    });

    test('a plain photo post is not a meal', () {
      final post = _post(postType: PostType.image, imageUrl: 'https://x/y.jpg');

      expect(ExploreFilter.meals.matches(post), isFalse);
    });
  });

  group('runs', () {
    test('a tracked run is matched by its route', () {
      final post = _post(activity: 'Run', routePoints: _route);

      expect(ExploreFilter.runs.matches(post), isTrue);
    });

    test('a manually entered run has no route and is matched by type', () {
      final post = _post(activity: 'Run', postType: PostType.run);

      expect(ExploreFilter.runs.matches(post), isTrue);
    });

    test('a run is not a meal', () {
      final post = _post(
        activity: 'Run',
        postType: PostType.run,
        metricLabels: const ['5.00 km', '320 kcal'],
      );

      expect(ExploreFilter.meals.matches(post), isFalse);
    });
  });

  test('photos catch anything carrying an image, meals included', () {
    final meal = _post(postType: PostType.meal, imageUrl: 'https://x/y.jpg');

    expect(ExploreFilter.photos.matches(meal), isTrue);
    expect(ExploreFilter.meals.matches(meal), isTrue);
  });

  group('isPhotoPost — what the profile photo grid keeps', () {
    test('a workout backdrop stays with its workout', () {
      // Picking a background for a workout card is not sharing a photo. The
      // grid used to show it as a bare tile, so the same session appeared
      // twice: once as a picture and once under Workouts.
      final post = _post(
        activity: 'Leg Day',
        postType: PostType.workout,
        imageUrl: 'https://x/backdrop.jpg',
        workoutData: const {'title': 'Leg Day'},
      );

      expect(ExploreFilterX.isPhotoPost(post), isFalse);
      expect(ExploreFilter.workouts.matches(post), isTrue);
    });

    test('a run carrying a picture stays with its run', () {
      final post = _post(
        activity: 'Run',
        postType: PostType.run,
        imageUrl: 'https://x/backdrop.jpg',
      );

      expect(ExploreFilterX.isPhotoPost(post), isFalse);
      expect(ExploreFilter.runs.matches(post), isTrue);
    });

    test('a photographed meal stays with its meal', () {
      final post = _post(postType: PostType.meal, imageUrl: 'https://x/y.jpg');

      expect(ExploreFilterX.isPhotoPost(post), isFalse);
    });

    test('a plain photo post is kept', () {
      final post = _post(postType: PostType.image, imageUrl: 'https://x/y.jpg');

      expect(ExploreFilterX.isPhotoPost(post), isTrue);
    });

    test('a post with no picture is not a photo post', () {
      expect(ExploreFilterX.isPhotoPost(_post()), isFalse);
      expect(ExploreFilterX.isPhotoPost(_post(imageUrl: '')), isFalse);
    });

    test('the Photos chip still catches what the grid drops', () {
      // Explore's chip means "show me pictures", wherever they are. Only the
      // tabbed profile grid needs the stricter rule.
      final post = _post(
        postType: PostType.workout,
        imageUrl: 'https://x/backdrop.jpg',
      );

      expect(ExploreFilter.photos.matches(post), isTrue);
      expect(ExploreFilterX.isPhotoPost(post), isFalse);
    });
  });

  test('applyExploreFilter keeps order and leaves "all" untouched', () {
    final posts = [
      _post(postType: PostType.workout),
      _post(postType: PostType.meal),
      _post(postType: PostType.run),
    ];

    expect(applyExploreFilter(posts, ExploreFilter.all), same(posts));
    expect(applyExploreFilter(posts, ExploreFilter.workouts), hasLength(1));
    expect(applyExploreFilter(posts, ExploreFilter.meals), hasLength(1));
    expect(applyExploreFilter(posts, ExploreFilter.runs), hasLength(1));
  });
}
