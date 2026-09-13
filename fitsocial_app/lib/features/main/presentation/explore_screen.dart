import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/bottom_nav.dart';
import '../../../shared/widgets/post_summary_tile.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';
import '../domain/explore_models.dart';
import 'post_detail_sheet.dart';
import '../../music/presentation/music_island_action.dart';
import '../../races/application/race_providers.dart';
import '../../races/domain/race_formatting.dart';
import '../../../shared/widgets/liquid_glass.dart';

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
    final palette = context.palette;
    final query = ref.watch(userSearchQueryProvider);
    final isSearching = query.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore'),
        actions: const [MusicIslandAction()],
      ),
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
              style: TextStyle(color: palette.text),
              decoration: InputDecoration(
                hintText: 'Search people by name or handle',
                hintStyle: TextStyle(color: palette.muted),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: palette.muted,
                ),
                suffixIcon: isSearching || _controller.text.isNotEmpty
                    ? IconButton(
                        onPressed: _clear,
                        icon: Icon(
                          Icons.close_rounded,
                          color: palette.muted,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: palette.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  borderSide: BorderSide(color: palette.stroke),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  borderSide: BorderSide(color: palette.stroke),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  borderSide: BorderSide(color: palette.brand),
                ),
              ),
            ),
          ),
          // Hidden while searching: the box above searches people, and a race
          // banner sitting over a list of user results would read as one of
          // them.
          if (!isSearching) const _RaceCalendarBanner(),
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

/// The way into the running calendar.
///
/// Explore is where somebody comes to find something they are not already
/// following, which is exactly what a race calendar is for. It sits above the
/// trending grid rather than inside it because it is a destination, not a post.
class _RaceCalendarBanner extends ConsumerWidget {
  const _RaceCalendarBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final next = ref.watch(nextSavedRaceProvider);
    final now = ref.watch(raceClockProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: GestureDetector(
        // A saved race sends you to your own list, otherwise to the calendar.
        // Somebody with a goal race is checking on that race; somebody without
        // one is still looking for it.
        onTap: () => context.push(next == null ? '/races' : '/races/saved'),
        child: DarkCard(
          margin: EdgeInsets.zero,
          // A promo band using colour to mean something, so the colour goes
          // under the lens and arrives bent like every other card here.
          backdrop: GlassBloom(colors: [palette.brand]),
          child: Row(
            children: [
              Icon(
                Icons.event_available_rounded,
                size: 22,
                color: palette.brand,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      next == null ? 'Find a race' : next.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      next == null
                          ? 'Road, trail and ultra events across South Africa'
                          : '${RaceFormat.countdown(next, now) ?? 'Race day'} · '
                              '${next.venue.shortLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: palette.muted),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: palette.muted,
              ),
            ],
          ),
        ),
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
      loading: () => Center(
        child: CircularProgressIndicator(color: context.palette.brand),
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
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md + FitSocialBottomNav.clearance(context),
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
    final palette = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: () => context.push('/user/${user.id}'),
      child: LiquidGlass(
        // Painted by the lens rather than by a fill of its own: a pane
        // over the app backdrop, like every other card.
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.stroke),
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
                      style: TextStyle(color: palette.muted),
                    ),
                  ],
                ),
              ),
              Text(
                '${user.postsCount} ${user.postsCount == 1 ? 'post' : 'posts'}',
                style: TextStyle(color: palette.muted, fontSize: 13),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.muted),
            ],
          ),
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
    // The shared avatar, so a search result shows the same photo, monogram or
    // empty-profile glyph the person carries everywhere else. Search rows sit
    // on the plain page rather than on a card, and the hairline that separates
    // an avatar from a card would read as an outline here.
    return Avatar(
      initials: user.initials,
      size: size,
      imageUrl: user.avatarUrl,
      border: AvatarBorder.none,
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
      loading: () => Center(
        child: CircularProgressIndicator(color: context.palette.brand),
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
            message: 'Once the community starts posting, the workouts, runs '
                'and meals people are reacting to land here.',
          );
        }

        // Chips sit outside the scrollable so they stay reachable however far
        // down the grid the user has gone — switching category is the main
        // thing this screen is for, and burying it at the top would make it a
        // scroll-to-top-first action.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _FilterChipRow(),
            const SizedBox(height: AppSpacing.md),
            Expanded(child: _TrendingGrid(posts: posts)),
          ],
        );
      },
    );
  }
}

