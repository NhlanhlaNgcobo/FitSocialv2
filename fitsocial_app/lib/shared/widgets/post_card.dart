import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/auth/application/app_session.dart';
import '../../features/main/application/content_providers.dart';
import '../../features/main/data/content_repository.dart';
import '../../features/main/domain/app_models.dart';
import '../../features/main/domain/shared_post.dart';
import '../identity/profile_identity.dart';
import 'avatar.dart';
import 'confirm_destructive_sheet.dart';
import 'liquid_glass.dart';
import 'mention_text.dart';
import 'profile_link.dart';
import 'quick_toast.dart';
import 'reaction_bar.dart';
import 'run_summary_card.dart';
import 'share_sheet.dart';
import 'workout_summary_card.dart';

class PostCard extends StatelessWidget {
  const PostCard({
    required this.postId,
    required this.authorId,
    required this.userName,
    required this.activity,
    required this.caption,
    required this.metricLabels,
    required this.timestamp,
    this.likes = 0,
    this.comments = 0,
    this.backgroundColors = const [Color(0xFF332113), Color(0xFF0E0E0E)],
    this.onCommentTapped,
    this.onDeleted,
    this.postType = PostType.text,
    this.imageUrl,
    this.workoutData,
    this.routePoints = const [],
    this.authorAvatarUrl,
    this.imageAspectRatio,
    this.taggedUsers = const [],
    super.key,
  });

  final String postId;

  /// Uid of the post's author, used to decide whether the viewer may delete it.
  final String authorId;
  final String userName;
  final String activity;
  final String caption;
  final List<String> metricLabels;
  final String timestamp;
  final int likes;
  final int comments;
  final List<Color> backgroundColors;
  final VoidCallback? onCommentTapped;

  /// Called once the post has actually been deleted. A card inside a list can
  /// ignore this — the list reloads without it — but a screen that exists to
  /// show this one post has to close itself.
  final VoidCallback? onDeleted;

  final PostType postType;
  final String? imageUrl;
  final Map<String, dynamic>? workoutData;

  /// Completed run route. When non-empty the card renders a map preview of the
  /// finished run instead of the plain gradient tile.
  final List<RoutePoint> routePoints;

  /// Author's profile photo, denormalised onto the post. Null falls back to
  /// the initials avatar.
  final String? authorAvatarUrl;

  /// width / height of [imageUrl] as the user cropped it. Null falls back to
  /// square rather than re-cropping the photo to a fixed shape.
  final double? imageAspectRatio;

  /// People the author attached to the post, drawn as a "with @…" line under
  /// the header. Empty on every post nobody was tagged in.
  final List<TaggedUser> taggedUsers;

  /// A polyline needs at least two fixes; a single point is not a route.
  bool get _hasRoute => routePoints.length >= 2;

  /// Whether this post is a run. A route outranks the type, the way it does
  /// everywhere else: a run tracked before [PostType.run] existed was stamped
  /// `text` and is recognisable only by its trace.
  bool get _isRun => postType == PostType.run || _hasRoute;

  /// Whether there is a run card to draw — a shape to show, a photo to show it
  /// on, or both. A run with neither is words, and renders as words.
  bool get _hasRunCard => _isRun && (_hasRoute || imageUrl != null);

  /// This post in the form the share flows want it — the sheet, the Pulse
  /// card, and the link all read from one snapshot.
  SharedPostRef get _shareRef => SharedPostRef.of(
        postId: postId,
        authorId: authorId,
        authorName: userName,
        authorAvatarUrl: authorAvatarUrl,
        activity: activity,
        caption: caption,
        imageUrl: imageUrl,
        aspectRatio: imageAspectRatio,
        route: routePoints,
        hasWorkout: workoutData != null || postType == PostType.workout,
      );

  /// Whether there is anything to draw between the header and the actions.
  ///
  /// Keyed off what the post actually carries rather than what its type
  /// promises, so a manually entered run — typed `run`, but with no GPS trace
  /// and no photo — reads as a text post instead of reserving an empty band.
  bool get _hasPayload =>
      _hasRoute ||
      imageUrl != null ||
      workoutData != null ||
      postType == PostType.workout;

