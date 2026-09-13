import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/identity/profile_identity.dart';
import '../../../shared/widgets/comment_well.dart';
import '../../../shared/widgets/keyboard_safe_bottom_bar.dart';
import '../../../shared/widgets/mention_suggestions.dart';
import '../../auth/application/app_session.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider;
import '../../main/domain/app_models.dart' show Comment;
import '../../main/presentation/comments_sheet.dart' show CommentTile;
import '../../../shared/widgets/quick_toast.dart';
import '../application/pulse_providers.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// The conversation under a Pulse.
///
/// Visible to everyone the Pulse itself is visible to, and gone when it is —
/// the comments carry the same 24-hour life as the thing they are about, which
/// is what keeps a Pulse a moment rather than a post.
///
/// Deliberately not the post comments sheet with a different id: that one
/// writes through the content repository and bumps a feed post's counter, and
/// neither has any meaning here.
class PulseCommentsSheet extends ConsumerWidget {
  const PulseCommentsSheet({
    required this.pulseId,
    required this.pulseAuthorId,
    super.key,
  });

  final String pulseId;

  /// Who published the Pulse. They may remove any comment under it — the same
  /// latitude a post's author has over their own thread.
  final String pulseAuthorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final comments = ref.watch(pulseCommentsProvider(pulseId));

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
            Container(height: 1, color: palette.stroke),
            Flexible(
              child: comments.when(
                data: (list) => list.isEmpty
                    ? const _Message(
                        label: 'No comments yet.\n'
                            'Say something about this Pulse.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        itemCount: list.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.md),
                        itemBuilder: (context, index) => _PulseCommentRow(
                          pulseId: pulseId,
                          pulseAuthorId: pulseAuthorId,
                          comment: list[index],
                        ),
                      ),
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.orangeBright,
                      strokeWidth: 2,
                    ),
                  ),
                ),
                error: (_, __) =>
                    const _Message(label: "Couldn't load comments."),
              ),
            ),
            // This sheet floats over its own barrier, so nothing else lifts the
            // composer clear of the keyboard — it pads for whichever of the
            // keyboard and the nav bar is taller itself.
            KeyboardSafeBottomBar(
                child: _PulseCommentComposer(pulseId: pulseId)),
          ],
        ),
      ),
    );
  }
}

/// One comment, with a long-press to remove it where that is allowed.
class _PulseCommentRow extends ConsumerWidget {
  const _PulseCommentRow({
    required this.pulseId,
    required this.pulseAuthorId,
    required this.comment,
  });

  final String pulseId;
  final String pulseAuthorId;
  final Comment comment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = ref.watch(currentUserIdProvider);
    final canDelete = currentUserId != null &&
        (currentUserId == comment.authorId || currentUserId == pulseAuthorId);

    if (!canDelete) return CommentTile(comment: comment);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _confirmDelete(context, ref),
      child: CommentTile(comment: comment),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => LiquidGlass(
        // A dialog interrupts a page, so there is always something
        // behind it -- which makes it glass like everything else.
        borderRadius: BorderRadius.circular(22),
        child: AlertDialog(
          title: const Text('Delete this comment?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Delete',
                style: TextStyle(color: palette.danger),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      await ref.read(pulseActionsProvider).deleteComment(pulseId, comment.id);
    } catch (_) {
      showQuickToastOn(
        overlay,
        "Couldn't delete that comment.",
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    }
  }
}

/// The "Add a comment…" well for a Pulse.
///
/// A sibling of the feed's comment composer rather than a reuse of it: that
/// one is bound to a post id and refreshes the feed's own providers on send.
/// The mention autocomplete is shared, because `@` should behave the same
/// wherever it is typed.
class _PulseCommentComposer extends ConsumerStatefulWidget {
  const _PulseCommentComposer({required this.pulseId});

  final String pulseId;

  @override
  ConsumerState<_PulseCommentComposer> createState() =>
      _PulseCommentComposerState();
}

class _PulseCommentComposerState extends ConsumerState<_PulseCommentComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    // Both resolved before the await: the send can outlive this widget, and
    // reaching for the context afterwards is what makes that a crash.
    final overlay = Overlay.of(context, rootOverlay: true);

    try {
      await ref.read(pulseActionsProvider).comment(widget.pulseId, text);
      // Cleared only on success, so a failed send leaves the words in the box
      // to try again with rather than losing them.
      _controller.clear();
    } catch (error) {
      debugPrint('Posting a Pulse comment failed: $error');
      showQuickToastOn(
        overlay,
        "Couldn't post that comment. Try again.",
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Signed out there is nobody to attribute a comment to, and the write
    // would be refused anyway — so the box isn't offered.
    if (ref.watch(currentUserIdProvider) == null) {
      return const SizedBox.shrink();
    }

    final profile = ref.watch(appSessionProvider).profile;

    return LiquidGlass(
      // Square: this pane meets the sheet's bottom edge on both sides.
      borderRadius: BorderRadius.circular(0),
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.stroke)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm + 2,
          AppSpacing.md,
          AppSpacing.sm + 2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Above the field, not below it: this bar already sits on the
            // keyboard, so there is no room underneath to open into.
            MentionSuggestions(controller: _controller, focusNode: _focusNode),
            // The same box as under a post — see [CommentWell] for why the
            // material is shared and the writes are not.
            CommentWell(
              controller: _controller,
              focusNode: _focusNode,
              onSubmit: _submit,
              isSending: _isSending,
              hintText: 'Add a comment…',
              avatarInitials: avatarInitials(profile?.displayName),
              avatarUrl: profile?.avatarUrl,
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.palette.muted,
            fontSize: 15,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
