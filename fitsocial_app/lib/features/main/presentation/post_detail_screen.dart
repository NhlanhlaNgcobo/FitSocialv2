import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/identity/profile_identity.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/comment_composer.dart';
import '../../../shared/widgets/post_card.dart';
import '../../../shared/widgets/post_gradient.dart';
import '../../../shared/widgets/run_route_map.dart';
import '../../../shared/widgets/workout_summary_card.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';
import 'comments_sheet.dart';

/// A single post on its own page.
///
/// Deliberately *not* the feed card blown up: a card is a preview in a stack of
/// previews, and re-drawing it alone on a page left one bordered box floating in
/// a screen of empty background. Here the post owns the page — media runs edge
/// to edge, its numbers get room to be read, and the comments are the rest of
/// the page rather than a sheet you have to know to open.
///
/// Opened by tapping a tile in a profile grid, which already holds the post, so
/// [initialPost] renders immediately and [postProvider] is only consulted when
/// the screen was reached without one (a deep link, or a restart).
class PostDetailScreen extends ConsumerWidget {
  const PostDetailScreen({required this.postId, this.initialPost, super.key});

  final String postId;
  final FeedPost? initialPost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final post = initialPost;
    if (post != null) return _PostPage(post: post);

    return ref.watch(postProvider(postId)).when(
          loading: () => const _StatusScaffold(
            child: Center(
              child: CircularProgressIndicator(color: AppColors.orangeBright),
            ),
          ),
          error: (_, __) => _StatusScaffold(
            child: _Message(
              icon: Icons.cloud_off_rounded,
              title: "Couldn't load this post",
              message: 'Check your connection and try again.',
              onRetry: () => ref.invalidate(postProvider(postId)),
            ),
          ),
          data: (loaded) {
            if (loaded == null) {
              return const _StatusScaffold(
                child: _Message(
                  icon: Icons.hide_source_rounded,
                  title: 'Post not found',
                  message: 'It may have been deleted by its author.',
                ),
              );
            }
            return _PostPage(post: loaded);
          },
        );
  }
}

/// The page itself, once there is a post to draw.
class _PostPage extends ConsumerStatefulWidget {
  const _PostPage({required this.post});

  final FeedPost post;

  @override
  ConsumerState<_PostPage> createState() => _PostPageState();
}

class _PostPageState extends ConsumerState<_PostPage> {
  final _scrollController = ScrollController();
  final _composerFocus = FocusNode();

