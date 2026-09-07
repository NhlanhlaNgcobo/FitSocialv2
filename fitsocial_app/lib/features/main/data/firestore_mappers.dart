import 'package:flutter/material.dart';

import '../../../shared/identity/profile_identity.dart';
import '../../../shared/reactions/fit_reaction.dart';
import '../domain/app_models.dart';
import 'author_identity_cache.dart';
import 'firestore_models.dart';

class FirestoreMapper {
  const FirestoreMapper._();

  /// [post] with the author's current name and photo laid over the copy frozen
  /// onto the document when it was written.
  ///
  /// A null [identity] is the author we could not resolve, and leaves the post
  /// exactly as stored — see [AuthorIdentityCache].
  static FeedPost withLiveAuthor(FeedPost post, AuthorIdentity? identity) {
    if (identity == null) return post;
    return post.withAuthor(
      userName: _liveName(identity.displayName, post.userName),
      authorAvatarUrl: _liveAvatar(identity.avatarUrl),
    );
  }

  /// [comment] with the author's current name and photo, on the same terms as
  /// [withLiveAuthor].
  static Comment commentWithLiveAuthor(
    Comment comment,
    AuthorIdentity? identity,
  ) {
    if (identity == null) return comment;
    return comment.withAuthor(
      authorName: _liveName(identity.displayName, comment.authorName),
      authorAvatarUrl: _liveAvatar(identity.avatarUrl),
    );
  }

  /// The live name, or [stored] when the profile has nothing better to offer.
  ///
  /// A profile whose displayName is empty or an address would sanitise to the
  /// placeholder, and replacing a real stored name with "FitSocial Member"
  /// would be a downgrade — the whole point of the overlay is to be more
  /// current, never less informative.
  static String _liveName(String? live, String stored) {
    final safe = PublicAuthorName.firstSafe([live]);
    return safe == PublicAuthorName.fallback ? stored : safe;
  }

  /// The live avatar, with an empty string read as "no photo" rather than as a
  /// URL. Null clears the stored one, which is what a removed photo should do.
  static String? _liveAvatar(String? live) {
    final trimmed = (live ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static FeedPost toFeedPost(FirestorePostRecord post) {
    return FeedPost(
      id: post.id,
      authorId: post.authorId,
      // Sanitised on read as well as write: posts stored before the email
      // fallback was removed still carry addresses in this field.
      userName: PublicAuthorName.sanitize(post.authorName),
      activity: post.activity,
      caption: post.caption,
      metricLabels: _realMetrics(post.metricLabels),
      timestamp: _relativeTime(post.createdAt) ?? post.timestampLabel,
      likes: post.likesCount,
      comments: post.commentsCount,
      backgroundColors: _themeColors(post.themeKey),
      likedBy: post.likedBy,
      // Reconciled against likesCount, not read straight off the map: a post
      // carrying likes from before reactions has a total and no breakdown, and
      // those are read as the default reaction rather than as nothing.
      reactions: readReactionCountsAgainstTotal(
        post.reactionCounts,
        post.likesCount,
      ),
      reactionsBy: _parseReactionsBy(post.reactionsBy),
      postType: _parsePostType(post.postType),
      imageUrl: post.imageUrl,
      workoutData: post.workoutData,
      routePoints: post.routePoints,
      authorAvatarUrl: post.authorAvatarUrl,
      imageAspectRatio: post.imageAspectRatio,
      taggedUsers: post.taggedUsers,
    );
  }

  /// Placeholder metrics written by the old share flow, before plain photo
  /// posts stopped claiming to measure anything.
  static const _filler = ['Post', 'Community', 'Now'];

  /// Drops the filler triple so photos shared before the change stop carrying
  /// "Post / Community / Now" burned over the bottom of the image. Real
  /// metrics — a run's pace, a meal's macros — pass through untouched.
  static List<String> _realMetrics(List<String> labels) {
    if (labels.length != _filler.length) return labels;
    for (var i = 0; i < labels.length; i++) {
      if (labels[i] != _filler[i]) return labels;
    }
    return const [];
  }

  /// "2 hours ago" from the post's server timestamp.
  ///
  /// Returns null when there is nothing to compute from, so the caller can fall
  /// back to the stored label. A clock skew that puts [createdAt] in the future
  /// reads as "just now" rather than a negative duration.
  static String? _relativeTime(DateTime? createdAt) {
    if (createdAt == null) return null;

    final elapsed = DateTime.now().difference(createdAt);
    if (elapsed.isNegative || elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inHours < 1) return _plural(elapsed.inMinutes, 'minute');
    if (elapsed.inDays < 1) return _plural(elapsed.inHours, 'hour');
    if (elapsed.inDays < 7) return _plural(elapsed.inDays, 'day');
    if (elapsed.inDays < 30) return _plural(elapsed.inDays ~/ 7, 'week');
    if (elapsed.inDays < 365) return _plural(elapsed.inDays ~/ 30, 'month');
    return _plural(elapsed.inDays ~/ 365, 'year');
  }

  static String _plural(int count, String unit) =>
      '$count $unit${count == 1 ? '' : 's'} ago';

  /// uid -> reaction, dropping anyone whose stored key this build doesn't
  /// know. A reaction added in a later release then reads as "no reaction from
  /// that person" rather than as the wrong one; they still count towards the
  /// total, which comes off likesCount.
  static Map<String, FitReaction> _parseReactionsBy(Map<String, String> raw) {
    final parsed = <String, FitReaction>{};
    for (final entry in raw.entries) {
      final reaction = FitReaction.fromKey(entry.value);
      if (reaction != null) parsed[entry.key] = reaction;
    }
    return parsed;
  }

  static PostType _parsePostType(String value) {
    switch (value) {
      case 'image':
        return PostType.image;
      case 'workout':
        return PostType.workout;
      case 'run':
        return PostType.run;
      case 'meal':
        return PostType.meal;
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
      initials: avatarInitials(displayName),
      postsCount: user.postsCount,
      avatarUrl: user.avatarUrl,
      bio: user.bio,
      location: user.location,
      pronouns: user.pronouns,
      links: user.links,
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

  static Comment toComment(FirestoreCommentRecord record) {
    return Comment(
      id: record.id,
      authorId: record.authorId,
      // Comments written before the email fallback was removed still hold
      // addresses; never let one reach the UI.
      authorName: PublicAuthorName.sanitize(record.authorName),
      text: record.text,
      createdAt: record.createdAt ?? DateTime.now(),
      authorAvatarUrl: record.authorAvatarUrl,
      parentId: record.parentCommentId,
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
}
