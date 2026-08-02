import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(userSearchQueryProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Search fires 400ms after typing stops — one query per search rather than
  /// one per keystroke.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      ref.read(userSearchQueryProvider.notifier).state = value.trim();
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    ref.read(userSearchQueryProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(userSearchQueryProvider);
    final isSearching = query.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Explore')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              style: const TextStyle(color: AppColors.white),
              decoration: InputDecoration(
                hintText: 'Search people by name or handle',
                hintStyle: const TextStyle(color: AppColors.muted),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.muted,
                ),
                suffixIcon: isSearching || _controller.text.isNotEmpty
                    ? IconButton(
                        onPressed: _clear,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.muted,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: AppColors.stroke),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: AppColors.stroke),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: AppColors.orangeBright),
                ),
              ),
            ),
          ),
          Expanded(
            child: isSearching
                ? _SearchResults(query: query)
                : const _TrendingSection(),
          ),
        ],
      ),
    );
  }
}

// ── User search results ─────────────────────────────────────────────────────

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(userSearchResultsProvider(query));

    return results.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.orangeBright),
      ),
      error: (_, __) => _ExploreMessage(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't run that search",
        message: 'Check your connection and try again.',
        onRetry: () => ref.invalidate(userSearchResultsProvider(query)),
      ),
      data: (users) {
        if (users.isEmpty) {
          return _ExploreMessage(
            icon: Icons.person_search_outlined,
            title: 'No people found',
            message: 'Nothing matched "$query". Search is case-sensitive, so '
                'try matching how the name is written.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          itemCount: users.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) => _UserResultTile(user: users[index]),
        );
      },
    );
  }
}

class _UserResultTile extends StatelessWidget {
  const _UserResultTile({required this.user});

  final UserSearchResult user;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _UserPostsSheet(user: user),
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Row(
          children: [
            _UserAvatar(user: user, size: 48),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.handle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            Text(
              '${user.postsCount} ${user.postsCount == 1 ? 'post' : 'posts'}',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.user, required this.size});

  final UserSearchResult user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasAvatar = user.avatarUrl != null && user.avatarUrl!.isNotEmpty;

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFF444444), Color(0xFF2A2A2A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: hasAvatar
          ? Image.network(
              user.avatarUrl!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (_, __, ___) => _initialsText(),
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : _initialsText(),
            )
          : _initialsText(),
    );
  }

  Widget _initialsText() {
    return Text(
      user.initials,
      style: TextStyle(
        color: AppColors.white,
        fontWeight: FontWeight.w700,
        fontSize: size * 0.34,
      ),
    );
  }
}

/// Tapping a search result opens their posts here. FitSocial has no public
/// profile route yet, so this shows the same content inline.
class _UserPostsSheet extends ConsumerWidget {
  const _UserPostsSheet({required this.user});

  final UserSearchResult user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(userPostsProvider(user.id));

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                color: AppColors.stroke,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                _UserAvatar(user: user, size: 52),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.handle,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      if (user.bio.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          user.bio,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: FollowButton(targetUserId: user.id),
          ),
          Container(height: 1, color: AppColors.stroke),
          Flexible(
            child: posts.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppColors.orangeBright,
                  ),
                ),
              ),
              error: (_, __) => const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  "Couldn't load these posts.",
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Text(
                      "This person hasn't posted yet.",
                      style: TextStyle(color: AppColors.muted),
                    ),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: items.length,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (context, index) =>
                      _PostThumb(post: items[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Follow / Unfollow toggle for another user's profile. Hides itself on the
/// signed-in user's own profile, since you can't follow yourself.
class FollowButton extends ConsumerStatefulWidget {
  const FollowButton({required this.targetUserId, super.key});

  final String targetUserId;

  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  bool _isPending = false;

  Future<void> _toggle(bool isFollowing) async {
    setState(() => _isPending = true);
    try {
      await ref
          .read(followActionsProvider)
          .toggle(widget.targetUserId, isFollowing: isFollowing);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFollowing
                ? "Couldn't unfollow: $error"
                : "Couldn't follow: $error",
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isPending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);
    if (currentUserId == null || currentUserId == widget.targetUserId) {
      return const SizedBox.shrink();
    }

    final isFollowing =
        ref.watch(isFollowingProvider(widget.targetUserId)).valueOrNull ??
            false;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: isFollowing
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.white,
                side: const BorderSide(color: AppColors.stroke),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _isPending ? null : () => _toggle(true),
              child: _isPending
                  ? const _ButtonSpinner(color: AppColors.white)
                  : const Text(
                      'Following',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            )
          : FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _isPending ? null : () => _toggle(false),
              child: _isPending
                  ? const _ButtonSpinner(color: AppColors.white)
                  : const Text(
                      'Follow',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
  }
}

// ── Trending ────────────────────────────────────────────────────────────────

class _TrendingSection extends ConsumerWidget {
  const _TrendingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trending = ref.watch(trendingPostsProvider);

    return trending.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.orangeBright),
      ),
      error: (_, __) => _ExploreMessage(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load trending",
        message: 'Check your connection and try again.',
        onRetry: () => ref.invalidate(trendingPostsProvider),
      ),
      data: (posts) {
        if (posts.isEmpty) {
          return const _ExploreMessage(
            icon: Icons.trending_up_rounded,
            title: 'Nothing trending yet',
            message: 'Once the community starts posting, the most-liked '
                'workouts, runs and meals land here.',
          );
        }

        return RefreshIndicator(
          color: AppColors.orangeBright,
          backgroundColor: AppColors.surface,
          onRefresh: () async => ref.invalidate(trendingPostsProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.trending_up_rounded,
                    color: AppColors.orangeBright,
                    size: 20,
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Text(
                    'Trending Posts',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: posts.length,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.85,
                ),
                itemBuilder: (context, index) =>
                    _TrendingTile(post: posts[index]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TrendingTile extends StatelessWidget {
  const _TrendingTile({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _PostBackground(post: post),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm + 2),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Color(0xE6050505)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    post.userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    post.activity,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.favorite_rounded,
                    color: AppColors.orangeBright,
                    size: 13,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${post.likes}',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared post visuals ─────────────────────────────────────────────────────

class _PostThumb extends StatelessWidget {
  const _PostThumb({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: _PostBackground(post: post),
    );
  }
}

/// The post's photo when it has one, otherwise its gradient theme with the
/// activity label.
class _PostBackground extends StatelessWidget {
  const _PostBackground({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final hasImage = post.imageUrl != null && post.imageUrl!.isNotEmpty;
    if (!hasImage) return _GradientFill(post: post);

    return Image.network(
      post.imageUrl!,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _GradientFill(post: post),
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : _GradientFill(post: post),
    );
  }
}

class _GradientFill extends StatelessWidget {
  const _GradientFill({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final colors = post.backgroundColors.isNotEmpty
        ? post.backgroundColors
        : const [AppColors.surfaceHigh, AppColors.surface];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(8),
      alignment: Alignment.center,
      child: Text(
        post.activity,
        textAlign: TextAlign.center,
        maxLines: 3,
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

class _ExploreMessage extends StatelessWidget {
  const _ExploreMessage({
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
    return Center(
      child: SingleChildScrollView(
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
              child: Icon(icon, size: 56, color: AppColors.orangeBright),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.white,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.white,
                  side: const BorderSide(color: AppColors.stroke),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
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