/// The category selector, pinned above the grid.
class _FilterChipRow extends ConsumerWidget {
  const _FilterChipRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(exploreFilterProvider);

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: ExploreFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final filter = ExploreFilter.values[index];
          return _FilterChip(
            filter: filter,
            isSelected: filter == selected,
            onTap: () =>
                ref.read(exploreFilterProvider.notifier).state = filter,
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.filter,
    required this.isSelected,
    required this.onTap,
  });

  final ExploreFilter filter;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? palette.brand : palette.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected ? palette.brand : palette.stroke,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconFor(filter),
              size: 15,
              // The selected pill is orange, so its contents go dark rather
              // than white — brand-on-brand would be unreadable. Fixed, not
              // themed: the pill is the same orange on the light theme, so
              // the page colour would put cream on orange there.
              color: isSelected ? AppColors.onBrandInk : palette.muted,
            ),
            const SizedBox(width: 6),
            Text(
              filter.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected ? AppColors.onBrandInk : palette.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(ExploreFilter filter) => switch (filter) {
        ExploreFilter.all => Icons.auto_awesome_rounded,
        ExploreFilter.runs => Icons.directions_run_rounded,
        ExploreFilter.workouts => Icons.fitness_center_rounded,
        ExploreFilter.meals => Icons.restaurant_rounded,
        ExploreFilter.photos => Icons.photo_camera_rounded,
      };
}

class _TrendingGrid extends ConsumerWidget {
  const _TrendingGrid({required this.posts});

  final List<FeedPost> posts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final filter = ref.watch(exploreFilterProvider);
    final visible = applyExploreFilter(posts, filter);

    if (visible.isEmpty) {
      return _ExploreMessage(
        icon: _FilterChip._iconFor(filter),
        title: 'No ${filter.label.toLowerCase()} trending',
        message: 'Nobody has posted a ${filter.label.toLowerCase()} that '
            'caught on yet. Try another category.',
        actionLabel: 'Show everything',
        onRetry: () =>
            ref.read(exploreFilterProvider.notifier).state = ExploreFilter.all,
      );
    }

    return RefreshIndicator(
      color: palette.brand,
      backgroundColor: palette.surface,
      onRefresh: () async => ref.invalidate(trendingPostsProvider),
      child: GridView.builder(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md + FitSocialBottomNav.clearance(context),
        ),
        // Always scrollable so the pull-to-refresh gesture still works when
        // the filtered set is short enough to fit on one screen.
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: visible.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.85,
        ),
        itemBuilder: (context, index) => _TrendingTile(post: visible[index]),
      ),
    );
  }
}

class _TrendingTile extends StatelessWidget {
  const _TrendingTile({required this.post});

  final FeedPost post;

  /// A photo wins the backdrop when there is one: whatever the author shot is
  /// more worth looking at than a rendering of what they wrote or measured.
  /// What the post *is* — the route, the numbers — is drawn over it either
  /// way, so a run reads as a run with or without a picture behind it.
  bool get _hasPhoto => post.imageUrl != null && post.imageUrl!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _hasPhoto;

    return GestureDetector(
      onTap: () => showPostDetailSheet(context, post),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.nested),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The same radius as the clip above, so the glass rim on a
            // summary tile lands on the edge the grid actually shows.
            if (hasPhoto)
              PostMediaTile(
                post: post,
                showAuthor: true,
                borderRadius: AppRadius.nested,
              )
            else
              PostSummaryTile(
                post: post,
                showAuthor: true,
                borderRadius: AppRadius.nested,
              ),
            // Both counts, not just likes: comments are weighted double in the
            // ranking, so a post sitting high on the strength of its replies
            // would otherwise look mysteriously placed.
            Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.sm,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (post.comments > 0) ...[
                    _CountPill(
                      icon: Icons.mode_comment_rounded,
                      count: post.comments,
                      onMedia: hasPhoto,
                    ),
                    const SizedBox(width: 4),
                  ],
                  _CountPill(
                    icon: Icons.favorite_rounded,
                    count: post.likes,
                    onMedia: hasPhoto,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.icon,
    required this.count,
    this.onMedia = true,
  });

  final IconData icon;
  final int count;

  /// Whether the pill sits over a photo or gradient. Over media it stays a
  /// dark plate with fixed contents in both themes; on an activity card it is
  /// part of the card and follows the palette, because a black lozenge on a
  /// cream tile reads as a hole in it.
  final bool onMedia;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: onMedia ? Colors.black54 : palette.surfaceHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            // The bright orange is tuned for fills and glyphs on black; at
            // 13px on cream it needs the heavier weight.
            color: onMedia ? AppColors.orangeBright : palette.brandText,
            size: 13,
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              color: onMedia ? AppColors.onMedia : palette.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
    this.actionLabel = 'Retry',
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  /// What the button says. Not every dead end is a failure to retry — an empty
  /// category is a filter to clear.
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.surfaceHigh,
              ),
              child: Icon(icon, size: 56, color: palette.brand),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: palette.text,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: palette.muted,
                height: 1.5,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.text,
                  side: BorderSide(color: palette.stroke),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.field),
                  ),
                ),
                onPressed: onRetry,
                child: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
