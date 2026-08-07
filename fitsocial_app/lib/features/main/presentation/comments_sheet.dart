import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/comment_composer.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';

class CommentsSheet extends ConsumerWidget {
  const CommentsSheet({required this.postId, super.key});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final commentsAsync = ref.watch(commentsProvider(postId));
    final media = MediaQuery.of(context);

    // Keep the composer clear of whatever is occupying the bottom edge. With
    // the keyboard up that's viewInsets; with it down it's the system nav bar,
    // which viewInsets never reports — take whichever is larger so the send
    // row is never tucked under the gesture pill or the 3-button bar.
    final bottomInset = math.max(
      media.viewInsets.bottom,
      media.viewPadding.bottom,
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  itemCount: comments.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, index) {
                    final comment = comments[index];
                    return CommentTile(comment: comment);
                  },
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: CircularProgressIndicator(
                    color: AppColors.orangeBright,
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
          Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: CommentComposer(postId: postId),
          ),
        ],
      ),
    );
  }
}

/// One comment: avatar, author, age, then the words.
///
/// Public so the post detail page can list comments under the post in exactly
/// the form the sheet shows them.
class CommentTile extends StatelessWidget {
  const CommentTile({required this.comment, super.key});

  final Comment comment;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Shared Avatar so a commenter's photo renders here exactly as it does
        // on their posts, falling back to initials when they have none.
        Avatar(
          initials: _initials(comment.authorName),
          size: 34,
          imageUrl: comment.authorAvatarUrl,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    comment.authorName,
                    style: TextStyle(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
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
              Text(
                comment.text,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length < 2) {
      final first = parts.first;
      if (first.isEmpty) return 'FS';
      return first.substring(0, first.length > 1 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
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
