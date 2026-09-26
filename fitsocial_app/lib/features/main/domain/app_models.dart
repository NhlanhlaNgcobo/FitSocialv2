import 'package:flutter/material.dart';

import '../../../shared/reactions/fit_reaction.dart';

/// What a post is, as recorded on the document.
///
/// [run] and [meal] were added after launch. Posts written before that carry
/// `text` and have to be recognised from their contents instead — see
/// ExploreFilterX, which is the one place that knows both forms.
enum PostType {
  text,
  image,
  workout,
  run,
  meal,
}

/// Someone attached to a post from its composer.
///
/// Name and handle ride along on the post document rather than being resolved
/// per render: the "with @bear" line is drawn for every card in the feed, and
/// a profile read per tagged person would be a query per card. The uid is what
/// makes the chip navigable and is the only field that can't go stale.
class TaggedUser {
  const TaggedUser({
    required this.id,
    required this.displayName,
    required this.handle,
  });

  final String id;
  final String displayName;

  /// Normalized username, no '@' — the UI adds one.
  final String handle;

  Map<String, String> toMap() => {
        'id': id,
        'displayName': displayName,
        'handle': handle,
      };

  /// Null for an entry missing the uid, which is the one field the chip cannot
  /// do without — a tag that leads nowhere is worse than no tag.
  static TaggedUser? fromMap(Object? value) {
    if (value is! Map) return null;
    final id = (value['id'] ?? '').toString().trim();
    if (id.isEmpty) return null;
    return TaggedUser(
      id: id,
      displayName:
          PublicAuthorName.sanitize((value['displayName'] ?? '').toString()),
      handle: (value['handle'] ?? '').toString().trim(),
    );
  }

  static List<TaggedUser> listFrom(Object? value) {
    if (value is! List) return const [];
    return value.map(TaggedUser.fromMap).whereType<TaggedUser>().toList(
          growable: false,
        );
  }
}

class FeedPost {
  const FeedPost({
    required this.id,
    required this.authorId,
    required this.userName,
    required this.activity,
    required this.caption,
    required this.metricLabels,
    required this.timestamp,
    required this.likes,
    required this.comments,
    required this.backgroundColors,
    required this.likedBy,
    this.reactions = FitReactionSummary.empty,
    this.reactionsBy = const {},
    this.postType = PostType.text,
    this.imageUrl,
    this.workoutData,
    this.routePoints = const [],
    this.authorAvatarUrl,
    this.imageAspectRatio,
    this.taggedUsers = const [],
  });

  final String id;

  /// Uid of the author. Needed so the UI can tell whose post it is — for the
  /// delete action, which only the author may perform.
  final String authorId;
  final String userName;
  final String activity;
  final String caption;
  final List<String> metricLabels;
  final String timestamp;
  final int likes;
  final int comments;
  final List<Color> backgroundColors;

  /// Everyone who has reacted. Still called this because it is still the same
  /// field: the single Like button became the reaction control, the way it did
  /// on Facebook, and the people it named did not change.
  final List<String> likedBy;

  /// The breakdown — how many gave each reaction. [likes] remains the total,
  /// and the two agree because the summary is reconciled against it on read.
  final FitReactionSummary reactions;

  /// Which reaction each person gave. Missing for anyone whose like predates
  /// reactions; [reactionOf] resolves those through [likedBy] instead.
  final Map<String, FitReaction> reactionsBy;

  final PostType postType;
  final String? imageUrl;
  final Map<String, dynamic>? workoutData;

  /// Completed run route, for the map preview on run posts. Empty on every
  /// other post type.
  final List<RoutePoint> routePoints;

  /// Author's profile photo as it was when the post was created. Null for
  /// posts written before avatars were stored, and for authors without one.
  final String? authorAvatarUrl;

  /// width / height of the post image. Null on posts created before this was
  /// recorded — the feed falls back to square, Instagram's historical default.
  final double? imageAspectRatio;

  /// People the author attached to the post. Empty on everything written
  /// before tagging existed, and on any post nobody was tagged in.
  final List<TaggedUser> taggedUsers;

  /// What [userId] reacted with, or null if they haven't reacted.
  ///
  /// Falls back to the default reaction for someone who is named in [likedBy]
  /// but absent from [reactionsBy] — that is a like cast under the old single
  /// button, and the honest reading of it is 🧡. Without this, everyone who
  /// liked a post before today would find their own like had vanished from
  /// the bar while still counting towards the total.
  FitReaction? reactionOf(String? userId) {
    if (userId == null) return null;
    final given = reactionsBy[userId];
    if (given != null) return given;
    return likedBy.contains(userId) ? FitReaction.defaultReaction : null;
  }