  @override
  void dispose() {
    _scrollController.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  /// The comment icon has nothing to open here — the comments are already on
  /// the page — so it does what the reader meant: puts them on screen and the
  /// cursor in the box.
  void _startCommenting() {
    _composerFocus.requestFocus();
    if (!_scrollController.hasClients) return;
    _scrollController
        .animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    )
        .then((_) {
      // The keyboard rose while that ran, so the bottom of the list is further
      // down than it was when the animation was planned for it.
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final post = widget.post;
    final media = _MediaKind.of(post);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('Post', style: TextStyle(fontSize: 18)),
        actions: [
          // The card's own overflow, moved to the bar: on a page the post has
          // no header of its own to hang a `⋯` off, and delete/share belong to
          // the whole screen anyway.
          PostMenuButton(
            postId: post.id,
            authorId: post.authorId,
            userName: post.userName,
            activity: post.activity.trim(),
            caption: post.caption,
            // Nothing left to show once the post is gone.
            onDeleted: () => context.pop(),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      // The Scaffold lifts this clear of the keyboard; SafeArea keeps it off
      // the gesture bar when the keyboard is down.
      bottomNavigationBar: SafeArea(
        top: false,
        child: CommentComposer(postId: post.id, focusNode: _composerFocus),
      ),
      body: ListView(
        controller: _scrollController,
        padding: EdgeInsets.zero,
        children: [
          _AuthorRow(post: post),
          if (media == _MediaKind.none)
            _TextHero(post: post)
          else
            _MediaBlock(post: post, kind: media),
          // A workout block already spells out its own duration and calories;
          // repeating them as pills underneath is the same numbers twice.
          if (post.metricLabels.isNotEmpty && media != _MediaKind.workout)
            _MetricStrip(labels: post.metricLabels),
          const SizedBox(height: AppSpacing.xs),
          PostInteractionRow(
            postId: post.id,
            likes: post.likes,
            comments: post.comments,
            // Aligns the glyphs with the page gutter — the icons carry 10px of
            // their own padding for the touch target.
            horizontalPadding: AppSpacing.md - 10,
            iconSize: 24,
            onCommentTapped: _startCommenting,
          ),
          if (media != _MediaKind.none) _Caption(post: post),
          _Timestamp(post: post),
          const _SectionRule(),
          _CommentList(postId: post.id),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// What a post has to show between its header and its actions.
enum _MediaKind {
  photo,
  route,
  workout,

  /// Words only — the caption becomes the hero instead.
  none;

  static _MediaKind of(FeedPost post) {
    // A route outranks the type, exactly as the feed card decides it: a run is
    // drawn as its map whether or not it was stamped PostType.run.
    if (post.routePoints.length >= 2) return _MediaKind.route;
    if (post.imageUrl != null && post.imageUrl!.isNotEmpty) {
      return _MediaKind.photo;
    }
    if (post.workoutData != null || post.postType == PostType.workout) {
      return _MediaKind.workout;
    }
    return _MediaKind.none;
  }
}

/// Avatar, author and what they did — and, for anyone else's post, the way
/// through to their profile.
class _AuthorRow extends ConsumerWidget {
  const _AuthorRow({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final activity = post.activity.trim();
    // Your own name leads nowhere useful — this page was opened *from* your
    // profile — so it isn't dressed up as a link.
    final isSelf = ref.watch(currentUserIdProvider) == post.authorId;

    final row = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Avatar(
            initials: avatarInitials(post.userName),
            size: 44,
            imageUrl: post.authorAvatarUrl,
          ),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  post.userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    height: 1.2,
                  ),
                ),
                if (activity.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    activity,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      color: palette.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!isSelf)
            Icon(Icons.chevron_right_rounded, color: palette.muted, size: 22),
        ],
      ),
    );

    if (isSelf) return row;
    return InkWell(
      onTap: () => context.push('/user/${post.authorId}'),
      child: row,
    );
  }
}

/// The photo, the run map or the workout block — whichever this post carries.
///
/// Photos and maps run to both edges of the screen. There is only one post
/// here, so a margin around the media would frame it as a card in a list it
/// isn't in.
class _MediaBlock extends StatelessWidget {
  const _MediaBlock({required this.post, required this.kind});

  final FeedPost post;
  final _MediaKind kind;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case _MediaKind.route:
        return RunRouteMap(
          route: post.routePoints
              .map((point) => LatLng(point.latitude, point.longitude))
              .toList(growable: false),
          mode: RunRouteMapMode.completed,
          // Taller than the feed's preview: on this page the route is the
          // subject, not a thumbnail of one.
          height: 280,
        );
      case _MediaKind.photo:
        return _Photo(post: post);
      case _MediaKind.workout:
        return WorkoutSummaryCard(
          workoutData: post.workoutData,
          activity: post.activity,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        );
      case _MediaKind.none:
        return const SizedBox.shrink();
    }
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    // The shape the user cropped to, clamped to Instagram's legal range so a
    // malformed value can't produce an absurdly tall card. Square is the
    // fallback for posts saved before the ratio was recorded.
    final ratio = (post.imageAspectRatio ?? 1.0).clamp(0.8, 1.91);

    return AspectRatio(
      aspectRatio: ratio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The post's own gradient sits behind the photo, so the space is
          // never a blank hole while the image loads.
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: post.backgroundColors,
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Image.network(
            post.imageUrl!,
            fit: BoxFit.cover,
            // Both fallbacks land on the dark gradient behind the photo, not
            // on the page, so they take the on-media register.
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
          // No metrics burnt over the photo here: the strip below the image
          // says the same numbers where they can actually be read.
        ],
      ),
    );
  }
}

/// A post with nothing but words, drawn on its own gradient.
///
/// The feed sets a text post as a plain paragraph, which is right in a column
/// of cards. Alone on a page that is a sentence adrift in empty space, so here
/// the words get the panel the photo would have had.
class _TextHero extends StatelessWidget {
  const _TextHero({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    if (post.caption.trim().isEmpty) return const SizedBox.shrink();
    final palette = context.palette;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      constraints: const BoxConstraints(minHeight: 150),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: postGradientColors(post.backgroundColors, palette),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: palette.stroke),
      ),
      child: Text(
        post.caption,
        style: TextStyle(
          color: postGradientTextColor(palette),
          fontSize: 19,
          height: 1.45,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The post's measured numbers as a row of pills — distance, time, pace, or a
/// meal's macros.
///
/// The feed stamps these across the bottom of the photo, where they compete
/// with the picture. On the page they get their own line, split into a bold
/// value over its quiet unit.
class _MetricStrip extends StatelessWidget {
  const _MetricStrip({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(child: _MetricPill(label: labels[i])),
          ],
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label});

  /// One stored label, e.g. `5.23 km`, `28:14`, `32g protein`.
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Everything up to the first space is the number; the rest is its unit.
    // A label with no space (a duration, "28:14") is all value and no unit.
    final split = label.trim().indexOf(' ');
    final value = split == -1 ? label.trim() : label.substring(0, split);
    final unit = split == -1 ? '' : label.substring(split + 1).trim();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.stroke),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: palette.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
          if (unit.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              unit,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.muted,
                fontSize: 11.5,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Username in semibold followed by the caption — the same sentence the feed
/// card sets, one step larger because this is the reading copy of the post.
class _Caption extends StatelessWidget {
  const _Caption({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    if (post.caption.trim().isEmpty) return const SizedBox.shrink();
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 2, AppSpacing.md, 0),
      // RichText, unlike Text, inherits nothing — the root span has to name
      // the colour itself.
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            color: palette.text,
          ),
          children: [
            TextSpan(
              text: post.userName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const TextSpan(text: '  '),
            TextSpan(text: post.caption),
          ],
        ),
      ),
    );
  }
}

/// Age of the post, the quietest line on the page.
class _Timestamp extends StatelessWidget {
  const _Timestamp({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 10, AppSpacing.md, 0),
      child: Text(
        post.timestamp,
        style: TextStyle(fontSize: 12, color: context.palette.muted),
      ),
    );
  }
}

