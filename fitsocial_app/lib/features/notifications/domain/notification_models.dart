import '../../../shared/identity/profile_identity.dart';
import '../../../shared/reactions/fit_reaction.dart';

/// What caused a notification.
///
/// Only the kinds the app actually writes are listed. An unknown key read back
/// from Firestore resolves to null and the document is dropped, so a build that
/// predates a new kind shows a shorter list rather than a broken row.
enum FitNotificationType {
  follow,

  /// Someone reacted to a post.
  ///
  /// Still stored as `like`: this is the same event it always was, and the
  /// notifications written before there were seven reactions are still in
  /// people's inboxes. Renaming the key would orphan every one of them, so
  /// the wording changed and the key did not — see [FitNotification.message].
  like,

  /// Someone wrote `@you` in a post caption or a comment.
  mention,

  /// Someone attached you to a post from its composer.
  tag;

  /// Stored form. Explicit rather than [name] so renaming the enum can never
  /// silently orphan the documents already written.
  String get key {
    switch (this) {
      case FitNotificationType.follow:
        return 'follow';
      case FitNotificationType.like:
        return 'like';
      case FitNotificationType.mention:
        return 'mention';
      case FitNotificationType.tag:
        return 'tag';
    }
  }

  static FitNotificationType? fromKey(String? value) {
    switch (value) {
      case 'follow':
        return FitNotificationType.follow;
      case 'like':
        return FitNotificationType.like;
      case 'mention':
        return FitNotificationType.mention;
      case 'tag':
        return FitNotificationType.tag;
      default:
        return null;
    }
  }
}

/// Document ids for notifications.
///
/// Deterministic on purpose. The id encodes the relationship that caused the
/// notification, which gives two things for free: following the same person
/// twice can only ever produce one row, and undoing the action — an unfollow,
/// an unlike — can delete the notification without having to search for it.
abstract final class NotificationIds {
  static String follow(String actorId) => 'follow_$actorId';

  static String like(String postId, String actorId) =>
      'like_${postId}_$actorId';

  /// A mention is keyed by the thing it was written in, not by the post it
  /// hangs off: naming someone in a caption and again in a comment are two
  /// separate events, and collapsing them would silently drop the second.
  /// [sourceId] is the post id for a caption and the comment id for a comment.
  static String mention(String sourceId, String actorId) =>
      'mention_${sourceId}_$actorId';

  static String tag(String postId, String actorId) => 'tag_${postId}_$actorId';
}

/// One line in the notifications list.
class FitNotification {
  const FitNotification({
    required this.id,
    required this.type,
    required this.actorId,
    required this.actorName,
    required this.isRead,
    this.actorAvatarUrl,
    this.createdAt,
    this.postId,
    this.postImageUrl,
    this.postType,
    this.commentId,
    this.reaction,
  });

  final String id;
  final FitNotificationType type;

  /// Who did it. Name and photo are denormalised onto the notification the
  /// same way posts denormalise their author, so the list renders from the one
  /// query it already runs instead of a profile read per row.
  final String actorId;
  final String actorName;
  final String? actorAvatarUrl;

  /// Whether the recipient has opened the list since this arrived.
  final bool isRead;

  /// Server clock. Null only for the moment before a server timestamp
  /// resolves, which the recipient never sees — they are not the writer.
  final DateTime? createdAt;

  /// The post that was liked. Null on a follow.
  final String? postId;

  /// Thumbnail of the liked post, when it carried an image.
  final String? postImageUrl;

  /// The liked post's stored `postType`, which is what decides whether the row
  /// reads "liked your photo", "liked your run", and so on. Carried on
  /// mentions and tags too, for the same sentence-building reason.
  final String? postType;

  /// Set on a mention that was written in a comment rather than in the post's
  /// own caption. Null on every other kind, and on a caption mention — which
  /// is what tells the two apart in [message].
  final String? commentId;

  /// Which reaction was given. Null on every other kind, and on a [like]
  /// written before there were seven of them — those rows keep their original
  /// wording rather than being retconned into a reaction nobody chose.
  final FitReaction? reaction;

  /// The sentence that follows the actor's name.
  String get message {
    switch (type) {
      case FitNotificationType.follow:
        return 'started following you';
      case FitNotificationType.like:
        // The emoji carries the whole point of having seven, so it leads the
        // sentence. A row from before reactions has none and keeps the words
        // it was written with.
        final given = reaction;
        return given == null
            ? 'liked your $_likedNoun'
            : 'reacted ${given.emoji} to your $_likedNoun';
      case FitNotificationType.mention:
        return commentId == null
            ? 'mentioned you in a $_likedNoun'
            : 'mentioned you in a comment';
      case FitNotificationType.tag:
        return 'tagged you in a $_likedNoun';
    }
  }

  /// What the liked thing is called in that sentence. Unknown and missing
  /// types fall back to "post", which is true of everything in the feed.
  String get _likedNoun {
    switch (postType) {
      case 'image':
        return 'photo';
      case 'meal':
        return 'meal';
      case 'run':
        return 'run';
      case 'workout':
        return 'workout';
      default:
        return 'post';
    }
  }

  /// Where tapping the row goes: the profile for a follow, otherwise the post
  /// the action happened on. Null when one of the latter arrived without a
  /// post id to open.
  String? get route {
    switch (type) {
      case FitNotificationType.follow:
        return '/user/$actorId';
      case FitNotificationType.like:
      case FitNotificationType.mention:
      case FitNotificationType.tag:
        final id = postId;
        return (id == null || id.isEmpty) ? null : '/post/$id';
    }
  }
}

/// Monogram shown when an actor has no profile photo, empty when there is no
/// real name to build one from — see [avatarInitials].
String notificationInitials(String name) => avatarInitials(name);

/// Compact age for the end of a notification row — "now", "42m", "6h", "3d".
///
/// Deliberately terser than the feed's "2 hours ago": the row already carries
/// a name and a sentence, and a full phrase on the end of every one of them
/// turns the list into a wall of text. Weeks are the largest unit — past that
/// the exact age stops mattering.
String notificationAgeLabel(DateTime? createdAt, DateTime now) {
  if (createdAt == null) return 'now';

  final elapsed = now.difference(createdAt);
  // A clock skew that puts the notification in the future reads as "now"
  // rather than a negative age.
  if (elapsed.isNegative || elapsed.inMinutes < 1) return 'now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d';
  return '${elapsed.inDays ~/ 7}w';
}
