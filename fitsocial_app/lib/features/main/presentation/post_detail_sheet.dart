import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/post_card.dart';
import '../domain/app_models.dart';
import 'comments_sheet.dart';

/// Opens [post] in a sheet over whatever is on screen.
///
/// Explore's grid used to be a dead end — the tiles rendered a post and then
/// had nowhere to send you. A sheet rather than a route because the grid's
/// scroll position is the thing worth keeping: browsing Explore is a sequence
/// of dip-ins, and a full page push would cost that position on every one.
Future<void> showPostDetailSheet(BuildContext context, FeedPost post) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // Push onto the root navigator, not the shell branch's nested one. A
    // branch-level route only covers AppShell's body, so the floating bottom
    // nav — a sibling in the Scaffold — would paint straight over the sheet
    // and escape the modal barrier.
    useRootNavigator: true,
    builder: (_) => PostDetailSheet(post: post),
  );
}

class PostDetailSheet extends StatelessWidget {
  const PostDetailSheet({required this.post, super.key});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DraggableScrollableSheet(
      // Opens tall enough that a photo post's image and its actions are both
      // above the fold, without covering the grid entirely — the sliver of
      // Explore left showing is what makes this read as a peek rather than a
      // page.
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      // The sheet is already inside a modal route, so it must size to its
      // content rather than claiming the full screen behind the barrier.
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: palette.stroke),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md + MediaQuery.of(context).viewPadding.bottom,
            ),
            children: [
              const _GrabHandle(),
              _SheetHeader(post: post),
              const SizedBox(height: AppSpacing.sm),
              // The same card the feed renders, so like, save, comment and the
              // overflow menu behave identically here — there is no second
              // implementation of a post to keep in step.
              PostCard(
                postId: post.id,
                authorId: post.authorId,
                userName: post.userName,
                activity: post.activity,
                caption: post.caption,
                metricLabels: post.metricLabels,
                timestamp: post.timestamp,
                likes: post.likes,
                comments: post.comments,
                backgroundColors: post.backgroundColors,
                visualTile: post.visualTile,
                postType: post.postType,
                imageUrl: post.imageUrl,
                workoutData: post.workoutData,
                routePoints: post.routePoints,
                authorAvatarUrl: post.authorAvatarUrl,
                imageAspectRatio: post.imageAspectRatio,
                onCommentTapped: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    useRootNavigator: true,
                    builder: (_) => CommentsSheet(postId: post.id),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "View profile" alongside the author's name — the other half of what a tapped
/// tile is for. Explore exists to find people, so the post has to lead back to
/// whoever made it.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Post',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: palette.text,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () {
            // Resolved before the pop: `context` is defunct once the sheet has
            // been dismissed, so the router has to be held first.
            final router = GoRouter.of(context);
            // Close the sheet rather than stacking the profile on top of it —
            // otherwise backing out of the profile lands on a post the user
            // has already navigated away from.
            Navigator.of(context).pop();
            router.push('/user/${post.authorId}');
          },
          style: TextButton.styleFrom(foregroundColor: AppColors.orangeBright),
          icon: const Icon(Icons.person_outline_rounded, size: 18),
          label: const Text('View profile'),
        ),
      ],
    );
  }
}

class _GrabHandle extends StatelessWidget {
  const _GrabHandle();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: palette.stroke,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
