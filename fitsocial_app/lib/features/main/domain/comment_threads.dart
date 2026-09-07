import 'app_models.dart';

/// One top-level comment and the replies written under it.
///
/// The shape every comment list renders from: the query comes back flat, and
/// this is what turns it into the conversation people wrote.
class CommentThread {
  const CommentThread({required this.comment, this.replies = const []});

  final Comment comment;

  /// Oldest first, the order they were written in — a thread is read down the
  /// page, unlike the feed.
  final List<Comment> replies;

  /// The comment plus its replies, which is what the post's counter counts.
  int get length => 1 + replies.length;
}

/// Groups a post's comments into threads, oldest first.
///
/// Threads are one level deep. A reply written against another reply — which
/// nothing in the app can do today, but old or hand-written data might — is
/// hung off the top-level comment its chain leads back to rather than being
/// indented a second time.
///
/// A reply whose parent is gone becomes a thread of its own instead of
/// disappearing: the words were still said, and a post owner deleting one
/// comment must not silently take other people's with it.
List<CommentThread> threadComments(List<Comment> comments) {
  if (comments.isEmpty) return const [];

  final byId = <String, Comment>{for (final comment in comments) comment.id: comment};

  final roots = <Comment>[];
  final replies = <String, List<Comment>>{};

  for (final comment in comments) {
    final rootId = _rootId(comment, byId);
    if (rootId == comment.id) {
      roots.add(comment);
    } else {
      (replies[rootId] ??= <Comment>[]).add(comment);
    }
  }

  return [
    for (final root in roots)
      CommentThread(
        comment: root,
        replies: replies[root.id] ?? const <Comment>[],
      ),
  ];
}

/// The top of [comment]'s chain. Itself when it starts one, when its parent
/// has been deleted, or when the chain loops — the hop limit is what keeps a
/// cycle in the data from hanging the list.
String _rootId(Comment comment, Map<String, Comment> byId) {
  var current = comment;
  for (var hops = 0; hops < 8; hops++) {
    final parentId = current.parentId;
    if (parentId == null || parentId.isEmpty) return current.id;
    final parent = byId[parentId];
    if (parent == null || parent.id == current.id) return current.id;
    current = parent;
  }
  return current.id;
}

/// Who a new comment has to tell, and whether their row reads as a reply.
///
/// Three rules, in order:
///
///  * nobody is told about their own words;
///  * a mention already reached them, and a second row for the same comment is
///    the app repeating itself;
///  * being replied to outranks owning the post — someone answering your
///    comment on your own post is one event, and "replied to your comment" is
///    the truer half of it.
Map<String, bool> commentNotificationAudience({
  required String actorId,
  required String postAuthorId,
  required String parentAuthorId,
  required Set<String> mentioned,
}) {
  bool tellable(String userId) =>
      userId.isNotEmpty && userId != actorId && !mentioned.contains(userId);

  final audience = <String, bool>{};
  if (tellable(parentAuthorId)) audience[parentAuthorId] = true;
  if (tellable(postAuthorId) && !audience.containsKey(postAuthorId)) {
    audience[postAuthorId] = false;
  }
  return audience;
}
