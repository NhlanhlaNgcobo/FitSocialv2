import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../auth/application/app_session.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/brand_image_tile.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/primary_button.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(appSessionProvider).profile;
    final stats = ref.watch(profileStatsProvider);
    final displayName = profile?.displayName ?? 'FitSocial User';
    final handle = profile?.handle ?? '@fitsocial';
    final initials = _initials(displayName);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(displayName),
          actions: [
            IconButton(
              onPressed: () => context.push('/achievements'),
              icon: const Icon(Icons.workspace_premium_outlined),
            ),
            IconButton(
              onPressed: () => context.push('/edit-profile'),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.grid_view_rounded)),
              Tab(icon: Icon(Icons.fitness_center_rounded)),
              Tab(icon: Icon(Icons.directions_run_rounded)),
              Tab(icon: Icon(Icons.restaurant_rounded)),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: DarkCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Avatar(
                          initials: initials,
                          size: 68,
                          imageUrl: profile?.avatarUrl,
                          // Only reached when the user has no uploaded photo.
                          visualTile: AppVisualTile.heroPortrait,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: stats.when(
                              data: _buildStats,
                              loading: () => const [
                                _ProfileStat(label: 'Posts', value: '--'),
                                _ProfileStat(label: 'Followers', value: '--'),
                                _ProfileStat(label: 'Following', value: '--'),
                              ],
                              error: (_, __) => const [
                                _ProfileStat(label: 'Posts', value: '--'),
                                _ProfileStat(label: 'Followers', value: '--'),
                                _ProfileStat(label: 'Following', value: '--'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '$handle\n${profile?.bio ?? ''}\n${profile?.location ?? ''}',
                        style: const TextStyle(
                            color: AppColors.muted, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: PrimaryButton(
                            label: 'Edit Profile',
                            onPressed: () => context.push('/edit-profile'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        SizedBox(
                          height: 56,
                          width: 56,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.stroke),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            onPressed: () =>
                                ref.read(appSessionProvider).signOut(),
                            child: const Icon(Icons.logout_rounded),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  // First tab is the photo grid; the rest filter the user's
                  // posts by activity.
                  _MediaGrid(mediaOnly: true),
                  _MediaGrid(activityKeyword: 'workout'),
                  _MediaGrid(activityKeyword: 'run'),
                  _MediaGrid(activityKeyword: 'meal'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStats(List<ProfileStat> stats) {
    return stats
        .map(
          (stat) => _ProfileStat(
            label: stat.label,
            value: stat.value,
          ),
        )
        .toList();
  }
}

String _initials(String value) {
  final parts = value.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return 'FS';
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: AppColors.muted),
        ),
      ],
    );
  }
}

/// Grid of the signed-in user's OWN posts, queried by `authorId`. New accounts
/// with no posts get an empty state — never mock/brand placeholder images.
class _MediaGrid extends ConsumerWidget {
  const _MediaGrid({this.mediaOnly = false, this.activityKeyword});

  /// Photo grid: query only posts that carry an uploaded image.
  final bool mediaOnly;

  /// When set, only posts whose activity contains this keyword are shown
  /// (used by the Workouts / Runs / Meals tabs).
  final String? activityKeyword;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      return const _EmptyGrid(message: 'Sign in to see your posts.');
    }

    final posts = ref.watch(
      mediaOnly ? userMediaPostsProvider(userId) : userPostsProvider(userId),
    );

    return posts.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.orangeBright),
      ),
      error: (_, __) => _ErrorGrid(
        onRetry: () => ref.invalidate(
          mediaOnly ? userMediaPostsProvider(userId) : userPostsProvider(userId),
        ),
      ),
      data: (all) {
        final keyword = activityKeyword;
        final visible = keyword == null
            ? all
            : all
                .where((p) => p.activity.toLowerCase().contains(keyword))
                .toList();

        if (visible.isEmpty) {
          return _EmptyGrid(
            message: mediaOnly
                ? 'Photos you post will show up here.'
                : keyword == null
                    ? 'No posts yet. Share your first workout!'
                    : 'No ${keyword}s shared yet.',
          );
        }

        return RefreshIndicator(
          color: AppColors.orangeBright,
          backgroundColor: AppColors.surface,
          onRefresh: () async => ref.invalidate(
            mediaOnly
                ? userMediaPostsProvider(userId)
                : userPostsProvider(userId),
          ),
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            itemCount: visible.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (context, index) => _PostTile(post: visible[index]),
          ),
        );
      },
    );
  }
}

class _ErrorGrid extends StatelessWidget {
  const _ErrorGrid({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: AppColors.muted,
              size: 42,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              "Couldn't load your posts.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 15),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.white,
                side: const BorderSide(color: AppColors.stroke),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single post tile — the uploaded photo when present, otherwise a
/// gradient card labelled with the activity.
class _PostTile extends StatelessWidget {
  const _PostTile({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    if (post.imageUrl != null && post.imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(
          post.imageUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _GradientTile(post: post),
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _GradientTile(post: post),
        ),
      );
    }
    return _GradientTile(post: post);
  }
}

class _GradientTile extends StatelessWidget {
  const _GradientTile({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final colors = post.backgroundColors.isNotEmpty
        ? post.backgroundColors
        : [AppColors.surfaceHigh, AppColors.surface];
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(8),
      alignment: Alignment.bottomLeft,
      child: Text(
        post.activity,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _EmptyGrid extends StatelessWidget {
  const _EmptyGrid({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceHigh,
              ),
              child: const Icon(
                Icons.camera_alt_outlined,
                color: AppColors.orangeBright,
                size: 48,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text(
              'No posts yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.white,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
