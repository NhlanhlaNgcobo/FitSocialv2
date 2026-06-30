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
    );
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

class WorkoutLogDraft {
  const WorkoutLogDraft({
    required this.title,
    required this.duration,
    required this.calories,
    required this.exercises,
    required this.shareToFeed,
  });

  final String title;
  final String duration;
  final String calories;
  final List<String> exercises;
  final bool shareToFeed;
}

class RunLogDraft {
  const RunLogDraft({
    required this.distanceKm,
    required this.elapsed,
    required this.averagePace,
    required this.shareToFeed,
  });

  final double distanceKm;
  final Duration elapsed;
  final String averagePace;
  final bool shareToFeed;
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
  });

  final String caption;
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