  @override
  Widget build(BuildContext context) {
    // One layout for every post type. The header — and therefore the avatar —
    // sits in exactly the same place whether the post carries a photo, a run
    // map, a workout card or nothing but text. Only the body swaps: media posts
    // put their caption below the actions (Instagram), text posts put the words
    // where the media would have been.
    //
    // Everything lives inside one rounded block a step off the app background,
    // so each post reads as a discrete card against the feed.
    final palette = context.palette;

    return Container(
      decoration: BoxDecoration(
        // No fill. The card is a pane of glass over the shell's backdrop, and
        // an opaque surface here would be the one thing standing between the
        // lens and anything worth bending. The hairline stays: it is what
        // separates one post from the next.
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: palette.stroke),
        // Drawn out here rather than inside the clip, which would cut away the
        // shadow the shape is casting. Dark mode's is transparent — there a
        // post separates from the page by a lit rim instead.
        boxShadow: [
          BoxShadow(
            color: palette.paneShadow,
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      // Media runs to the card's edges, so the card does the rounding for it.
      clipBehavior: Clip.antiAlias,
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(_cardRadius),
        // The Container already clips to this shape.
        clip: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(palette),
            if (taggedUsers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(_gutter, 0, _gutter, 8),
                child: TaggedUsersLine(tagged: taggedUsers),
              ),
            if (_hasPayload)
              _buildPayload(palette)
            else
              _buildBodyText(palette),
            PostInteractionRow(
              post: _shareRef,
              likes: likes,
              comments: comments,
              onCommentTapped: onCommentTapped,
            ),
            // A text post's words are already the body, so there's no caption
            // line to repeat underneath.
            if (_hasPayload) _buildCaption(palette),
            _buildCommentLink(palette),
            _buildTimestamp(palette),
          ],
        ),
      ),
    );
  }

  /// The words of a text-only post, set to Threads' body metrics: 15px on a
  /// 21px line box. Sits at the gutter, aligned with the caption and the
  /// username above it, so the left edge of every post's content lines up.
  Widget _buildBodyText(AppPalette palette) {
    if (caption.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 0, _gutter, 2),
      child: MentionText(
        text: caption,
        style: TextStyle(
          fontSize: 15,
          height: 21 / 15,
          color: palette.text,
        ),
      ),
    );
  }

  /// Horizontal inset for everything except the media, which runs edge to edge.
  static const double _gutter = 14;

  /// Corner radius of the card block.
  static const double _cardRadius = 18;

  /// Name over activity subtitle on the left, overflow menu on the right.
  ///
  /// The avatar and the name are one tap target rather than two: they name the
  /// same person, and a 14px line of text on its own is a thin thing to hit.
  /// The overflow button stays outside it so the menu is still reachable.
  Widget _buildHeader(AppPalette palette) {
    final subtitle = activity.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 10, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: ProfileLink(
              userId: authorId,
              child: Row(
                children: [
                  Avatar(
                    initials: avatarInitials(userName),
                    size: 34,
                    imageUrl: authorAvatarUrl,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            height: 1.2,
                          ),
                        ),
                        // Only rendered when the author wrote one — an absent
                        // subtitle leaves a single centred name rather than a
                        // blank second line.
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.2,
                              color: palette.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          PostMenuButton(
            post: _shareRef,
            onDeleted: onDeleted,
          ),
        ],
      ),
    );
  }

  /// "View all 12 comments" — the tap target that opens the same sheet as the
  /// comment icon. Hidden when there is nothing to view.
  Widget _buildCommentLink(AppPalette palette) {
    if (comments <= 0) return const SizedBox.shrink();
    final label =
        comments == 1 ? 'View 1 comment' : 'View all $comments comments';

    return GestureDetector(
      onTap: onCommentTapped,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_gutter, 6, _gutter, 0),
        child: Text(
          label,
          style: TextStyle(fontSize: 13, color: palette.muted),
        ),
      ),
    );
  }

  /// Age of the post, the quietest line on the card and always its last.
  Widget _buildTimestamp(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 6, _gutter, 12),
      child: Text(
        timestamp,
        style: TextStyle(fontSize: 11.5, color: palette.muted),
      ),
    );
  }

  /// Username in semibold followed by the caption on the same line — the
  /// Instagram convention, and it reads as one sentence rather than a header.
  Widget _buildCaption(AppPalette palette) {
    if (caption.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 6, _gutter, 0),
      child: MentionText(
        text: caption,
        leadingName: userName,
        leadingUserId: authorId,
        style: TextStyle(
          fontSize: 14,
          height: 1.35,
          color: palette.text,
        ),
        leadingStyle: TextStyle(
          fontSize: 14,
          height: 1.35,
          color: palette.text,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Selects the correct visual payload based on [postType].
  Widget _buildPayload(AppPalette palette) {
    // A run outranks the type and outranks its photo: the photo is a backdrop
    // for the run's shape and its numbers, not a photo post.
    if (_hasRunCard) return _buildRunPayload();

    switch (postType) {
      // A meal is a photo of food, so it renders as one.
      case PostType.image:
      case PostType.meal:
        return _buildImagePayload(palette);
      case PostType.workout:
        return _buildWorkoutPayload();
      // A run with no route has nothing to draw; _hasPayload has already
      // routed it to the text body.
      case PostType.run:
      case PostType.text:
        return _buildTextPayload();
    }
  }

  // ── RUN payload (the route as a line, on the runner's own photo) ──────────

  Widget _buildRunPayload() {
    return RunSummaryCard(
      route: routePoints,
      distanceLabel: RunSummaryCard.distanceFrom(metricLabels),
      durationLabel: RunSummaryCard.durationFrom(metricLabels),
      background: imageUrl == null ? null : NetworkImage(imageUrl!),
      margin: const EdgeInsets.symmetric(horizontal: _gutter),
    );
  }

  // ── TEXT payload (original gradient tile) ──────────────────────────────────

  Widget _buildTextPayload() {
    return const SizedBox.shrink();
  }

  // ── IMAGE payload (AspectRatio 4:5 clamped) ───────────────────────────────

  Widget _buildImagePayload(AppPalette palette) {
    // Render at the shape the user cropped to. Clamped to Instagram's legal
    // range so a malformed value can't produce an absurdly tall or wide card;
    // square is the fallback for posts saved before the ratio was recorded.
    final ratio = (imageAspectRatio ?? 1.0).clamp(0.8, 1.91);

    return AspectRatio(
      aspectRatio: ratio,
      child: ClipRRect(
        // Square corners: media runs edge to edge, so rounding would read as
        // an inset card rather than a continuous feed.
        borderRadius: BorderRadius.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Gradient background while image loads
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: backgroundColors,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            if (imageUrl != null)
              Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                // Both fallbacks land on the dark gradient behind the photo,
                // not on the card, so they take the on-media register.
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(
                    Icons.broken_image_rounded,
                    color: AppColors.onMediaMuted,
                    size: 48,
                  ),
                ),
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!
                          : null,
                      color: AppColors.orangeBright,
                      strokeWidth: 2,
                    ),
                  );
                },
              ),
            // Bottom gradient overlay for metric labels
            if (metricLabels.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Color(0xCC050505),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _metricDivider(),
                      _metricRow(),
                    ],
                  ),
                ),
              ),
            // No activity badge over the photo: the activity now reads as the
            // subtitle under the author's name, and repeating it on the media
            // was the same words twice.
          ],
        ),
      ),
    );
  }

  // ── WORKOUT payload (a tinted block of structured data) ───────────────────

  Widget _buildWorkoutPayload() {
    return WorkoutSummaryCard(
      workoutData: workoutData,
      activity: activity,
      // A workout's photo is a backdrop for its numbers, not a photo post — so
      // it goes behind the summary rather than replacing it.
      backgroundImageUrl: imageUrl,
      margin: const EdgeInsets.symmetric(horizontal: _gutter),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  Widget _metricDivider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            Color(0x66FFFFFF),
            Colors.transparent,
          ],
        ),
      ),
    );
  }

  Widget _metricRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: metricLabels
          .map(
            (metric) => Expanded(
              child: Text(
                metric,
                style: const TextStyle(
                  // Explicit, and deliberately not the theme's foreground:
                  // this sits on the photo's dark scrim, which does not change
                  // with the theme. Inheriting would put black text on it in
                  // light mode.
                  color: AppColors.onMedia,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  shadows: [
                    Shadow(
                      color: Colors.black45,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Like, comment and save for one post.
///
/// Public because the post detail page draws the same three controls without
/// drawing a [PostCard] around them — one implementation of "what a like does"
/// is the whole point.
class PostInteractionRow extends ConsumerWidget {
  const PostInteractionRow({
    required this.post,
    required this.likes,
    required this.comments,
    this.onCommentTapped,
    this.horizontalPadding = PostCard._gutter - 10,
    this.iconSize = 22,
    super.key,
  });

  /// The post being acted on. A snapshot rather than an id because the share
  /// glyph needs the whole thing — see [showPostShareSheet].
  final SharedPostRef post;
  final int likes;
  final int comments;
  final VoidCallback? onCommentTapped;

  String get postId => post.postId;

  /// Inset of the row itself. The default lines the *glyphs* up with the card's
  /// gutter — the icons carry 10px of their own padding for the touch target.
  final double horizontalPadding;

  /// Size of the glyphs. The detail page runs a step larger, where the row is
  /// the page's primary control rather than one line on a card in a feed.
  final double iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Treated as "not reacted yet" while it loads, so the row is usable from
    // the first frame instead of showing a spinner where a control should be.
    final reaction = ref.watch(postReactionProvider(postId)).valueOrNull;
    final isBookmarked =
        ref.watch(postBookmarkStatusProvider(postId)).valueOrNull ?? false;
    final palette = context.palette;

    // Like, comment and share cluster on the left, save alone on the right —
    // Instagram's arrangement, and the one people already reach for without
    // looking. Counts sit inline with their icon rather than on a separate
    // line, which keeps the card short and the layout identical for text and
    // media posts.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        children: [
          // Tap gives 🧡, hold opens the seven. Only a reaction actually given
          // takes colour; everything at rest is muted, so the row stays quiet
          // until the user acts.
          PostReactionIcon(
            selected: reaction,
            count: likes,
            size: iconSize,
            restingColor: palette.muted,
            onChanged: (picked) async {
              final userId = FirebaseAuth.instance.currentUser?.uid;
              if (userId == null) return;
              await ref.read(contentRepositoryProvider).setPostReaction(
                    postId,
                    userId,
                    picked,
                    // Names the reactor on the notification the post's author
                    // receives, from the profile the session already holds.
                    profile: ref.read(appSessionProvider).profile,
                  );
            },
          ),
          _ActionIcon(
            icon: Icons.mode_comment_outlined,
            color: palette.muted,
            count: comments,
            size: iconSize,
            onTap: onCommentTapped,
          ),
          _ActionIcon(
            // The paper plane, not the platform's share glyph: this opens
            // FitSocial's own options first — Pulse among them — and only
            // reaches the OS sheet if that is what the user picks.
            icon: Icons.send_outlined,
            color: palette.muted,
            size: iconSize,
            onTap: () => showPostShareSheet(context, post),
          ),
          const Spacer(),
          _ActionIcon(
            icon: isBookmarked
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            color: isBookmarked ? palette.brand : palette.muted,
            size: iconSize,
            onTap: () async {
              final userId = FirebaseAuth.instance.currentUser?.uid;
              if (userId == null) return;
              await ref
                  .read(contentRepositoryProvider)
                  .toggleBookmark(postId, userId);
            },
          ),
        ],
      ),
    );
  }
}

/// What the `⋯` sheet offers, which depends on whose post it is.
enum _PostMenuAction { delete, share }

/// The `⋯` overflow on a post.
///
/// Share is offered on every post including your own — you share your own work
/// more than anyone else's — and the author additionally gets Delete.
///
/// Public so the detail page can hang the identical menu off its app bar
/// instead of shipping a second delete flow.
class PostMenuButton extends ConsumerWidget {
  const PostMenuButton({
    required this.post,
    this.onDeleted,
    super.key,
  });

  final VoidCallback? onDeleted;

  /// The post this menu acts on, in the form the share flow needs it. Carries
  /// the author id the delete check reads, so there is one snapshot here
  /// rather than five loose strings.
  final SharedPostRef post;

  String get postId => post.postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      onPressed: () => _showMenu(context, ref),
      visualDensity: VisualDensity.compact,
      icon:
          Icon(Icons.more_horiz_rounded, color: context.palette.text, size: 22),
    );
  }

  Future<void> _showMenu(BuildContext context, WidgetRef ref) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isAuthor = uid != null && uid == post.authorId;
    final palette = context.palette;

    final action = await showModalBottomSheet<_PostMenuAction>(
        context: context,
        backgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) => LiquidGlass(
              // A sheet always has a page behind it, which makes it the one
              // surface in the app guaranteed something worth bending.
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: palette.stroke,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    ListTile(
                      leading:
                          Icon(Icons.ios_share_rounded, color: palette.text),
                      title: Text(
                        'Share post',
                        style: TextStyle(
                          color: palette.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () =>
                          Navigator.of(sheetContext).pop(_PostMenuAction.share),
                    ),
                    if (isAuthor)
                      ListTile(
                        leading: Icon(Icons.delete_outline_rounded,
                            color: palette.danger),
                        title: Text(
                          'Delete post',
                          style: TextStyle(
                            color: palette.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () => Navigator.of(sheetContext)
                            .pop(_PostMenuAction.delete),
                      ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),
            ));

    if (action == null || !context.mounted) return;
    if (action == _PostMenuAction.share) {
      await showPostShareSheet(context, post);
      return;
    }

    // Deleting is irreversible and removes the comments with it, so it gets an
    // explicit confirmation rather than relying on the sheet as the only gate.
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Delete post?',
      message: 'This permanently removes the post, its photo and all of its '
          'comments. It cannot be undone.',
      confirmLabel: 'Delete post',
    );

    if (!confirmed || !context.mounted) return;

    // [onDeleted] pops the detail route, which disposes this widget and its
    // [ref] with it. Everything the delete needs is therefore read *before*
    // that happens: the container and the root overlay both outlive the route.
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = container.read(contentRepositoryProvider);
    final feed = container.read(feedPostsProvider.notifier);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);

    // The card goes and the toast lands the instant the user confirms, rather
    // than after a Firestore round trip — the write is going to succeed
    // essentially always, and waiting on it makes deleting feel broken on a
    // slow connection. The catch below is the price: if the write does fail,
    // the feed is refetched and the post comes back alongside the error.
    feed.removePost(postId);
    if (overlay != null) {
      showQuickToastOn(overlay, 'Post deleted', tone: ToastTone.success);
    }
    onDeleted?.call();

    try {
      await repository.deletePost(postId);
      // The feed holds its posts in memory and drops this one above; the
      // profile grids are cached reads and would keep showing the tile until
      // something forced them to re-query.
      container
        ..invalidate(userPostsProvider)
        ..invalidate(userMediaPostsProvider)
        ..invalidate(profileStatsProvider);
    } catch (_) {
      // Put the post back before saying anything, so the message doesn't point
      // at a card that is no longer on screen.
      await feed.refresh();
      if (overlay == null) return;
      showQuickToastOn(
        overlay,
        'Could not delete post',
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
        visibleFor: const Duration(milliseconds: 2200),
      );
    }
  }
}

/// A feed action: a light outlined glyph with its count beside it.
///
/// Kept deliberately plain — no fill, no background, 20px stroke icons — so the
/// row recedes and the content stays the loudest thing on screen.
class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.color,
    this.count = 0,
    this.size = 22,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final int count;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        // Vertical padding gives a 44px touch target without the visual bulk
        // of an IconButton's default 48px box.
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: size),
            if (count > 0) ...[
              const SizedBox(width: 6),
              // The count stays the plain foreground whatever the icon is
              // doing — an orange number beside an active heart reads as part
              // of the glyph.
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