/// Hairline between the post and its conversation.
class _SectionRule extends StatelessWidget {
  const _SectionRule();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      color: context.palette.stroke,
    );
  }
}

/// The post's comments, live.
///
/// Read straight from the stream rather than the cached future, so a comment
/// written in the box at the bottom of this page appears above it without a
/// refresh — and so does anyone else's.
class _CommentList extends ConsumerWidget {
  const _CommentList({required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final commentsAsync = ref.watch(commentsStreamProvider(postId));

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Comments',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${commentsAsync.valueOrNull?.length ?? ''}',
                style: TextStyle(color: palette.muted, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          commentsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: AppColors.orangeBright,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
            error: (_, __) => Text(
              "Couldn't load comments.",
              style: TextStyle(color: palette.muted, fontSize: 14),
            ),
            data: (comments) {
              if (comments.isEmpty) {
                return Text(
                  'No comments yet. Be the first to say something.',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 14,
                    height: 1.5,
                  ),
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < comments.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.md),
                    CommentTile(comment: comments[i]),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The app bar the loading and error states share with the real page, so the
/// back button is in the same place whatever the screen is doing.
class _StatusScaffold extends StatelessWidget {
  const _StatusScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(title: const Text('Post', style: TextStyle(fontSize: 18))),
      body: child,
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