  /// The same post with its author's name and photo replaced.
  ///
  /// Separate from [copyWith] because this one has to be able to write null:
  /// an author who has removed their profile photo should lose it from their
  /// old posts too, and `copyWith` reads a null argument as "leave it alone".
  FeedPost withAuthor({
    required String userName,
    required String? authorAvatarUrl,
  }) {
    return FeedPost(
      id: id,
      authorId: authorId,
      userName: userName,
      activity: activity,
      caption: caption,
      metricLabels: metricLabels,
      timestamp: timestamp,
      likes: likes,
      comments: comments,
      backgroundColors: backgroundColors,
      likedBy: likedBy,
      reactions: reactions,
      reactionsBy: reactionsBy,
      postType: postType,
      imageUrl: imageUrl,
      workoutData: workoutData,
      routePoints: routePoints,
      authorAvatarUrl: authorAvatarUrl,
      imageAspectRatio: imageAspectRatio,
      taggedUsers: taggedUsers,
    );
  }

  FeedPost copyWith({
    String? id,
    String? authorId,
    String? userName,
    String? activity,
    String? caption,
    List<String>? metricLabels,
    String? timestamp,
    int? likes,
    int? comments,
    List<Color>? backgroundColors,
    List<String>? likedBy,
    FitReactionSummary? reactions,
    Map<String, FitReaction>? reactionsBy,
    PostType? postType,
    String? imageUrl,
    Map<String, dynamic>? workoutData,
    List<RoutePoint>? routePoints,
    String? authorAvatarUrl,
    double? imageAspectRatio,
    List<TaggedUser>? taggedUsers,
  }) {
    return FeedPost(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      userName: userName ?? this.userName,
      activity: activity ?? this.activity,
      caption: caption ?? this.caption,
      metricLabels: metricLabels ?? this.metricLabels,
      timestamp: timestamp ?? this.timestamp,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      backgroundColors: backgroundColors ?? this.backgroundColors,
      likedBy: likedBy ?? this.likedBy,
      reactions: reactions ?? this.reactions,
      reactionsBy: reactionsBy ?? this.reactionsBy,
      postType: postType ?? this.postType,
      imageUrl: imageUrl ?? this.imageUrl,
      workoutData: workoutData ?? this.workoutData,
      routePoints: routePoints ?? this.routePoints,
      authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
      imageAspectRatio: imageAspectRatio ?? this.imageAspectRatio,
      taggedUsers: taggedUsers ?? this.taggedUsers,
    );
  }
}

/// Where the posts on the home feed came from.
enum FeedSource {
  /// The people the user follows, plus the user themselves. The feed proper.
  following,

  /// The community's best, standing in because the following feed had nothing
  /// to show. Labelled as such on screen: a new user should never be left
  /// thinking the people they follow have gone quiet when they simply haven't
  /// followed anyone yet.
  suggested,

  /// Both: everything from the people they follow, topped up with suggestions
  /// underneath because there was not yet enough to fill a screen.
  ///
  /// This exists to remove a cliff. Following nobody showed a full suggested
  /// feed; following one person replaced all of it with that person's single
  /// post. The feed got *worse* the moment somebody engaged with it, which is
  /// precisely backwards, and it read as a broken app rather than as a small
  /// follow list. Blending means the feed can only ever grow as you follow
  /// more people.
  blended,
}

/// The home feed: the posts, and an honest account of where they came from.
///
/// The source travels with the posts rather than being worked out in the UI,
/// because only the query knows whether it fell back — by the time a list of
/// posts reaches a widget, a following feed and a suggested one are
/// indistinguishable.
class HomeFeed {
  const HomeFeed({
    required this.posts,
    required this.source,
    this.followedIds = const {},
  });

  const HomeFeed.empty()
      : posts = const [],
        source = FeedSource.following,
        followedIds = const {};

  final List<FeedPost> posts;
  final FeedSource source;

  /// The ids of the posts in [posts] that came from the follow graph.
  ///
  /// Ids rather than a boundary index, and that is worth stating because the
  /// index is the obvious implementation and it is wrong. The feed removes
  /// posts in place when one is deleted; an index would keep pointing at the
  /// same position in a list that had shifted underneath it, and the first
  /// suggestion would quietly start rendering above the "more from FitSocial"
  /// line as if the user followed its author. Identity cannot drift.
  ///
  /// Only read for [FeedSource.blended]; empty for the other two, where every
  /// post has the same provenance.
  final Set<String> followedIds;

  bool get isEmpty => posts.isEmpty;

  /// The posts from people the user actually follows.
  List<FeedPost> get followedPosts => source == FeedSource.blended
      ? posts.where((post) => followedIds.contains(post.id)).toList()
      : posts;

  /// The suggestions sitting underneath them, empty unless blended.
  List<FeedPost> get suggestedPosts => source == FeedSource.blended
      ? posts.where((post) => !followedIds.contains(post.id)).toList()
      : const [];

