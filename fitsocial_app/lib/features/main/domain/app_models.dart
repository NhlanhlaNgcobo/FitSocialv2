import 'package:flutter/material.dart';
import '../../../shared/widgets/brand_image_tile.dart';

class StoryItem {
  const StoryItem({
    required this.name,
    required this.initials,
    this.visualTile,
    this.isOwnStory = false,
  });

  final String name;
  final String initials;
  final AppVisualTile? visualTile;
  final bool isOwnStory;
}

enum PostType {
  text,
  image,
  workout,
}

class FeedPost {
  const FeedPost({
    required this.id,
    required this.userName,
    required this.activity,
    required this.caption,
    required this.metricLabels,
    required this.timestamp,
    required this.likes,
    required this.comments,
    required this.backgroundColors,
    required this.likedBy,
    this.visualTile,
    this.postType = PostType.text,
    this.imageUrl,
    this.workoutData,
    this.routePoints = const [],
    this.authorAvatarUrl,
    this.imageAspectRatio,
  });

  final String id;
  final String userName;
  final String activity;
  final String caption;
  final List<String> metricLabels;
  final String timestamp;
  final int likes;
  final int comments;
  final List<Color> backgroundColors;
  final List<String> likedBy;
  final AppVisualTile? visualTile;
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

  FeedPost copyWith({
    String? id,
    String? userName,
    String? activity,
    String? caption,
    List<String>? metricLabels,
    String? timestamp,
    int? likes,
    int? comments,
    List<Color>? backgroundColors,
    List<String>? likedBy,
    AppVisualTile? visualTile,
    PostType? postType,
    String? imageUrl,
    Map<String, dynamic>? workoutData,
    List<RoutePoint>? routePoints,
    String? authorAvatarUrl,
    double? imageAspectRatio,
  }) {
    return FeedPost(
      id: id ?? this.id,
      userName: userName ?? this.userName,
      activity: activity ?? this.activity,
      caption: caption ?? this.caption,
      metricLabels: metricLabels ?? this.metricLabels,
      timestamp: timestamp ?? this.timestamp,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      backgroundColors: backgroundColors ?? this.backgroundColors,
      likedBy: likedBy ?? this.likedBy,
      visualTile: visualTile ?? this.visualTile,
      postType: postType ?? this.postType,
      imageUrl: imageUrl ?? this.imageUrl,
      workoutData: workoutData ?? this.workoutData,
      routePoints: routePoints ?? this.routePoints,
      authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
      imageAspectRatio: imageAspectRatio ?? this.imageAspectRatio,
    );
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
  });

  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime createdAt;
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
    required this.duration,
    required this.calories,
    required this.exercises,
    required this.notes,
    required this.shareToFeed,
  });

  final String title;
  final String duration;
  final String calories;
  final List<ExerciseEntry> exercises;
  final String notes;
  final bool shareToFeed;
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
  });

  final String name;
  final String calories;
  final String protein;
  final String carbs;
  final String fat;
  final String notes;
  final bool shareToFeed;
  final String? imageUrl;
}

class PostDraft {
  const PostDraft({
    required this.caption,
    this.imageUrl,
    this.imageAspectRatio,
  });

  final String caption;
  final String? imageUrl;

  /// width / height of the cropped photo. Stored so the feed can render the
  /// image at the shape the user actually chose instead of forcing one.
  final double? imageAspectRatio;
}

class SummaryMetric {
  const SummaryMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
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
}

enum PodcastCategory {
  mindset,
  discipline,
  recovery,
  business,
}

enum ActivitySection {
  progress,
  music,
  podcasts,
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
    }
  }
}

extension PodcastCategoryX on PodcastCategory {
  String get label {
    switch (this) {
      case PodcastCategory.mindset:
        return 'Mindset';
      case PodcastCategory.discipline:
        return 'Discipline';
      case PodcastCategory.recovery:
        return 'Recovery';
      case PodcastCategory.business:
        return 'Business';
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
      case ActivitySection.podcasts:
        return 'Podcasts';
    }
  }
}

class WorkoutPlaylist {
  const WorkoutPlaylist({
    required this.title,
    required this.subtitle,
    required this.provider,
    required this.workoutType,
    required this.durationLabel,
    required this.trackCount,
    required this.backgroundColors,
    this.visualTile,
  });

  final String title;
  final String subtitle;
  final MusicProviderService provider;
  final WorkoutType workoutType;
  final String durationLabel;
  final int trackCount;
  final List<Color> backgroundColors;
  final AppVisualTile? visualTile;
}

class UserCreatedPlaylist {
  const UserCreatedPlaylist({
    required this.name,
    required this.workoutType,
    required this.provider,
    required this.trackCount,
  });

  final String name;
  final WorkoutType workoutType;
  final MusicProviderService provider;
  final int trackCount;
}

class PodcastRecommendation {
  const PodcastRecommendation({
    required this.title,
    required this.host,
    required this.provider,
    required this.category,
    required this.episodeTitle,
    required this.durationLabel,
    required this.backgroundColors,
    this.visualTile,
  });

  final String title;
  final String host;
  final MusicProviderService provider;
  final PodcastCategory category;
  final String episodeTitle;
  final String durationLabel;
  final List<Color> backgroundColors;
  final AppVisualTile? visualTile;
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
  });

  final String id;
  final String displayName;
  final String handle;
  final String initials;
  final int postsCount;
  final String? avatarUrl;
  final String bio;
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
  });

  /// Lifetime XP earned across every logged activity.
  final int currentXp;

  /// Total lifetime XP needed to reach the next level.
  final int nextLevelXp;

  final int level;
  final int currentStreak;
  final List<BadgeProgress> badges;

  /// XP banked since this level began — what the progress bar fills with.
  int get xpIntoCurrentLevel => currentXp - (level - 1) * AchievementXp.perLevel;

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
