import 'dart:math';

import 'app_models.dart';

/// Ranks the Explore grid.
///
/// The previous ordering was `likesCount desc` across all time, which meant the
/// grid never changed: whichever posts collected likes first held the page
/// permanently, and there was no reason to open the tab twice. This scores
/// engagement against age instead, so a post that did well today outranks one
/// that did slightly better a month ago.
///
/// The shape is the usual gravity formula. Two choices are deliberate:
///
///  - Comments count double. Writing a reply costs more than tapping a heart,
///    so it is the stronger signal that a post was worth stopping on.
///  - The numerator floors at 1, so a brand-new post with no engagement still
///    outranks an ancient one holding a couple of likes. In a young community
///    that is what stops the grid freezing all over again.
class TrendingScore {
  const TrendingScore._();

  /// How many likes one comment is worth.
  static const double commentWeight = 2;

  /// How steeply a post decays. Higher drops old posts faster; 1.5 gives a
  /// well-received post roughly a day near the top before fresher work passes
  /// it.
  static const double gravity = 1.5;

  /// Added to the age before decay is applied, so a post minutes old isn't
  /// dividing by nearly zero and taking the whole grid on the strength of a
  /// single like.
  static const double _ageOffsetHours = 2;

  /// What an undated post is aged at — see [of].
  static const double _undatedAgeHours = 24 * 7;

  static double of({
    required int likes,
    required int comments,
    required DateTime? createdAt,
    required DateTime now,
  }) {
    final engagement = 1 + likes + comments * commentWeight;

    // A post with no server timestamp can't be aged. Scoring it as a week old
    // keeps it eligible without letting it displace anything current. A clock
    // skew that puts createdAt in the future is clamped to zero rather than
    // producing a negative age, which would invert the decay.
    final ageHours = createdAt == null
        ? _undatedAgeHours
        : max(0.0, now.difference(createdAt).inMinutes / 60);

    return engagement / pow(ageHours + _ageOffsetHours, gravity);
  }
}

/// The category chips above the Explore grid.
enum ExploreFilter { all, runs, workouts, meals, photos }

extension ExploreFilterX on ExploreFilter {
  String get label => switch (this) {
        ExploreFilter.all => 'All',
        ExploreFilter.runs => 'Runs',
        ExploreFilter.workouts => 'Workouts',
        ExploreFilter.meals => 'Meals',
        ExploreFilter.photos => 'Photos',
      };

  /// Whether [post] belongs under this chip.
  ///
  /// Categories deliberately overlap: a photographed meal is both a meal and a
  /// photo, and someone tapping "Photos" means "show me pictures", not "show
  /// me pictures that aren't food".
  bool matches(FeedPost post) => switch (this) {
        ExploreFilter.all => true,
        ExploreFilter.runs => isRun(post),
        ExploreFilter.workouts => isWorkout(post),
        ExploreFilter.meals => isMeal(post),
        ExploreFilter.photos =>
          post.imageUrl != null && post.imageUrl!.isNotEmpty,
      };

  /// Runs now carry [PostType.run]. Older ones were written as
  /// [PostType.text], where the route was the tell — except for a manually
  /// entered run, which has no route and could only be recognised by its
  /// activity label. All three forms have to be caught.
  static bool isRun(FeedPost post) {
    if (post.postType == PostType.run) return true;
    if (post.routePoints.length >= 2) return true;
    return post.activity.trim().toLowerCase() == 'run';
  }

  static bool isWorkout(FeedPost post) {
    return post.postType == PostType.workout || post.workoutData != null;
  }

  /// Meals now carry [PostType.meal]. Older ones share [PostType.text] with
  /// plain posts, so the type says nothing and the kcal metric is the only
  /// tell left.
  ///
  /// That tell is not exclusive: the workout flow writes a '0 kcal' metric of
  /// its own, so every shared workout matched this until the kind checks below
  /// were added. A post that is already a workout or a run is never a meal.
  static bool isMeal(FeedPost post) {
    if (post.postType == PostType.meal) return true;
    if (isWorkout(post) || isRun(post)) return false;
    return post.metricLabels
        .any((label) => label.toLowerCase().contains('kcal'));
  }
}

/// [posts] filtered to [filter], preserving the ranked order.
List<FeedPost> applyExploreFilter(List<FeedPost> posts, ExploreFilter filter) {
  if (filter == ExploreFilter.all) return posts;
  return posts.where(filter.matches).toList(growable: false);
}
