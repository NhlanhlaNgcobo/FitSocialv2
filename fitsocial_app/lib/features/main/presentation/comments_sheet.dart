import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/identity/profile_identity.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/comment_composer.dart';
import '../../../shared/widgets/keyboard_safe_bottom_bar.dart';
import '../../../shared/widgets/mention_text.dart';
import '../../../shared/widgets/profile_link.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';
import '../domain/comment_threads.dart';
import '../../../shared/widgets/liquid_glass.dart';

class CommentsSheet extends ConsumerStatefulWidget {
  const CommentsSheet({
    required this.postId,
    this.autofocus = false,
    super.key,
  });

  final String postId;

  /// Opens with the keyboard up, for "Add a comment…" on a card — somebody
  /// who tapped a box to type in should not then have to tap it again.
  final bool autofocus;

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  /// Which comment the box at the bottom is answering. Held here rather than
  /// in the composer because the Reply button that sets it is up in the list.
  CommentReplyTarget? _replyTo;

  /// Owned by the sheet so tapping Reply can put the cursor in the box — a
  /// banner saying "Replying to Bear" over a keyboard that never came up is
  /// half an action.
  final _composerFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      // After the first frame: focus asked for before the field is laid out
      // is dropped, and the keyboard never comes up.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _composerFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _composerFocus.dispose();
    super.dispose();
  }

  void _replyTapped(CommentReplyTarget target) {
    setState(() => _replyTo = target);
    _composerFocus.requestFocus();
  }

  void _clearReply() {
    if (_replyTo == null) return;
    setState(() => _replyTo = null);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final commentsAsync = ref.watch(commentsProvider(widget.postId));

    return LiquidGlass(
      // Over the screen it was opened from, so there is real content to bend.
      lens: true,
      // A sheet always has a page behind it, which makes it the
      // one surface guaranteed something worth bending.
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.stroke,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Text(
                    'Comments',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: palette.text,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(
                      Icons.close_rounded,
                      color: palette.muted,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),

            Container(
              height: 1,
              color: palette.stroke,
            ),

            // Comment list
            Flexible(
              child: commentsAsync.when(
                data: (comments) {
                  if (comments.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Text(
                          'No comments yet.\nBe the first to comment!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ),
                    );
                  }
                  // Grouped, so a reply sits under what it answers instead of
                  // at the bottom of a flat list minutes away from it.
                  final threads = threadComments(comments);
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    itemCount: threads.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (context, index) => CommentThreadTile(
                      thread: threads[index],
                      onReply: _replyTapped,
                    ),
                  );
                },
                loading: () => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: CircularProgressIndicator(
                      color: context.palette.brand,
                      strokeWidth: 2,
                    ),
                  ),
                ),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Text(
                      'Failed to load comments.',
                      style: TextStyle(color: palette.muted),
                    ),
                  ),
                ),
              ),
            ),

            // Input bar. The sheet floats over its own barrier, so nothing else
            // lifts the composer clear of the keyboard or the system nav bar —
            // it pads for whichever is taller itself.
            KeyboardSafeBottomBar(
              child: CommentComposer(
                postId: widget.postId,
                focusNode: _composerFocus,
                replyTo: _replyTo,
                onClearReply: _clearReply,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One comment and the conversation under it.
///
/// Public for the same reason [CommentTile] is: the post detail page lists
/// comments in exactly the form the sheet shows them, and a thread that nested
/// on one screen and not on the other would read as two different apps.
class CommentThreadTile extends StatefulWidget {
  const CommentThreadTile({
    required this.thread,
    required this.onReply,
    super.key,
  });

  /// How many replies a thread shows before it asks.
  ///
  /// Two is enough to see that a conversation happened; a fifteen-reply thread
  /// pushing every other comment off the screen is what this guards against.
  static const int collapsedReplies = 2;

  final CommentThread thread;

  /// Given the thread to join and the person being answered.
  final ValueChanged<CommentReplyTarget> onReply;

  @override
  State<CommentThreadTile> createState() => _CommentThreadTileState();
}

class _CommentThreadTileState extends State<CommentThreadTile> {
  bool _expanded = false;

  /// Indent for everything under the parent comment — its avatar's width plus
  /// the gap beside it, so replies line up with the words they answer.
  static const double _indent = 34 + AppSpacing.sm;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final replies = widget.thread.replies;
    final hidden = replies.length - CommentThreadTile.collapsedReplies;
    final shown = (_expanded || hidden <= 0)
        ? replies
        : replies.take(CommentThreadTile.collapsedReplies).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommentTile(
          comment: widget.thread.comment,
          onReply: () => _reply(widget.thread.comment),
        ),
        for (final reply in shown)
          Padding(
            padding: const EdgeInsets.only(left: _indent, top: AppSpacing.md),
            child: CommentTile(
              comment: reply,
              compact: true,
              onReply: () => _reply(reply),
            ),
          ),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(left: _indent, top: AppSpacing.sm),
            child: GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  _expanded ? 'Hide replies' : _moreLabel(hidden),
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _moreLabel(int hidden) =>
      'View $hidden more ${hidden == 1 ? 'reply' : 'replies'}';

  /// Replies always join the thread they were tapped in; tapping Reply on a
  /// reply never opens a second level. One indent is all a phone has room for,
  /// and who is being answered is carried by the name on the composer's banner
  /// instead of by another step to the right.
  void _reply(Comment comment) {
    widget.onReply(
      CommentReplyTarget(
        commentId: widget.thread.comment.id,
        authorName: comment.authorName,
      ),
    );
  }
}

/// One comment: avatar, author, age, then the words.
///
/// Public so the post detail page can list comments under the post in exactly
/// the form the sheet shows them.
class CommentTile extends StatelessWidget {
  const CommentTile({
    required this.comment,
    this.onReply,
    this.compact = false,
    super.key,
  });

  final Comment comment;

  /// Opens a reply to this comment. Null where there is nowhere to write one.
  final VoidCallback? onReply;

  /// Set on a reply: a smaller avatar, so an indented tile still leaves the
  /// words room at the depth it sits at.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Shared Avatar so a commenter's photo renders here exactly as it does
        // on their posts, falling back to initials when they have none.
        ProfileLink(
          userId: comment.authorId,
          child: Avatar(
            initials: avatarInitials(comment.authorName),
            size: compact ? 28 : 34,
            imageUrl: comment.authorAvatarUrl,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Only the name, not the age beside it: the whole row would
                  // swallow the long-press that removes a Pulse comment.
                  Flexible(
                    child: ProfileLink(
                      userId: comment.authorId,
                      child: Text(
                        comment.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _relativeTime(comment.createdAt),
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              MentionText(
                text: comment.text,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              if (onReply != null) ...[
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: onReply,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    // Vertical only: the strip has to be tappable without
                    // pushing the next comment down a whole line.
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      'Reply',
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }
}
