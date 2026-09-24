import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
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
import '../../../shared/widgets/glass_top_bar.dart';
import '../../../shared/widgets/post_card.dart';
import '../../notifications/application/notification_providers.dart';
import '../../pulse/presentation/pulse_tray.dart';
import 'comments_sheet.dart';
import '../../../shared/layout/tab_reselect.dart';
import '../../music/presentation/music_island_action.dart';
import '../../../shared/widgets/liquid_glass.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scroll = ScrollController();
  final _refreshIndicator = GlobalKey<RefreshIndicatorState>();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Home tapped while already on Home: back to the top, then a refresh.
  ///
  /// The refresh goes through the pull-to-refresh indicator rather than
  /// straight to [_refresh], so the spinner shows under the top bar exactly as
  /// it does when the feed is pulled — the same refresh, reached a second way.
  Future<void> _backToTopAndRefresh() async {
    if (_scroll.hasClients && _scroll.offset > 0) {
      // A long way down, most of the distance is skipped so the glide back is
      // one short movement rather than a long spin through every post.
      final screen = _scroll.position.viewportDimension;
      if (_scroll.offset > screen * 3) _scroll.jumpTo(screen * 1.5);
      await _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
    if (!mounted) return;
    await _refreshIndicator.currentState?.show();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(
      homeTabReselectProvider,
      (_, __) => _backToTopAndRefresh(),
    );
    final posts = ref.watch(feedPostsProvider);
    final rows = _rows(posts, ref);

    return Scaffold(
      // The top bar is glass, and glass needs the feed running underneath it —
      // the same bargain `extendBody` strikes for the nav at the other end.
      // The list pays for it in top padding, below.
      extendBodyBehindAppBar: true,
      appBar: GlassTopBar(
        title: const FitSocialLogo(size: 24, animated: false),
        actions: [
          const MusicIslandAction(),
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
      body: RefreshIndicator(
        key: _refreshIndicator,
        onRefresh: () => _refresh(ref),
        color: context.palette.brand,
        backgroundColor: context.palette.surface,
        // The list now starts at the top of the screen, so the default 40px
        // would drop the spinner behind the bar. Put it below the glass, where
        // it is the one thing on this screen that should not be refracted.
        displacement: GlassTopBar.clearance(context) + AppSpacing.sm,
        child: ListView.builder(
          controller: _scroll,
          // Without this the gesture is only available once the feed is long
          // enough to scroll — which is exactly when a stale feed is least
          // worth refreshing, and an empty one could never be recovered.
          physics: const AlwaysScrollableScrollPhysics(),
          // A screen and a half of read-ahead, against a default of 250px —
          // shorter than a single post. At the default a photo only starts
          // downloading as its card enters the viewport, which is what made
          // scrolling land on a spinner every time. Cards in the cache area are
          // laid out but not painted, so this buys the fetches a head start
          // without paying to draw anything nobody is looking at.
          scrollCacheExtent: const ScrollCacheExtent.viewport(1.5),
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            // Clears the glass top bar, which overlays this list now rather
            // than sitting above it — the mirror of the nav's clearance below.
            AppSpacing.sm + GlassTopBar.clearance(context),
            AppSpacing.md,
            // Clears the floating nav, which overlays this list rather than
            // sitting below it.
            AppSpacing.md + FitSocialBottomNav.clearance(context),
          ),
          itemCount: rows.length,
          itemBuilder: (context, index) => rows[index],
        ),
      ),
    );
  }

  /// Everything on this page that was read once and would otherwise stay as it
  /// was until the app is restarted.
  ///
  /// The Pulse tray and the bell are live queries and re-render themselves, so
  /// the pull only re-runs the one-shot reads: the feed itself, and the streak
  /// grid above it.
  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(activitySessionsProvider);
    await ref.read(feedPostsProvider.notifier).refresh();
  }

  /// Every row of the page, flat.
  ///
  /// Flat is the whole point. A sliver culls at the granularity of its own
  /// children, and nothing below one: the feed used to arrive as a single
  /// [Column] holding every post, which made it *one* child, taller than the
  /// screen, laid out and painted whole on every frame. Thirty posts scrolled
  /// like thirty posts even though three were visible.
  ///
  /// Handed the rows separately, the list builds and paints the handful in
  /// view and leaves the rest as data.
  List<Widget> _rows(AsyncValue<HomeFeed> posts, WidgetRef ref) {
    return [
      const PulseTray(),
      const SizedBox(height: AppSpacing.sm),
      // The current Mon-Sun week, pinned: the feed is somewhere to glance
      // at the streak, not somewhere to change the window.
      const ActivityGridCard(fixedRange: ActivityRange.week),
      const SizedBox(height: AppSpacing.sm),
      ...posts.when(
        data: (feed) => _buildFeed(feed, ref),
        loading: () => const [_SectionPlaceholder(label: 'Loading feed...')],
        error: (_, __) =>
            const [_SectionPlaceholder(label: 'Feed unavailable')],
      ),
    ];
  }

  List<Widget> _buildFeed(HomeFeed feed, WidgetRef ref) {
    if (feed.isEmpty) return const [_NothingPostedYet()];

    // Blended: the people they follow first, then a line, then the top-up.
    // The line is not decoration — without it a stranger's post reads as
    // somebody they followed and forgot about.
    if (feed.source == FeedSource.blended) {
      return [
        ..._buildPosts(feed.followedPosts, ref),
        const SizedBox(height: AppSpacing.sm),
        const _SuggestedHeader(isTopUp: true),
        const SizedBox(height: AppSpacing.sm),
        ..._buildPosts(feed.suggestedPosts, ref),
      ];
    }

    return [
      // Said out loud when these are not the people you follow, so a quiet
      // feed is never mistaken for a quiet community — or the other way
      // round.
      if (feed.source == FeedSource.suggested) ...[
        const _SuggestedHeader(),
        const SizedBox(height: AppSpacing.sm),
      ],
      ..._buildPosts(feed.posts, ref),
    ];
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
          mealData: post.mealData,
          routePoints: post.routePoints,
          showRouteMap: post.showRouteMap,
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
  const _SuggestedHeader({this.isTopUp = false});

  /// Whether this introduces a top-up below a real feed, rather than standing
  /// in for one.
  ///
  /// The two need different words. Above an empty feed the message is "you
  /// haven't followed anyone"; above a short one it is "you have, and here is
  /// more" — telling somebody who follows three people that they follow nobody
  /// is how a prompt starts getting ignored.
  final bool isTopUp;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.explore_outlined,
                  size: 18,
                  color: palette.brand,
                ),
                const SizedBox(width: 8),
                Text(
                  isTopUp ? 'More from FitSocial' : 'Suggested for you',
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
              isTopUp
                  ? "That's everything from the people you follow. Follow a few "
                      'more and this section shrinks.'
                  : 'Follow people and their posts land here first.',
              style:
                  TextStyle(color: palette.muted, fontSize: 13.5, height: 1.4),
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
              label: Text(isTopUp ? 'Find more people' : 'Find people'),
            ),
          ],
        ),
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

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xl,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: palette.brandSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bolt_rounded,
                color: palette.brand,
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
                foregroundColor: palette.brandText,
                side: BorderSide(color: palette.brand),
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
                color: context.palette.brand,
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
    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.stroke),
        ),
        child: Text(
          label,
          style: TextStyle(color: palette.muted),
        ),
      ),
    );
  }
}
