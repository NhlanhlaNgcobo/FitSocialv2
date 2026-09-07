import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/auth/application/app_session.dart';
import '../../features/main/application/content_providers.dart';
import '../../features/main/data/content_repository.dart';
import 'mention_suggestions.dart';
import 'quick_toast.dart';
import '../../shared/widgets/liquid_glass.dart';

/// The "Add a comment…" well and its send button.
///
/// Lives here rather than inside the comments sheet because the post detail
/// page pins the same control to the bottom of the screen: writing a comment
/// has to behave identically — and refresh the same providers — wherever the
/// post is being read.
///
/// The caller owns the inset below it. Nothing lifts this clear of the
/// keyboard on its own — a [Scaffold] pins `bottomNavigationBar` to the bottom
/// of the screen regardless of `viewInsets` — so every host has to pad for
/// whichever of the keyboard and the system nav bar is taller.
/// The comment a reply is aimed at.
///
/// [commentId] is the thread it joins, which is not always the comment that
/// was tapped: replying to a reply keeps the same thread and only changes who
/// is being answered. [authorName] is who that is.
class CommentReplyTarget {
  const CommentReplyTarget({
    required this.commentId,
    required this.authorName,
  });

  final String commentId;
  final String authorName;
}

class CommentComposer extends ConsumerStatefulWidget {
  const CommentComposer({
    required this.postId,
    this.focusNode,
    this.replyTo,
    this.onClearReply,
    super.key,
  });

  final String postId;

  /// Lets the host put the cursor in the box — the detail page's comment icon
  /// has no sheet to open, so it focuses this instead.
  final FocusNode? focusNode;

  /// What this comment will answer, or null when it starts a thread.
  ///
  /// Owned by the host rather than by this widget: the Reply button that sets
  /// it lives up in the list, and on the detail page the list and the box are
  /// not even in the same subtree.
  final CommentReplyTarget? replyTo;

  /// Called when the reply is taken back — by the ✕ on the banner, and by a
  /// send, which has answered it.
  final VoidCallback? onClearReply;

  @override
  ConsumerState<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends ConsumerState<CommentComposer> {
  final _controller = TextEditingController();

  /// Stands in when the host didn't supply one. The suggestion list needs to
  /// know whether the field is being typed in, so there always has to be a
  /// focus node even when nobody outside wanted to drive it.
  final _ownFocus = FocusNode();

  bool _isSending = false;

  FocusNode get _focusNode => widget.focusNode ?? _ownFocus;

  @override
  void dispose() {
    _controller.dispose();
    _ownFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    try {
      final repository = ref.read(contentRepositoryProvider);
      // Attribution comes from the public profile, never from auth.
      final profile = ref.read(appSessionProvider).profile;
      await repository.addComment(
        profile,
        widget.postId,
        text,
        parentCommentId: widget.replyTo?.commentId,
      );

      _controller.clear();
      // The reply has been written, so the banner has nothing left to say.
      widget.onClearReply?.call();

      // Bump the comment count on the feed post card
      ref.read(feedPostsProvider.notifier).incrementCommentCount(widget.postId);

      // Refresh comment list
      ref.invalidate(commentsProvider(widget.postId));
    } catch (e) {
      if (mounted) {
        debugPrint('Posting a comment failed: $e');
        showQuickToast(
          context,
          "Couldn't post that comment. Try again.",
          icon: Icons.error_outline_rounded,
          tone: ToastTone.danger,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(
          top: BorderSide(color: palette.stroke),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.replyTo != null) _replyBanner(palette, widget.replyTo!),
          // Above the field, not below it: this bar already sits on the
          // keyboard, so there is no room underneath to open into.
          MentionSuggestions(
            controller: _controller,
            focusNode: _focusNode,
          ),
          _inputRow(palette),
        ],
      ),
    );
  }

  /// Says where this comment is about to go, and offers the one way out of
  /// it. Without this a reply and a new comment are the same empty box, and
  /// the difference only shows up after it has been sent.
  Widget _replyBanner(AppPalette palette, CommentReplyTarget target) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Icon(Icons.reply_rounded, size: 15, color: palette.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Replying to ${target.authorName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.muted, fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap: widget.onClearReply,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: palette.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputRow(AppPalette palette) {
    return Row(
      children: [
        Expanded(
          child: LiquidGlass(
            // Painted by the lens rather than by a fill of its own: a pane
            // over the app backdrop, like every other card.
            borderRadius: BorderRadius.circular(24),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: widget.replyTo == null
                      ? 'Add a comment...'
                      : 'Reply to ${widget.replyTo!.authorName}...',
                  hintStyle: TextStyle(color: palette.muted),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        GestureDetector(
          onTap: _submit,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFA053), Color(0xFFFF6B2C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: _isSending
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      color: AppColors.onBrand,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(
                    Icons.send_rounded,
                    color: palette.text,
                    size: 18,
                  ),
          ),
        ),
      ],
    );
  }
}