  /// The same feed with its posts replaced — for the in-place edits the feed
  /// makes as the user likes, comments, or deletes, none of which change where
  /// a post came from.
  HomeFeed withPosts(List<FeedPost> posts) => HomeFeed(
        posts: posts,
        source: source,
        followedIds: followedIds,
      );
}

/// Guards the metric strip burned across the bottom of a post's photo.
///
/// That overlay covers part of the picture, so only an actual measurement
/// earns a slot there — a run's distance, a workout's duration, a meal's
/// macros. Anything without a number in it is a label, not a measurement, and
/// is dropped. That is what "Post / Community / Now" was: filler stamped over
/// every shared photo. Half-filled entries go the same way, so a meal logged
/// without macros no longer prints a bare " kcal" across the food.
///
/// Applied at the single point where posts are written, so it holds for every
/// kind of post regardless of which flow created it.
class PostMetricLabels {
  const PostMetricLabels._();

  static final RegExp _hasNumber = RegExp(r'\d');

  /// [labels] keeping only the entries that state a measurement.
  static List<String> measured(List<String> labels) {
    return labels
        .map((label) => label.trim())
        .where(_hasNumber.hasMatch)
        .toList(growable: false);
  }
}

/// Guards the name attached to publicly visible content.
///
/// Posts and comments are readable by every signed-in user, so an author name
/// must never be an email address or any other auth credential. This is the
/// single source of truth for both the write path (what gets stored) and the
/// read path (what reaches the UI) — records written before this was enforced
/// may still hold an email, so stored values are sanitised on the way out too.
class PublicAuthorName {
  const PublicAuthorName._();

  static const String fallback = 'FitSocial Member';

  static final RegExp _emailLike = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Returns [value] when it is safe to display, otherwise [fallback].
  static String sanitize(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return fallback;
    if (_emailLike.hasMatch(trimmed)) return fallback;
    return trimmed;
  }

  /// First safe, non-empty candidate, else [fallback]. Used to prefer
  /// displayName over handle without letting an email through either.
  static String firstSafe(List<String?> candidates) {
    for (final candidate in candidates) {
      final trimmed = (candidate ?? '').trim();
      if (trimmed.isEmpty) continue;
      if (_emailLike.hasMatch(trimmed)) continue;
      return trimmed;
    }
    return fallback;
  }
}

class Comment {
  const Comment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.createdAt,
    this.authorAvatarUrl,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime createdAt;

  /// Author's profile photo at the time of commenting, denormalised the same
  /// way [authorName] is. Null on comments written before it was recorded.
  final String? authorAvatarUrl;

  /// The same comment with its author's name and photo replaced — the
  /// counterpart to [FeedPost.withAuthor], and null-writing for the same
  /// reason.
  Comment withAuthor({
    required String authorName,
    required String? authorAvatarUrl,
  }) {
    return Comment(
      id: id,
      authorId: authorId,
      authorName: authorName,
      text: text,
      createdAt: createdAt,
      authorAvatarUrl: authorAvatarUrl,
    );
  }
}

class ActivitySaveResult {
  const ActivitySaveResult({
    required this.message,
    this.createdPost,
  });

  final String message;
  final FeedPost? createdPost;
}

class ExerciseEntry {
  factory ExerciseEntry.fromMap(Map<String, dynamic> map) => ExerciseEntry(
        name: (map['name'] as String?) ?? '',
        sets: (map['sets'] as num?)?.toInt() ?? 0,
        reps: (map['reps'] as num?)?.toInt() ?? 0,
      );
  const ExerciseEntry({
    required this.name,
    required this.sets,
    required this.reps,
  });

  final String name;
  final int sets;
  final int reps;

  /// Firestore can only store primitives, lists, and maps — never custom
  /// classes — so entries must be converted before being written.
  Map<String, dynamic> toMap() => {
        'name': name,
        'sets': sets,
        'reps': reps,
      };
}

class WorkoutLogDraft {
  const WorkoutLogDraft({
    required this.title,
    required this.durationMinutes,
    required this.calories,
    required this.exercises,
    required this.notes,
    required this.shareToFeed,
    this.backgroundImagePath,
  });

  final String title;

  /// How long the session lasted. Numeric rather than a "45 min" label so the
  /// Progress tab can add durations up; the label is derived where it is shown.
  final int durationMinutes;

  /// Energy burned in kcal, as entered. Zero when the user left it blank —
  /// the field is optional and no figure is invented for a workout.
  final int calories;

  final List<ExerciseEntry> exercises;
  final String notes;
  final bool shareToFeed;

  /// A photo to sit behind the workout card, as a *local* file path — it has
  /// not been uploaded yet. Null falls back to the generated gradient, which is
  /// what every workout looked like before this existed.
  final String? backgroundImagePath;

  Duration get duration => Duration(minutes: durationMinutes);

  /// "45 min", for the post's metric strip.
  String get durationLabel => '$durationMinutes min';

