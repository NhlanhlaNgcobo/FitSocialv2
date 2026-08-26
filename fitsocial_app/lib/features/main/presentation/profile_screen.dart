import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../auth/application/app_session.dart';
import '../../auth/presentation/account_switcher_sheet.dart';
import '../../challenges/application/challenge_providers.dart';
import '../../challenges/presentation/badge_shelf.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';
import '../domain/explore_models.dart';
import '../../../shared/widgets/post_summary_tile.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/bottom_nav.dart';
import '../../../shared/widgets/profile_bio.dart';
import '../../../shared/widgets/profile_stats_bar.dart';
import '../../music/presentation/music_island_action.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    // A profile read that failed during launch leaves the session signed in
    // with nothing to render — a placeholder name and no bio. Opening this
    // page is the moment to ask again; a session that already has its profile
    // is left alone rather than re-read on every visit to the tab.
    final session = ref.read(appSessionProvider);
    if (session.profile == null) session.reloadProfile();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(appSessionProvider).profile;
    final userId = ref.watch(currentUserIdProvider);
    final displayName = profile?.displayName ?? 'FitSocial User';
    final bio = ProfileBio(
      bio: profile?.bio ?? '',
      pronouns: profile?.pronouns ?? '',
      location: profile?.location ?? '',
      links: profile?.links ?? '',
    );

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        // No app bar: the action bar below is the top of the screen, so the
        // status bar is the only thing to inset for.
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _TopActionBar(),
              const SizedBox(height: AppSpacing.sm),
              _ProfileHeader(
                displayName: displayName,
                handle: formatHandle(profile?.handle),
                avatarUrl: profile?.avatarUrl,
              ),
              const SizedBox(height: AppSpacing.lg),
              // Nothing to count before the uid resolves; the bar shows its
              // placeholder dashes rather than disappearing and reflowing.
              ProfileStatsBar(userId: userId ?? ''),
              // The widget knows whether it has anything to say; asking it is
              // what keeps this from having to test four fields itself.
              if (!bio.isEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                bio,
              ],
              // The badge case, above the grid. It draws nothing at all until
              // there is something in it, so a new account is not given an
              // empty trophy shelf to feel bad about.
              if (userId != null) ...[
                const SizedBox(height: AppSpacing.lg),
                _ProfileBadgeShelf(userId: userId),
              ],
              const SizedBox(height: AppSpacing.lg),
              const _SectionIndicator(),
              const Expanded(
                child: TabBarView(
                  children: [
                    // First tab is the photo grid — every photo except meals,
                    // which get their own tab; the rest filter the user's
                    // posts by what kind of activity they are.
                    _MediaGrid(mediaOnly: true),
                    _MediaGrid(filter: ExploreFilter.workouts),
                    _MediaGrid(filter: ExploreFilter.runs),
                    _MediaGrid(filter: ExploreFilter.meals),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The badges a user holds, between their bio and their grid.
///
/// A thin wrapper rather than the shelf used directly, so the provider is
/// watched here and the profile's own build is not rebuilt every time a badge
/// lands.
class _ProfileBadgeShelf extends ConsumerWidget {
  const _ProfileBadgeShelf({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(badgesProvider(userId)).valueOrNull ?? const [];
    if (badges.isEmpty) return const SizedBox.shrink();

    return BadgeShelf(
      badges: badges,
      onTap: (badge) => showBadgeSheet(context, badge),
    );
  }
}

/// Add-people on the left, the music island and settings on the right.
///
/// This screen has no AppBar of its own, so the island cannot ride in an
/// `actions` list the way it does everywhere else — it goes in this row
/// instead, in the same place: first of the right-hand cluster.
class _TopActionBar extends StatelessWidget {
  const _TopActionBar();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        children: [
          IconButton(
            // Finding people is what Explore is, so this switches branch
            // rather than pushing a second search on top of the profile.
            onPressed: () => context.go('/explore'),
            tooltip: 'Find people',
            color: palette.text,
            icon: const Icon(Icons.person_add_alt),
          ),
          const Spacer(),
          const MusicIslandAction(),
          IconButton(
            onPressed: () => context.push('/settings'),
            tooltip: 'Settings',
            color: palette.text,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }
}

/// Avatar, name and handle, stacked and centred.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.displayName,
    required this.handle,
    this.avatarUrl,
  });

  final String displayName;
  final String handle;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        _PulseAvatar(
          initials: accountInitials(displayName),
          imageUrl: avatarUrl,
        ),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The name can be long, the two controls beside it can't — so
              // the name is what gives way.
              Flexible(
                child: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => showAccountSwitcherSheet(context),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: palette.text,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _EditPill(onPressed: () => context.push('/edit-profile')),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            handle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.muted, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

class _EditPill extends StatelessWidget {
  const _EditPill({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: context.palette.brand,
        foregroundColor: AppColors.onBrand,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        minimumSize: Size.zero,
        // Without this the button keeps Material's 48px tap padding and the
        // pill stops sitting beside the name.
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      onPressed: onPressed,
      child: const Text('Edit'),
    );
  }
}

/// The profile photo with the add-a-Pulse badge on its lower-right edge.
class _PulseAvatar extends StatelessWidget {
  const _PulseAvatar({required this.initials, this.imageUrl});

  final String initials;
  final String? imageUrl;

  static const double _size = 84;
  static const double _badgeSize = 28;

  /// Transparent margin around the badge, so the tap target clears 44px
  /// without the orange dot having to be that large.
  static const double _badgePadding = 8;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Avatar(initials: initials, size: _size, imageUrl: imageUrl),
          Positioned(
            // Pulled out by the invisible padding so the badge itself still
            // sits just inside the circle's bounding box.
            right: 4 - _badgePadding,
            bottom: 4 - _badgePadding,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.push('/pulse-compose'),
              child: Padding(
                padding: const EdgeInsets.all(_badgePadding),
                child: Container(
                  width: _badgeSize,
                  height: _badgeSize,
                  decoration: BoxDecoration(
                    color: palette.brand,
                    shape: BoxShape.circle,
                    // Separates the badge from whatever it overlaps.
                    border: Border.all(color: palette.background, width: 2.5),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: AppColors.onBrand,
                    size: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows which profile section is on screen, without being a control.
///
/// Swiping is the way you move between sections, so this is deliberately an
/// indicator and not a tab bar: no ripple, no underline, no full-width divider.
/// Each section's icon is always present but dim and small; the one you're
/// viewing brightens and grows. Because it interpolates off the tab
/// controller's animation rather than its index, the transition tracks your
/// finger mid-swipe instead of snapping when the page settles.
class _SectionIndicator extends StatelessWidget {
  const _SectionIndicator();

  static const _icons = <IconData>[
    Icons.grid_view_rounded,
    Icons.fitness_center_rounded,
    Icons.directions_run_rounded,
    Icons.restaurant_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final controller = DefaultTabController.of(context);
    final animation = controller.animation;

    return AnimatedBuilder(
      // TabController is itself a Listenable, so it stands in on the rare
      // frame where the animation hasn't been attached yet.
      animation: animation ?? controller,
      builder: (context, _) {
        final position = animation?.value ?? controller.index.toDouble();
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _icons.length; i++)
                _icon(i, position, palette),
            ],
          ),
        );
      },
    );
  }

  Widget _icon(int index, double position, AppPalette palette) {
    // 1 when this section fills the screen, 0 once it's a full page away.
    final t = (1 - (position - index).abs()).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Icon(
        _icons[index],
        size: 15 + (5 * t),
        color: Color.lerp(
          palette.muted.withValues(alpha: 0.35),
          AppColors.orange,
          t,
        ),
      ),
    );
  }
}

/// Grid of the signed-in user's OWN posts, queried by `authorId`. New accounts
/// with no posts get an empty state — never mock/brand placeholder images.
class _MediaGrid extends ConsumerWidget {
  const _MediaGrid({this.mediaOnly = false, this.filter});

  /// Photo grid: query only posts that carry an uploaded image. Meal photos
  /// are left out of it — the Meals tab is where those live.
  final bool mediaOnly;

  /// Which kind of post this tab shows. Shared with Explore's chips rather
  /// than matched on the activity text, which is the user's own wording — a
  /// workout titled "Leg Day" and a meal called "Chicken salad" never
  /// contained the words this used to search for, so both tabs sat empty.
  final ExploreFilter? filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      return const _EmptyGrid(message: 'Sign in to see your posts.');
    }

    final posts = ref.watch(
      mediaOnly ? userMediaPostsProvider(userId) : userPostsProvider(userId),
    );

    return posts.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.brand),
      ),
      error: (_, __) => _ErrorGrid(
        onRetry: () => ref.invalidate(
          mediaOnly
              ? userMediaPostsProvider(userId)
              : userPostsProvider(userId),
        ),
      ),
      data: (all) {
        final activeFilter = filter;
        // Workouts, runs and meals each have a tab of their own, so the photo
        // grid leaves them out — a logged plate belongs under Meals, and the
        // backdrop behind a workout card belongs under Workouts with the
        // session it decorates, not repeated here as a bare picture.
        final visible = activeFilter != null
            ? applyExploreFilter(all, activeFilter)
            : all.where(ExploreFilterX.isPhotoPost).toList(growable: false);

        if (visible.isEmpty) {
          return _EmptyGrid(
            message: mediaOnly
                ? 'Photos you post will show up here.'
                : activeFilter == null
                    ? 'No posts yet. Share your first workout!'
                    : 'No ${activeFilter.label.toLowerCase()} shared yet.',
          );
        }

        return RefreshIndicator(
          color: palette.brand,
          backgroundColor: palette.surface,
          onRefresh: () async => ref.invalidate(
            mediaOnly
                ? userMediaPostsProvider(userId)
                : userPostsProvider(userId),
          ),
          child: GridView.builder(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md + FitSocialBottomNav.clearance(context),
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

/// A centred empty-or-error state for one of the grid tabs.
///
/// Two things the plain `Center` + `Padding` it replaces got wrong. It cleared
/// nothing at the bottom, so its last line sat behind the floating nav -- the
/// grid beside it has always padded by [FitSocialBottomNav.clearance] and these
/// never did. And it could not give way: a Column of a fixed size inside a tab
/// of a fixed size overflows the moment the second is the smaller, which on a
/// short screen it was, by a pixel and a half.
///
/// Centred while there is room, scrolling once there is not.
class _GridState extends StatelessWidget {
  const _GridState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl + FitSocialBottomNav.clearance(context),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _ErrorGrid extends StatelessWidget {
  const _ErrorGrid({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _GridState(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            color: palette.muted,
            size: 42,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            "Couldn't load your posts.",
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted, fontSize: 15),
          ),
          const SizedBox(height: AppSpacing.md),
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
      ),
    );
  }
}

/// A single post tile — a run's route, a workout's numbers, or what the author
/// wrote, drawn over their photo when they picked one and on a card when they
/// didn't.
class _PostTile extends StatelessWidget {
  const _PostTile({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final hasImage = post.imageUrl != null && post.imageUrl!.isNotEmpty;

    return GestureDetector(
      // Opaque so the gaps inside a summary tile are part of the target too;
      // the post rides along so the detail screen doesn't re-fetch what this
      // grid already loaded.
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/post/${post.id}', extra: post),
      // Three across is tight, hence compact; and a profile grid is one
      // person's work throughout, so nothing needs naming them.
      child: hasImage
          ? PostMediaTile(post: post, compact: true, borderRadius: 16)
          : PostSummaryTile(post: post, compact: true, borderRadius: 16),
    );
  }
}

class _EmptyGrid extends StatelessWidget {
  const _EmptyGrid({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _GridState(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.surfaceHigh,
            ),
            child: Icon(
              Icons.camera_alt_outlined,
              color: palette.brand,
              size: 48,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'No posts yet',
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
            style: TextStyle(color: palette.muted, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
