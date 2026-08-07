import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/create_flow_controller.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';
import '../../../shared/widgets/activity_grid.dart';
import '../../../shared/widgets/bottom_nav.dart';
import '../../../shared/widgets/fit_social_logo.dart';
import '../../../shared/widgets/post_card.dart';
import '../../pulse/presentation/pulse_tray.dart';
import 'comments_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(feedPostsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const FitSocialLogo(size: 24, animated: false),
        actions: [
          IconButton(
            onPressed: () => context.push('/health'),
            icon: const Icon(Icons.monitor_heart_outlined),
          ),
          IconButton(
            onPressed: () => context.push('/achievements'),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            onPressed: () {
              ref
                  .read(createFlowControllerProvider.notifier)
                  .begin(CreateCanvasDestination.photo);
              context.push(CreateCanvasDestination.photo.route);
            },
            icon: const Icon(Icons.photo_camera_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          // Clears the floating nav, which overlays this list rather than
          // sitting below it.
          AppSpacing.md + FitSocialBottomNav.clearance(context),
        ),
        children: [
          const PulseTray(),
          const SizedBox(height: AppSpacing.sm),
          // The current Mon-Sun week, pinned: the feed is somewhere to glance
          // at the streak, not somewhere to change the window.
          const ActivityGridCard(fixedRange: ActivityRange.week),
          const SizedBox(height: AppSpacing.sm),
          posts.when(
            data: (data) => _buildPostColumn(data, ref),
            loading: () => const _SectionPlaceholder(label: 'Loading feed...'),
            error: (_, __) =>
                const _SectionPlaceholder(label: 'Feed unavailable'),
          ),
        ],
      ),
    );
  }

  Widget _buildPostColumn(List<FeedPost> posts, WidgetRef ref) {
    return Column(
      children: _buildPosts(posts, ref),
    );
  }

  List<Widget> _buildPosts(List<FeedPost> posts, WidgetRef ref) {
    final items = <Widget>[];
    for (var i = 0; i < posts.length; i++) {
      final post = posts[i];
      items.add(
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
              context: ref.context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              // Push onto the root navigator, not the shell branch's nested
              // one. A branch-level route only covers AppShell's body, so the
              // floating bottom nav — a sibling in the Scaffold — would paint
              // straight over the sheet and escape the modal barrier.
              useRootNavigator: true,
              builder: (_) => CommentsSheet(postId: post.id),
            );
          },
        ),
      );
      if (i != posts.length - 1) {
        // Just enough to keep the two card borders from touching — the feed
        // should read as a continuous stack, not a list of spaced-out tiles.
        items.add(const SizedBox(height: AppSpacing.xs));
      }
    }
    return items;
  }
}

class _SectionPlaceholder extends StatelessWidget {
  const _SectionPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.stroke),
      ),
      child: Text(
        label,
        style: TextStyle(color: palette.muted),
      ),
    );
  }
}

