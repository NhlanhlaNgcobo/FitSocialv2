import 'package:flutter/material.dart';

import '../domain/app_models.dart';
import 'firestore_models.dart';

class FirestoreMapper {
  const FirestoreMapper._();

  static StoryItem toStoryItem(FirestoreUserRecord user, {bool isOwnStory = false}) {
    return StoryItem(
      name: isOwnStory ? 'Your Story' : user.displayName.split(' ').first,
      initials: _initials(user.displayName),
      isOwnStory: isOwnStory,
    );
  }

  static FeedPost toFeedPost(FirestorePostRecord post) {
    return FeedPost(
      id: post.id,
      userName: post.authorName,
      activity: post.activity,
      caption: post.caption,
      metricLabels: post.metricLabels,
      timestamp: post.timestampLabel,
      likes: post.likesCount,
      comments: post.commentsCount,
      backgroundColors: _themeColors(post.themeKey),
      likedBy: post.likedBy,
    );
  }

  static ProfileStat toProfileStat({
    required String label,
    required int value,
  }) {
    return ProfileStat(
      label: label,
      value: value.toString(),
    );
  }

  static ProgressMetric toProgressMetric(FirestoreProgressRecord record) {
    return ProgressMetric(
      label: record.label,
      value: record.value,
      delta: record.delta,
      chartBars: record.chartBars,
    );
  }

  static SummaryMetric toSummaryMetric({
    required String label,
    required String value,
  }) {
    return SummaryMetric(label: label, value: value);
  }

  static Comment toComment(FirestoreCommentRecord record) {
    return Comment(
      id: record.id,
      authorId: record.authorId,
      authorName: record.authorName,
      text: record.text,
      createdAt: record.createdAt ?? DateTime.now(),
    );
  }

  static List<Color> _themeColors(String themeKey) {
    switch (themeKey) {
      case 'burn':
        return const [Color(0xFF422919), Color(0xFF0E0E0E)];
      case 'graphite':
        return const [Color(0xFF2A2A2A), Color(0xFF101010)];
      case 'sunset':
      default:
        return const [Color(0xFF7A4D2E), Color(0xFF121212)];
    }
  }

  static String _initials(String value) {
    final parts = value.trim().split(' ');
    if (parts.length < 2) {
      final first = parts.first;
      if (first.isEmpty) return 'FS';
      final end = first.length > 1 ? 2 : 1;
      return first.substring(0, end).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
