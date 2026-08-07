import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/follow_button.dart';
import '../../../shared/widgets/post_gradient.dart';
import '../../../shared/widgets/profile_bio.dart';
import '../../../shared/widgets/profile_stats_bar.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';

/// Someone else's profile.
///
/// Distinct from [ProfileScreen] rather than a mode of it: the two share a
/// stats bar and a bio and nothing else. Every control differs — this one
/// follows and mutes, the other edits and composes — and folding both into one
/// widget would mean a conditional on every row.
class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({required this.userId, super.key});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider(userId));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _TopActionBar(userId: userId),
            Expanded(
              child: profile.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.orangeBright,
                  ),
                ),
                error: (_, __) => _Message(
                  icon: Icons.cloud_off_rounded,
                  title: "Couldn't load this profile",
                  message: 'Check your connection and try again.',
                  onRetry: () => ref.invalidate(userProfileProvider(userId)),
                ),
                data: (user) {
                  if (user == null) {
                    return const _Message(
                      icon: Icons.person_off_outlined,
                      title: 'Profile not found',
                      message: 'This account may have been removed.',
                    );
                  }
                  return _ProfileBody(user: user);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Back on the left, notification toggle on the right.
class _TopActionBar extends ConsumerWidget {
  const _TopActionBar({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final isOn = ref.watch(userNotificationsProvider(userId)).valueOrNull ??
        false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            tooltip: 'Back',
            color: palette.text,
            icon: const Icon(Icons.chevron_left_rounded, size: 30),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => _toggle(context, ref, isOn),
            tooltip: isOn ? 'Turn off notifications' : 'Notify me about posts',
            color: isOn ? AppColors.orangeBright : palette.text,
            icon: Icon(
              isOn
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    bool isOn,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(userNotificationActionsProvider)(userId, enabled: !isOn);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't change notifications: $error")),
      );
    }
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.user});

  final UserSearchResult user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final posts = ref.watch(userMediaPostsProvider(user.id));
    final bio = user.bio.trim();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              Avatar(
                initials: user.initials,
                size: 96,
                imageUrl: user.avatarUrl,
              ),
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  _formatHandle(user.handle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ProfileStatsBar(userId: user.id),
              const SizedBox(height: AppSpacing.lg),
              // Hides itself when this is somehow the signed-in user's own
              // profile, so the row simply collapses.
              FollowButton(
                targetUserId: user.id,
                shape: FollowButtonShape.pill,
              ),
              if (bio.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                ProfileBio(bio: bio),
              ],
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
        ...posts.when(
          loading: () => const [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppColors.orangeBright,
                  ),
                ),
              ),
            ),
          ],
          error: (_, __) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  "Couldn't load these posts.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.muted),
                ),
              ),
            ),
          ],
          data: (items) {
            if (items.isEmpty) {
              return [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Text(
                      "This person hasn't shared any photos yet.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.muted),
                    ),
                  ),
                ),
              ];
            }
            return [
              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.md),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _PostTile(post: items[index]),
                    childCount: items.length,
                  ),
                ),
              ),
            ];
          },
        ),
      ],
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    final url = post.imageUrl;
    final hasImage = url != null && url.isNotEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/post/${post.id}', extra: post),
      child: hasImage
          ? ClipRRect(
              borderRadius: radius,
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _GradientTile(post: post),
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : _GradientTile(post: post),
              ),
            )
          : _GradientTile(post: post),
    );
  }
}

class _GradientTile extends StatelessWidget {
  const _GradientTile({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: postGradientColors(post.backgroundColors, palette),
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
        style: TextStyle(
          color: postGradientTextColor(palette),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: palette.muted),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.text,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted, height: 1.5),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.text,
                  side: BorderSide(color: palette.stroke),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Stored handles may or may not carry the '@'.
String _formatHandle(String handle) {
  final trimmed = handle.trim().replaceAll(RegExp(r'^@+'), '');
  return trimmed.isEmpty ? '@fitsocial' : '@$trimmed';
}
