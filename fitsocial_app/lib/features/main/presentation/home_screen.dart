import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../application/content_providers.dart';
import '../application/music_integration_controller.dart';
import '../domain/app_models.dart';
import '../../../shared/widgets/fit_social_logo.dart';
import '../../../shared/widgets/post_card.dart';
import '../../../shared/widgets/story_avatar.dart';
import 'comments_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stories = ref.watch(storyItemsProvider);
    final summaryMetrics = ref.watch(summaryMetricsProvider);
    final posts = ref.watch(feedPostsProvider);
    final musicState = ref.watch(musicIntegrationControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const FitSocialLogo(size: 24, animated: false),
        actions: [
          IconButton(
            onPressed: () => context.push('/achievements'),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            onPressed: () => context.push('/meal-camera'),
            icon: const Icon(Icons.photo_camera_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          stories.when(
            data: (data) => SizedBox(
              height: 96,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: _buildStories(data)),
              ),
            ),
            loading: () => const SizedBox(
              height: 96,
              child: _SectionPlaceholder(label: 'Loading stories...'),
            ),
            error: (_, __) => const SizedBox(
              height: 96,
              child: _SectionPlaceholder(label: 'Stories unavailable'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          summaryMetrics.when(
            data: (data) {
              if (data.length < 2) {
                return const _SectionPlaceholder(
                  label: 'Summary unavailable',
                );
              }
              return _TodaySummary(summaryMetrics: data);
            },
            loading: () => const _SummaryPlaceholder(),
            error: (_, __) =>
                const _SectionPlaceholder(label: 'Summary unavailable'),
          ),
          const SizedBox(height: AppSpacing.lg),
          _MusicSpotlightCard(
            hasConnection: musicState.hasAnyConnection,
            onOpenMusic: () {
              ref
                  .read(musicIntegrationControllerProvider.notifier)
                  .selectSection(ActivitySection.music);
              context.go('/activity');
            },
          ),
          const SizedBox(height: AppSpacing.lg),
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

  List<Widget> _buildStories(List<StoryItem> stories) {
    final items = <Widget>[];
    for (var i = 0; i < stories.length; i++) {
      final story = stories[i];
      items.add(
        StoryAvatar(
          name: story.name,
          initials: story.initials,
          visualTile: story.visualTile,
          isOwnStory: story.isOwnStory,
        ),
      );
      if (i != stories.length - 1) {
        items.add(const SizedBox(width: AppSpacing.md));
      }
    }
    return items;
  }

  List<Widget> _buildPosts(List<FeedPost> posts, WidgetRef ref) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final items = <Widget>[];
    for (var i = 0; i < posts.length; i++) {
      final post = posts[i];
      items.add(
        PostCard(
          userName: post.userName,
          activity: post.activity,
          caption: post.caption,
          metricLabels: post.metricLabels,
          timestamp: post.timestamp,
          likes: post.likes,
          comments: post.comments,
          backgroundColors: post.backgroundColors,
          visualTile: post.visualTile,
          isLikedByMe: post.likedBy.contains(currentUserId),
          onLikeTapped: () {
            ref
                .read(feedPostsProvider.notifier)
                .toggleLike(post.id, currentUserId);
          },
          onCommentTapped: () {
            showModalBottomSheet(
              context: ref.context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => CommentsSheet(postId: post.id),
            );
          },
        ),
      );
      if (i != posts.length - 1) {
        items.add(const SizedBox(height: AppSpacing.md));
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
    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Text(
        label,
        style: const TextStyle(color: AppColors.muted),
      ),
    );
  }
}

class _SummaryPlaceholder extends StatelessWidget {
  const _SummaryPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const _SectionPlaceholder(label: 'Loading summary...');
  }
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({required this.summaryMetrics});

  final List<SummaryMetric> summaryMetrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.stroke),
        gradient: const LinearGradient(
          colors: [Color(0xFF1B120C), AppColors.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryMetric(
              label: summaryMetrics[0].label,
              value: summaryMetrics[0].value,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _SummaryMetric(
              label: summaryMetrics[1].label,
              value: summaryMetrics[1].value,
            ),
          ),
        ],
      ),
    );
  }
}

class _MusicSpotlightCard extends StatelessWidget {
  const _MusicSpotlightCard({
    required this.hasConnection,
    required this.onOpenMusic,
  });

  final bool hasConnection;
  final VoidCallback onOpenMusic;

  @override
  Widget build(BuildContext context) {
    return DarkCard(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFA053), Color(0xFFFF6B2C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.music_note_rounded,
              color: AppColors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Music for your workout',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  hasConnection
                      ? 'Open your workout playlists and podcast picks.'
                      : 'Connect Spotify or Apple Music and build your training soundtrack.',
                  style: const TextStyle(color: AppColors.muted, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            onPressed: onOpenMusic,
            icon: const Icon(Icons.chevron_right_rounded),
            color: AppColors.orangeBright,
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
