import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/main/domain/activity_kind.dart';
import '../../features/main/domain/app_models.dart';
import '../../features/main/domain/explore_models.dart';
import 'app_photo.dart';
import 'liquid_glass.dart';
import 'route_sparkline.dart';

/// What kind of post a tile is showing. Drives the glyph and what the body
/// leads with — nothing else.
enum _PostKind { run, workout, meal, text }

/// [ExploreFilterX] owns the kind checks because it already has to recognise
/// the posts written before the types existed. Order matters: a workout writes
/// a '0 kcal' metric of its own, so it has to be claimed before anything asks
/// whether this is a meal.
_PostKind _kindOf(FeedPost post) {
  if (ExploreFilterX.isWorkout(post)) return _PostKind.workout;
  if (ExploreFilterX.isRun(post)) return _PostKind.run;
  if (ExploreFilterX.isMeal(post)) return _PostKind.meal;
  return _PostKind.text;
}

/// The glyph for a tile.
///
/// [_PostKind.run] covers every GPS activity, because that is how the post
/// types are written — a hike and a ride are both `postType: 'run'` on the
/// wire, which is what keeps the feed, Explore and notifications working
/// unchanged. The post's `activity` label is the only thing that tells them
/// apart, so the glyph is taken from there rather than from the kind.
IconData _iconFor(_PostKind kind, FeedPost post) => switch (kind) {
      _PostKind.run => _activityIconFor(post.activity),
      _PostKind.workout => Icons.fitness_center_rounded,
      _PostKind.meal => Icons.restaurant_rounded,
      _PostKind.text => Icons.format_quote_rounded,
    };

/// Matches a post's display label to an activity, defaulting to the running
/// glyph — which is correct for every run post written before hikes and rides
/// existed, and for anything unrecognised.
IconData _activityIconFor(String? activity) {
  final label = activity?.trim().toLowerCase();
  if (label == null || label.isEmpty) return Icons.directions_run_rounded;
  for (final kind in ActivityDescriptor.gpsKinds) {
    if (kind.descriptor.singular.toLowerCase() == label) {
      return kind.descriptor.icon;
    }
  }
  return Icons.directions_run_rounded;
}

/// A post's measurements, cleaned of the blanks the older logs wrote.
List<String> _metricsOf(FeedPost post) => post.metricLabels
    .map((label) => label.trim())
    .where((label) => label.isNotEmpty)
    .toList(growable: false);

/// Carries text across the one photo that is bright exactly where it sits.
/// The scrim handles the rest.
const List<Shadow> _mediaTextShadows = [
  Shadow(color: Color(0x73050505), blurRadius: 10, offset: Offset(0, 2)),
];

/// The tile a post gets in a grid when there is no photo to show.
///
/// Every grid in the app used to fall back to the post's stored gradient here:
/// a muddy orange rectangle with the activity's name printed on it, repeated
/// down the column, saying nothing about any of the posts behind it. Those
/// colour pairs were mixed for the dark app and describe nothing about a post,
/// so this drops them for a pane of the app's glass instead — a quiet card
/// over the backdrop, with the post's own content as the only thing on it
/// worth looking at.
///
/// What "content" means depends on the post. A GPS run has a shape; a workout
/// and a meal have numbers; a written post has its words. Each leads with its
/// own and falls back gracefully when it is missing, because a tile that
/// renders empty is worse than one that repeats itself.
///
/// Shared by Explore's two-across grid and the profile grids, which are three
/// across and half the size — hence [compact].
class PostSummaryTile extends StatelessWidget {
  const PostSummaryTile({
    required this.post,
    this.showAuthor = false,
    this.compact = false,
    this.borderRadius = 18,
    super.key,
  });

  final FeedPost post;

  /// Whether to name the author. Explore mixes everyone together and needs it;
  /// a profile grid is one person's work throughout and does not.
  final bool showAuthor;

  /// The three-across treatment: smaller type, fewer lines. At that size the
  /// choice is between a legible headline and an illegible full read-out.
  final bool compact;

  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final kind = _kindOf(post);
    final metrics = _metricsOf(post);

    // A run with a trace shows the trace. Everything else leads with what it
    // has: the headline number for a workout, a meal or a hand-typed run, and
    // for a written post the words themselves.
    final hasRoute =
        kind == _PostKind.run && RouteSparkline.canDraw(post.routePoints);
    final headline = metrics.isEmpty ? null : metrics.first;
    final words = post.caption.trim();

