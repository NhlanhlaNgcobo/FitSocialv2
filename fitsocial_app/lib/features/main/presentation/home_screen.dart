import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/create_flow_controller.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';
import '../../../shared/widgets/activity_grid.dart';
import '../../../shared/widgets/bottom_nav.dart';
import '../../../shared/widgets/fit_social_logo.dart';
import '../../../shared/widgets/post_card.dart';
import '../../notifications/application/notification_providers.dart';
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
            onPressed: () => context.push('/notifications'),
            icon: const _NotificationBell(),
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
            data: (feed) => _buildFeed(feed, ref),
            loading: () => const _SectionPlaceholder(label: 'Loading feed...'),
            error: (_, __) =>
                const _SectionPlaceholder(label: 'Feed unavailable'),
          ),
        ],
      ),
    );
  }

  Widget _buildFeed(HomeFeed feed, WidgetRef ref) {
    if (feed.isEmpty) return const _NothingPostedYet();

    return Column(
      children: [
        // Said out loud when these are not the people you follow, so a quiet
        // feed is never mistaken for a quiet community — or the other way
        // round.
        if (feed.source == FeedSource.suggested) ...[
          const _SuggestedHeader(),
          const SizedBox(height: AppSpacing.sm),
        ],
        ..._buildPosts(feed.posts, ref),
      ],
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
          postType: post.postType,
          imageUrl: post.imageUrl,
          workoutData: post.workoutData,
          routePoints: post.routePoints,
          authorAvatarUrl: post.authorAvatarUrl,
          imageAspectRatio: post.imageAspectRatio,
          taggedUsers: post.taggedUsers,
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

/// Says that what follows is the community rather than the people you follow,
/// and offers the one action that changes that.
class _SuggestedHeader extends StatelessWidget {
  const _SuggestedHeader();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.explore_outlined,
                size: 18,
                color: AppColors.orangeBright,
              ),
              const SizedBox(width: 8),
              Text(
                'Suggested for you',
                style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Follow people and their posts land here first.',
            style: TextStyle(color: palette.muted, fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.text,
              side: BorderSide(color: palette.stroke),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => context.go('/explore'),
            icon: const Icon(Icons.person_search_outlined, size: 18),
            label: const Text('Find people'),
          ),
        ],
      ),
    );
  }
}

/// The one case the suggested feed can't cover: nobody in the app has posted
/// anything yet.
class _NothingPostedYet extends StatelessWidget {
  const _NothingPostedYet();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.stroke),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.orangeBright.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: AppColors.orangeBright,
              size: 30,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'The feed is empty',
            style: TextStyle(
              color: palette.text,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Nobody has posted yet. Log a session and start it off.',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted, fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.orangeBright,
              side: const BorderSide(color: AppColors.orangeBright),
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => context.go('/create'),
            child: const Text('Create a post'),
          ),
        ],
      ),
    );
  }
}

/// The bell, carrying a count of what is waiting behind it.
///
/// The count is read from the same stream the notifications list renders, so
/// the badge can never claim something the list doesn't show. It clears
/// because opening the list marks it read, not because it was tapped.
class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.notifications_none_rounded),
        if (unread > 0)
          Positioned(
            right: -4,
            top: -3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: AppColors.orangeBright,
                borderRadius: BorderRadius.circular(999),
                // Separates the badge from the glyph underneath it, whichever
                // way the theme has painted the bar.
                border:
                    Border.all(color: context.palette.background, width: 1.5),
              ),
              child: Text(
                // Past nine the exact number stops being information; what
                // matters is that there is a lot.
                unread > 9 ? '9+' : '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.onBrand,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ),
          ),
      ],
    );
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
