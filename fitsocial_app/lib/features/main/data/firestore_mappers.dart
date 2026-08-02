import 'package:flutter/material.dart';

import '../domain/app_models.dart';
import 'firestore_models.dart';

class FirestoreMapper {
  const FirestoreMapper._();

  static StoryItem toStoryItem(FirestoreUserRecord user, {bool isOwnStory = false}) {
    final name = PublicAuthorName.sanitize(user.displayName);
    return StoryItem(
      name: isOwnStory ? 'Your Story' : name.split(' ').first,
      initials: _initials(name),
      isOwnStory: isOwnStory,
    );
  }

  static FeedPost toFeedPost(FirestorePostRecord post) {
    return FeedPost(
      id: post.id,
      // Sanitised on read as well as write: posts stored before the email
      // fallback was removed still carry addresses in this field.
      userName: PublicAuthorName.sanitize(post.authorName),
      activity: post.activity,
      caption: post.caption,
      metricLabels: post.metricLabels,
      timestamp: post.timestampLabel,
      likes: post.likesCount,
      comments: post.commentsCount,
      backgroundColors: _themeColors(post.themeKey),
      likedBy: post.likedBy,
      postType: _parsePostType(post.postType),
      imageUrl: post.imageUrl,
      workoutData: post.workoutData,
      routePoints: post.routePoints,
      authorAvatarUrl: post.authorAvatarUrl,
      imageAspectRatio: post.imageAspectRatio,
    );
  }

  static PostType _parsePostType(String value) {
    switch (value) {
      case 'image':
        return PostType.image;
      case 'workout':
        return PostType.workout;
      case 'text':
      default:
        return PostType.text;
    }
  }

  static UserSearchResult toUserSearchResult(FirestoreUserRecord user) {
    final displayName = PublicAuthorName.sanitize(user.displayName);
    return UserSearchResult(
      id: user.id,
      displayName: displayName,
      handle: user.handle,
      initials: _initials(displayName),
      postsCount: user.postsCount,
      avatarUrl: user.avatarUrl,
      bio: user.bio,
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
      // Comments written before the email fallback was removed still hold
      // addresses; never let one reach the UI.
      authorName: PublicAuthorName.sanitize(record.authorName),
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