    final Widget body;
    final String? caption;
    if (hasRoute) {
      body = RouteSparkline(
        route: post.routePoints,
        strokeWidth: compact ? 2 : 2.5,
      );
      // The trace carries the eye, so the distance heads the footer.
      caption = headline ?? post.activity;
    } else if (kind == _PostKind.text) {
      body =
          _Words(text: words.isEmpty ? post.activity : words, compact: compact);
      // The author's own subtitle, when they wrote one and it isn't already
      // the thing in the body.
      final subtitle = post.activity.trim();
      caption = (subtitle.isEmpty || words.isEmpty) ? null : subtitle;
    } else {
      body = _Headline(
        text: headline ?? post.activity,
        compact: compact,
      );
      // The headline number is only ever drawn once: it has taken the body, so
      // the footer falls to the post's own title — "Leg Day", "Oats", or "Run"
      // for a run typed in by hand. A post carrying no numbers at all has
      // nothing left to say there, and the line drops rather than repeating.
      caption = headline == null ? null : post.activity;
    }

    // The second and third metrics, where there is room for them.
    final detail = compact ? '' : metrics.skip(1).join(' · ');

    final shape = BorderRadius.circular(borderRadius);

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane over the
      // app backdrop, like every other card. The old surface-to-surfaceHigh
      // gradient was an opaque slab, and on the dark theme that slab is
      // black — a grid of them next to photos read as a grid of holes.
      borderRadius: shape,
      child: Container(
        padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.sm + 2),
        decoration: BoxDecoration(
          borderRadius: shape,
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _KindGlyph(icon: _iconFor(kind, post), size: compact ? 22 : 28),
            SizedBox(height: compact ? 6 : AppSpacing.sm),
            Expanded(child: body),
            SizedBox(height: compact ? 4 : AppSpacing.sm),
            if (caption != null && caption.isNotEmpty)
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.text,
                  fontSize: compact ? 11.5 : 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 1),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.brandText, fontSize: 11.5),
              ),
            ],
            if (showAuthor) ...[
              const SizedBox(height: 2),
              Text(
                post.userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 11.5,
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

/// The tile a post gets in a grid when it *does* have a photo.
///
/// The picture on a run or a workout is a backdrop its author chose to put
/// behind the session — the session is still what was shared. A grid that drew
/// the picture alone threw all of that away: the trace, the numbers, and the
/// fact that the tile was a run at all. This keeps the photo as the backdrop it
/// was meant to be and draws the same things [PostSummaryTile] draws on its
/// card over the top of it, in the same order, so the two tiles read as one
/// family whether or not the author brought a photo.
///
/// Everything drawn here is fixed rather than themed, for the reason the run
/// and workout cards are: a photo looks the same in both themes, so a colour
/// that followed the palette would be legible in only one of them.
class PostMediaTile extends StatelessWidget {
  const PostMediaTile({
    required this.post,
    this.showAuthor = false,
    this.compact = false,
    this.borderRadius = 18,
    super.key,
  });

  final FeedPost post;

  /// Whether to name the author — Explore does, a profile grid doesn't.
  final bool showAuthor;

  /// The three-across treatment: a thinner line, smaller type, and only the
  /// headline measurement. At that size a full read-out is unreadable anyway.
  final bool compact;

  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final url = post.imageUrl;
    if (url == null || url.isEmpty) {
      // Not reachable from the grids, which check first — but a tile that
      // renders nothing at all is the one outcome worth ruling out.
      return PostSummaryTile(
        post: post,
        showAuthor: showAuthor,
        compact: compact,
        borderRadius: borderRadius,
      );
    }

    final kind = _kindOf(post);
    final metrics = _metricsOf(post);
    final hasRoute =
        kind == _PostKind.run && RouteSparkline.canDraw(post.routePoints);

    // A written post's photo *is* the post: nothing is being summarised over
    // it, so it keeps the plain caption band it has always had — and in a
    // profile grid, which names nobody, it keeps the bare photo. The activity
    // kinds get the glyph, the trace and the numbers.
    final summarised = kind != _PostKind.text;
    final headline = metrics.isEmpty ? null : metrics.first;
    final detail = compact ? '' : metrics.skip(1).join(' · ');
    final caption =
        headline ?? (summarised || !compact ? post.activity.trim() : '');
    final scrim = _scrimFor(
      summarised: summarised,
      hasFooter: caption.isNotEmpty || detail.isNotEmpty || showAuthor,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _PostPhoto(url: url, borderRadius: borderRadius),
          if (scrim != null)
            DecoratedBox(decoration: BoxDecoration(gradient: scrim)),
          Padding(
            padding:
                EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.sm + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (summarised) ...[
                  _KindGlyph(
                      icon: _iconFor(kind, post), size: compact ? 22 : 28),
                  SizedBox(height: compact ? 6 : AppSpacing.sm),
                ],
                // The trace sits in the same box the summary card's body does,
                // between the glyph and the numbers, so it never runs under
                // either of them.
                Expanded(
                  child: hasRoute
                      ? RouteSparkline(
                          route: post.routePoints,
                          strokeWidth: compact ? 2 : 2.5,
                          onMedia: true,
                        )
                      : const SizedBox.expand(),
                ),
                SizedBox(height: compact ? 4 : AppSpacing.sm),
                if (caption.isNotEmpty)
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.onMedia,
                      fontSize: compact ? 11.5 : 14,
                      fontWeight: FontWeight.w800,
                      shadows: _mediaTextShadows,
                    ),
                  ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.onMediaMuted,
                      fontSize: 11.5,
                      shadows: _mediaTextShadows,
                    ),
                  ),
                ],
                if (showAuthor) ...[
                  const SizedBox(height: 2),
                  Text(
                    post.userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.onMediaMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      shadows: _mediaTextShadows,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The wash that holds the overlay against an arbitrary photo.
  ///
  /// A summarised tile carries something at the top as well as the bottom, so
  /// it darkens at both ends and stays lightest across the middle where the
  /// trace is — the line brings its own contrast, and a flat scrim over the
  /// whole photo would only mute it. A plain photo has text along the bottom
  /// and nothing else, so it keeps the single band it always had, and none at
  /// all when there is nothing over it to hold up.
  static LinearGradient? _scrimFor({
    required bool summarised,
    required bool hasFooter,
  }) {
    if (!summarised) {
      if (!hasFooter) return null;
      return const LinearGradient(
        colors: [Colors.transparent, Color(0xE6050505)],
        stops: [0.55, 1],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
    }

    return const LinearGradient(
      colors: [
        Color(0x73050505),
        Color(0x1A050505),
        Color(0x59050505),
        Color(0xD9050505)
      ],
      stops: [0, 0.32, 0.66, 1],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
  }
}

/// The post's photo, filling the tile.
///
/// What stands in while it loads has to be dark-tolerant chrome rather than a
/// card: the scrim and the overlay are drawn over this in their media register,
/// and swapping in a summary card here would put a black scrim across a cream
/// tile for as long as the download took.
class _PostPhoto extends StatelessWidget {
  const _PostPhoto({required this.url, required this.borderRadius});

  final String url;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    // Decoded to the cell, not to the 1080px the photo is stored at. A grid
    // holds a dozen of these on screen at once, and at full size a single
    // screenful of them fills Flutter's entire decoded-image budget.
    return LayoutBuilder(
      builder: (context, constraints) => Image(
        image: appPhotoSized(context, url, constraints.maxWidth),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            MediaPlaceholder(borderRadius: borderRadius, failed: true),
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : MediaPlaceholder(borderRadius: borderRadius),
      ),
    );
  }
}

/// A measurement, set large: the body of a workout, a meal, or a run with no
/// trace to draw.
///
/// Hung from the bottom of the body so it sits directly above the label that
/// names it — "45 min" over "Leg Day" reads as one block, where the same
/// number floating in the middle of the card reads as a gap above it.
class _Headline extends StatelessWidget {
  const _Headline({required this.text, required this.compact});

  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: context.palette.text,
          fontSize: compact ? 15 : 20,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}

/// What someone wrote, which on a post with no photo is the entire post.
///
/// Set smaller and lighter than a headline and hung from the top of the body,
/// so a long caption fills the tile the way a paragraph does and a short one
/// doesn't float in the middle of it.
class _Words extends StatelessWidget {
  const _Words({required this.text, required this.compact});

  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Text(
        text,
        maxLines: compact ? 3 : 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: context.palette.text,
          fontSize: compact ? 12 : 13.5,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }
}

/// The orange disc that says what kind of post the tile holds.
///
/// Small and in the corner: it is the one saturated thing on the card, and the
/// post's own content is what the tile is for.
class _KindGlyph extends StatelessWidget {
  const _KindGlyph({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFA053), Color(0xFFFF6B2C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.36),
      ),
      child: Icon(icon, color: AppColors.onBrand, size: size * 0.57),
    );
  }
}

/// Stands in for a photo that is still loading, or one that never arrived.
///
/// Deliberately says nothing: a tile that swapped a full summary card for the
/// picture a moment later would flash a different layout on every scroll, and
/// a grid of them would look like a grid of different things.
class MediaPlaceholder extends StatelessWidget {
  const MediaPlaceholder(
      {this.borderRadius = 18, this.failed = false, super.key});

  final double borderRadius;

  /// Whether the photo failed outright, as opposed to still being on its way.
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      alignment: Alignment.center,
      child: Icon(
        failed ? Icons.broken_image_outlined : Icons.photo_outlined,
        color: palette.muted.withValues(alpha: 0.5),
        size: 22,
      ),
    );
  }
}