  /// "320 kcal", for the post's metric strip.
  String get caloriesLabel => '$calories kcal';
}

/// One GPS coordinate on a saved run route.
///
/// Deliberately free of any `google_maps_flutter` types: this is the shape that
/// crosses the domain and Firestore boundaries, and the map plugin's `LatLng`
/// is a presentation concern. The UI converts at the widget edge.
class RoutePoint {
  const RoutePoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  /// Firestore representation — a plain `{lat, lng}` map, so a route persists
  /// as `List<Map<String, double>>`.
  Map<String, double> toMap() => {'lat': latitude, 'lng': longitude};

  /// Returns null when [value] isn't a usable coordinate pair, so a single bad
  /// entry can be skipped instead of failing the whole document read.
  static RoutePoint? fromMap(Object? value) {
    if (value is! Map) return null;
    final lat = (value['lat'] as num?)?.toDouble();
    final lng = (value['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return RoutePoint(latitude: lat, longitude: lng);
  }

  static List<RoutePoint> listFromFirestore(Object? value) {
    if (value is! List) return const [];
    return value
        .map(RoutePoint.fromMap)
        .whereType<RoutePoint>()
        .toList(growable: false);
  }
}

class RunLogDraft {
  const RunLogDraft({
    required this.distanceKm,
    required this.elapsed,
    required this.averagePace,
    required this.shareToFeed,
    this.routePoints = const [],
    this.startedAt,
    this.backgroundImagePath,
  });

  final double distanceKm;
  final Duration elapsed;
  final String averagePace;
  final bool shareToFeed;

  /// GPS trace of the run. Empty for manually entered runs, which have no
  /// recorded route — consumers must treat an empty route as "no map".
  final List<RoutePoint> routePoints;

  /// When the run began, when known (GPS-tracked runs only).
  final DateTime? startedAt;

  /// A photo to sit behind the run card, as a *local* file path — it has not
  /// been uploaded yet. Null falls back to the themed gradient, which is what
  /// every run looked like before this existed. Same contract as
  /// [WorkoutLogDraft.backgroundImagePath].
  final String? backgroundImagePath;
}

/// Where a food item's macros came from.
///
/// Surfaced in the UI because the difference matters to the user: a
/// database-backed number is a real composition value scaled to the portion,
/// an estimated one is the vision model's guess and worth checking.
enum MacroSource {
  /// Matched the app's curated food-composition table.
  database,

  /// Matched USDA FoodData Central.
  usda,

  /// No match — the model's own estimate.
  estimate;

  static MacroSource fromName(String? value) {
    return MacroSource.values.firstWhere(
      (source) => source.name == value,
      orElse: () => MacroSource.estimate,
    );
  }

  bool get isFromDatabase => this != MacroSource.estimate;

  String get label => switch (this) {
        MacroSource.database => 'Database',
        MacroSource.usda => 'USDA',
        MacroSource.estimate => 'Estimated',
      };
}

/// Per-100 g composition of a food, as stored in the nutrition database.
class FoodComposition {
  const FoodComposition({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  static FoodComposition? fromMap(Object? value) {
    if (value is! Map) return null;
    double read(String key) => (value[key] as num?)?.toDouble() ?? 0;
    return FoodComposition(
      calories: read('calories'),
      protein: read('protein'),
      carbs: read('carbs'),
      fat: read('fat'),
    );
  }

  Map<String, double> toMap() => {
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
      };
}

/// One identified food on the plate, with the macros for its portion.
class MealFoodItem {
  const MealFoodItem({
    required this.name,
    required this.grams,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.matchedFood,
    this.foodId,
    this.quantity = '',
    this.source = MacroSource.estimate,
    this.per100g,
  });

  /// What the analyzer called this item, e.g. "grilled chicken breast".
  final String name;

  /// The nutrition-database entry it resolved to, when it resolved to one.
  final String? matchedFood;
  final String? foodId;

  /// Estimated edible weight. Null only when the analyzer gave no portion.
  final int? grams;

  /// Human-readable portion, e.g. "1 cup" or "2 slices".
  final String quantity;

  final MacroSource source;

  /// Composition the macros were computed from. Present for database-backed
  /// items, which is what lets a corrected portion be recalculated on device
  /// instead of re-running the analysis.
  final FoodComposition? per100g;

  final int calories;
  final int protein;
  final int carbs;
  final int fat;

  /// The same item at a different portion, macros rescaled.
  ///
  /// Without [per100g] there is nothing to scale from, so the macros are left
  /// as they are and only the weight changes — an estimate stays an estimate.
  MealFoodItem withGrams(int newGrams) {
    final composition = per100g;
    if (composition == null || newGrams <= 0) {
      return copyWith(grams: newGrams);
    }
    final factor = newGrams / 100;
    return copyWith(
      grams: newGrams,
      quantity: '${newGrams}g',
      calories: (composition.calories * factor).round(),
      protein: (composition.protein * factor).round(),
      carbs: (composition.carbs * factor).round(),
      fat: (composition.fat * factor).round(),
    );
  }

  MealFoodItem copyWith({
    String? name,
    String? matchedFood,
    String? foodId,
    int? grams,
    String? quantity,
    MacroSource? source,
    FoodComposition? per100g,
    int? calories,
    int? protein,
    int? carbs,
    int? fat,
  }) {
    return MealFoodItem(
      name: name ?? this.name,
      matchedFood: matchedFood ?? this.matchedFood,
      foodId: foodId ?? this.foodId,
      grams: grams ?? this.grams,
      quantity: quantity ?? this.quantity,
      source: source ?? this.source,
      per100g: per100g ?? this.per100g,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
    );
  }

  /// Reads one entry of the analyzeMeal response.
  ///
  /// The Cloud Function sends macros as strings (the whole payload is stringly
  /// typed for the existing form fields), so numbers are parsed leniently
  /// rather than cast — a malformed field costs that field, not the item.
  static MealFoodItem? fromMap(Object? value) {
    if (value is! Map) return null;
    final name = (value['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;

    int readInt(String key) {
      final raw = value[key];
      if (raw is num) return raw.round();
      return int.tryParse(raw?.toString().trim() ?? '') ??
          double.tryParse(raw?.toString().trim() ?? '')?.round() ??
          0;
    }

    final grams = readInt('grams');
    return MealFoodItem(
      name: name,
      matchedFood: (value['matchedFood'] as Object?)?.toString(),
      foodId: (value['foodId'] as Object?)?.toString(),
      grams: grams > 0 ? grams : null,
      quantity: (value['quantity'] ?? '').toString(),
      source: MacroSource.fromName((value['source'] ?? '').toString()),
      per100g: FoodComposition.fromMap(value['per100g']),
      calories: readInt('calories'),
      protein: readInt('protein'),
      carbs: readInt('carbs'),
      fat: readInt('fat'),
    );
  }

  static List<MealFoodItem> listFrom(Object? value) {
    if (value is! List) return const [];
    return value
        .map(MealFoodItem.fromMap)
        .whereType<MealFoodItem>()
        .toList(growable: false);
  }

  /// Firestore representation, stored alongside the meal log.
  Map<String, Object?> toMap() => {
        'name': name,
        if (matchedFood != null) 'matchedFood': matchedFood,
        if (foodId != null) 'foodId': foodId,
        if (grams != null) 'grams': grams,
        if (quantity.isNotEmpty) 'quantity': quantity,
        'source': source.name,
        if (per100g != null) 'per100g': per100g!.toMap(),
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
      };
}

/// One nutrition-database entry returned by a food search.
class FoodSearchResult {
  const FoodSearchResult({
    required this.id,
    required this.name,
    required this.per100g,
    this.category = '',
    this.unitGrams,
    this.unitName,
    this.defaultPortionGrams = 150,
  });

  final String id;
  final String name;
  final String category;
  final FoodComposition per100g;

  /// Weight of one countable unit (a slice, an egg, a scoop), when the food
  /// has one. Null for foods only measured by weight or volume.
  final int? unitGrams;
  final String? unitName;

  /// A sensible starting portion when the user hasn't said how much.
  final int defaultPortionGrams;

  static FoodSearchResult? fromMap(Object? value) {
    if (value is! Map) return null;
    final id = (value['id'] ?? '').toString();
    final name = (value['name'] ?? '').toString();
    final per100g = FoodComposition.fromMap(value['per100g']);
    if (id.isEmpty || name.isEmpty || per100g == null) return null;

    return FoodSearchResult(
      id: id,
      name: name,
      category: (value['category'] ?? '').toString(),
      per100g: per100g,
      unitGrams: (value['unitGrams'] as num?)?.round(),
      unitName: (value['unitName'] as Object?)?.toString(),
      defaultPortionGrams:
          (value['defaultPortionGrams'] as num?)?.round() ?? 150,
    );
  }

  /// This food as a meal item at [grams], macros scaled from its composition.
  MealFoodItem toItem(int grams) {
    final portion = grams > 0 ? grams : defaultPortionGrams;
    final factor = portion / 100;
    return MealFoodItem(
      name: name,
      matchedFood: name,
      foodId: id,
      grams: portion,
      quantity: '${portion}g',
      source: MacroSource.database,
      per100g: per100g,
      calories: (per100g.calories * factor).round(),
      protein: (per100g.protein * factor).round(),
      carbs: (per100g.carbs * factor).round(),
      fat: (per100g.fat * factor).round(),
    );
  }
}

/// Summed macros across a list of items.
class MacroTotals {
  const MacroTotals({
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
  });

  final int calories;
  final int protein;
  final int carbs;
  final int fat;

  static MacroTotals of(Iterable<MealFoodItem> items) {
    var calories = 0;
    var protein = 0;
    var carbs = 0;
    var fat = 0;
    for (final item in items) {
      calories += item.calories;
      protein += item.protein;
      carbs += item.carbs;
      fat += item.fat;
    }
    return MacroTotals(
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
    );
  }
}

class MealLogDraft {
  const MealLogDraft({
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.notes,
    required this.shareToFeed,
    this.imageUrl,
    this.items = const [],
  });

  final String name;
  final String calories;
  final String protein;
  final String carbs;
  final String fat;
  final String notes;
  final bool shareToFeed;
  final String? imageUrl;

  /// The itemised breakdown behind the totals, when the meal was analysed.
  /// Empty for a meal typed in by hand.
  final List<MealFoodItem> items;
}

class PostDraft {
  const PostDraft({
    required this.caption,
    this.activity = '',
    this.imageUrl,
    this.imageAspectRatio,
    this.taggedUsers = const [],
  });

  final String caption;

  /// The line the author wants under their name in the feed header — "5km
  /// Morning Run", "Leg day". Free text, optional; an empty value leaves the
  /// header as a single line rather than inventing a label.
  final String activity;

  final String? imageUrl;

  /// width / height of the cropped photo. Stored so the feed can render the
  /// image at the shape the user actually chose instead of forcing one.
  final double? imageAspectRatio;

  /// People the author picked in the composer's tag sheet. Separate from the
  /// mentions inside [caption]: a tag is a deliberate attachment, a mention is
  /// something written in a sentence, and the two are notified differently.
  final List<TaggedUser> taggedUsers;
}

class ProgressMetric {
  const ProgressMetric({
    required this.label,
    required this.value,
    required this.delta,
    required this.chartBars,
  });

  final String label;
  final String value;
  final String delta;
  final List<double> chartBars;
}

/// How much history the activity grid covers.
///
/// Every range is Monday-aligned. GitHub's own graph starts its rows on a
/// Sunday, but a training week is read against the Monday it started on — the
/// week view exists to show how much of *this* week is still to play for.
enum ActivityRange {
  /// The current Monday-to-Sunday week, including the days still to come.
  week,

  /// The last five calendar weeks, rendered like a wall calendar.
  month,

  /// The last 53 weeks, rendered as GitHub draws its contribution graph:
  /// weeks as columns, days of the week as rows.
  year,
}

extension ActivityRangeX on ActivityRange {
  String get label => switch (this) {
        ActivityRange.week => '7D',
        ActivityRange.month => '30D',
        ActivityRange.year => '1Y',
      };

  /// Wording for the grid header, e.g. "in the last 30 days".
  String get windowLabel => switch (this) {
        ActivityRange.week => 'this week',
        ActivityRange.month => 'in the last 30 days',
        ActivityRange.year => 'in the last year',
      };

  /// How many days back the window reaches before Monday alignment.
  ///
  /// The year uses 364 (52 whole weeks) rather than 365 so that, once the
  /// current partial week is added, the grid lands on GitHub's familiar 53
  /// columns instead of drifting to 54 on some days. The week range does not
  /// use this — it is defined by the Monday it starts on.
  int get lookbackDays => switch (this) {
        ActivityRange.week => 7,
        ActivityRange.month => 35,
        ActivityRange.year => 364,
      };
}

/// One calendar day's worth of logged training.
///
/// Only runs and workouts count towards the grid — meals and posts are
/// tracked elsewhere and would make an "did I train today" signal noisy.
class ActivityDay {
  const ActivityDay({
    required this.date,
    this.runs = 0,
    this.workouts = 0,
  });

  /// Local midnight for the day this bucket covers.
  final DateTime date;
  final int runs;
  final int workouts;

  int get total => runs + workouts;

  /// Whether the square is filled.
  ///
  /// Deliberately binary. GitHub shades by volume, but the question this grid
  /// answers is "did I train that day", and the two-state legend on the card
  /// promises exactly that — a ladder of oranges would say something the
  /// legend does not explain.
  bool get isActive => total > 0;
}

/// The full, gap-filled window the activity grid renders.
class ActivityCalendar {
  const ActivityCalendar({
    required this.range,
    required this.days,
    required this.today,
  });

  /// Builds the window for [range] and drops the sparse [logged] days into it.
  ///
  /// [logged] only has to carry the days that actually saw activity; every
  /// other cell is filled in empty so the grid always draws a full rectangle.
  factory ActivityCalendar.fromLoggedDays({
    required ActivityRange range,
    required List<ActivityDay> logged,
    DateTime? today,
  }) {
    final now = dateOnly(today ?? DateTime.now());
    final start = startOfWindow(range, now);
    final end = endOfWindow(range, now);

    // Days are re-created on the normalised date rather than stored as given:
    // everything downstream compares `date` by equality — cell selection most
    // visibly — and a stray time component would never match. Entries landing
    // on the same day are merged rather than overwriting one another.
    final byDate = <DateTime, ActivityDay>{};
    for (final day in logged) {
      final key = dateOnly(day.date);
      final existing = byDate[key];
      byDate[key] = ActivityDay(
        date: key,
        runs: (existing?.runs ?? 0) + day.runs,
        workouts: (existing?.workouts ?? 0) + day.workouts,
      );
    }

    final days = <ActivityDay>[];
    for (var cursor = start;
        !cursor.isAfter(end);
        cursor = addDays(cursor, 1)) {
      days.add(byDate[cursor] ?? ActivityDay(date: cursor));
    }
    return ActivityCalendar(range: range, days: days, today: now);
  }

  final ActivityRange range;

  /// Every day in the window in chronological order, including the empty ones.
  ///
  /// For the week range this runs past [today] to the coming Sunday, so some
  /// entries are days that have not happened yet — see [isFuture].
  final List<ActivityDay> days;

  /// Local midnight today, against which [isFuture] is judged.
  final DateTime today;

  /// Whether [day] is still to come, and so is empty because it has not
  /// happened rather than because nothing was logged.
  bool isFuture(ActivityDay day) => day.date.isAfter(today);

  int get activeDays => days.where((day) => day.isActive).length;
  int get totalRuns => days.fold(0, (sum, day) => sum + day.runs);
  int get totalWorkouts => days.fold(0, (sum, day) => sum + day.workouts);

  /// Consecutive active days counting back from today.
  ///
  /// Today being empty does not break the streak — the day is still in
  /// progress — but any earlier gap does. Days still to come are ignored
  /// entirely, so the week view's empty Saturday does not read as a break.
  int get currentStreak {
    final elapsed = days.where((day) => !isFuture(day)).toList();
    var streak = 0;
    for (var i = elapsed.length - 1; i >= 0; i--) {
      if (elapsed[i].isActive) {
        streak++;
      } else if (i != elapsed.length - 1) {
        break;
      }
    }
    return streak;
  }

  /// The first day the window covers, always a Monday.
  static DateTime startOfWindow(ActivityRange range, DateTime today) {
    final now = dateOnly(today);
    // The week view is anchored to the Monday just gone rather than to a
    // rolling seven days, so the first square is always the start of the week.
    if (range == ActivityRange.week) return mondayOf(now);
    return mondayOf(addDays(now, -(range.lookbackDays - 1)));
  }

  /// The last day the window covers.
  ///
  /// The week runs on to its Sunday instead of stopping at today: the days
  /// still to come are the point of looking at the current week.
  static DateTime endOfWindow(ActivityRange range, DateTime today) {
    final now = dateOnly(today);
    if (range == ActivityRange.week) {
      return addDays(mondayOf(now), 6);
    }
    return now;
  }

  /// The Monday of the week [date] falls in.
  static DateTime mondayOf(DateTime date) {
    final day = dateOnly(date);
    // DateTime.weekday is 1 (Mon) to 7 (Sun), so subtracting weekday - 1
    // always lands on that week's Monday.
    return addDays(day, DateTime.monday - day.weekday);
  }

  /// [days] calendar days on from [date], at local midnight.
  ///
  /// Deliberately not `add(Duration(days: n))`: a Duration is elapsed time, so
  /// stepping across a daylight-saving change shifts the wall clock by an hour
  /// and lands on 23:00 the day before. The constructor normalises an
  /// out-of-range day instead, which keeps every step on local midnight.
  static DateTime addDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);

  /// Strips the time component so days compare and hash by calendar date.
  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

enum WorkoutType {
  strength,
  cardio,
  hiit,
  run,
  yoga,
}

enum MusicProviderService {
  spotify,
  appleMusic,
  youtubeMusic,

  /// Whatever music app is playing on this phone, read through Android's media
  /// session rather than through anyone's API.
  ///
  /// Unlike the three above this is not an account anybody connects — there is
  /// no sign-in, no token and no dashboard behind it. It is the value a
  /// snapshot carries when the player on the other end is an app we have no
  /// branding for, which is most of them. A recognised app still reports as
  /// itself, so Spotify playing reads as [spotify] and keeps its own colours.
  device;

  /// The services a user signs in to.
  ///
  /// [values] minus [device], and the list every account-shaped path should
  /// walk instead of `values`: the connect sheet, the saved-session restore,
  /// and anything that reaches for a token store. Asking `device` for an
  /// account throws, because there is no account to ask about.
  static const connectable = <MusicProviderService>[
    spotify,
    appleMusic,
    youtubeMusic,
  ];
}

enum ActivitySection {
  progress,
  music,
}

extension WorkoutTypeX on WorkoutType {
  String get label {
    switch (this) {
      case WorkoutType.strength:
        return 'Strength';
      case WorkoutType.cardio:
        return 'Cardio';
      case WorkoutType.hiit:
        return 'HIIT';
      case WorkoutType.run:
        return 'Run';
      case WorkoutType.yoga:
        return 'Yoga';
    }
  }
}

extension MusicProviderServiceX on MusicProviderService {
  String get label {
    switch (this) {
      case MusicProviderService.spotify:
        return 'Spotify';
      case MusicProviderService.appleMusic:
        return 'Apple Music';
      case MusicProviderService.youtubeMusic:
        return 'YouTube Music';
      case MusicProviderService.device:
        return 'Your music';
    }
  }
}

extension ActivitySectionX on ActivitySection {
  String get label {
    switch (this) {
      case ActivitySection.progress:
        return 'Progress';
      case ActivitySection.music:
        return 'Music';
    }
  }
}

class ProfileStat {
  const ProfileStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

/// A user surfaced by Explore search.
class UserSearchResult {
  const UserSearchResult({
    required this.id,
    required this.displayName,
    required this.handle,
    required this.initials,
    required this.postsCount,
    this.avatarUrl,
    this.bio = '',
    this.location = '',
    this.pronouns = '',
    this.links = '',
  });

  final String id;
  final String displayName;
  final String handle;
  final String initials;
  final int postsCount;
  final String? avatarUrl;

  /// The written part of the profile. Carried here as well as on the search
  /// result proper because the other-user profile screen is built from this
  /// record — anything missing from it cannot be shown there at all.
  final String bio;
  final String location;
  final String pronouns;
  final String links;
}

/// XP awarded per logged activity, and how much XP a level spans.
class AchievementXp {
  const AchievementXp._();

  static const int perWorkout = 100;
  static const int perMeal = 50;
  static const int perRun = 150;

  /// Every level costs the same amount of XP, so level N is reached at
  /// `(N - 1) * perLevel` total XP.
  static const int perLevel = 1000;
}

/// A single badge and how close the user is to earning it.
class BadgeProgress {
  const BadgeProgress({
    required this.id,
    required this.title,
    required this.description,
    required this.iconName,
    required this.currentProgress,
    required this.targetGoal,
  });

  final String id;
  final String title;
  final String description;

  /// Logical icon key, mapped to an [IconData] by the presentation layer so
  /// the domain stays free of widget concerns.
  final String iconName;

  final int currentProgress;
  final int targetGoal;

  bool get isUnlocked => currentProgress >= targetGoal;

  /// Clamped 0..1 so a partially-filled bar never overflows once the goal is
  /// exceeded (e.g. 14 workouts against a 10-workout badge).
  double get progressFraction {
    if (targetGoal <= 0) return 1;
    return (currentProgress / targetGoal).clamp(0.0, 1.0);
  }
}

class AchievementsData {
  const AchievementsData({
    required this.currentXp,
    required this.nextLevelXp,
    required this.level,
    required this.currentStreak,
    required this.badges,
    this.totalWorkouts = 0,
    this.totalMeals = 0,
    this.totalRuns = 0,
    this.longestRunKm = 0,
  });

  /// Lifetime XP earned across every logged activity.
  final int currentXp;

  /// Total lifetime XP needed to reach the next level.
  final int nextLevelXp;

  final int level;
  final int currentStreak;
  final List<BadgeProgress> badges;

  /// Lifetime counts of each activity kind. These are the same counters the
  /// badges measure against, surfaced directly so the dashboard can show a
  /// total rather than only a fraction of the next goal.
  final int totalWorkouts;
  final int totalMeals;
  final int totalRuns;

  /// Distance of the single longest run on record, in km.
  ///
  /// Deliberately the longest rather than the cumulative total: only the max is
  /// stored per user, so a lifetime total would read as zero for everyone who
  /// ran before it was tracked.
  final double longestRunKm;

  /// Whole weeks inside the current day streak — 0 until the first full week.
  int get streakWeeks => currentStreak ~/ 7;

  /// Every logged activity, whatever kind.
  int get totalActivities => totalWorkouts + totalMeals + totalRuns;

  /// XP banked since this level began — what the progress bar fills with.
  int get xpIntoCurrentLevel =>
      currentXp - (level - 1) * AchievementXp.perLevel;

  /// XP still owed before the next level unlocks.
  int get xpRemaining => (nextLevelXp - currentXp).clamp(0, nextLevelXp);

  double get levelProgress {
    if (AchievementXp.perLevel <= 0) return 0;
    return (xpIntoCurrentLevel / AchievementXp.perLevel).clamp(0.0, 1.0);
  }

  List<BadgeProgress> get unlockedBadges =>
      badges.where((badge) => badge.isUnlocked).toList();

  List<BadgeProgress> get lockedBadges =>
      badges.where((badge) => !badge.isUnlocked).toList();
}
