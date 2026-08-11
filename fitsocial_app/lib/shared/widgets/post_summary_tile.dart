import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/main/domain/app_models.dart';
import '../../features/main/domain/explore_models.dart';
import 'route_sparkline.dart';

/// What kind of post a tile is showing. Drives the glyph and what the body
/// leads with — nothing else.
enum _PostKind { run, workout, meal, text }

/// The tile a post gets in a grid when there is no photo to show.
///
/// Every grid in the app used to fall back to the post's stored gradient here:
/// a muddy orange rectangle with the activity's name printed on it, repeated
/// down the column, saying nothing about any of the posts behind it. Those
/// colour pairs were mixed for the dark app and describe nothing about a post,
/// so this drops them and builds on the palette instead — a quiet card, with
/// the post's own content as the only thing on it worth looking at.
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

  /// [ExploreFilterX] owns the kind checks because it already has to recognise
  /// the posts written before the types existed. Order matters: a workout
  /// writes a '0 kcal' metric of its own, so it has to be claimed before
  /// anything asks whether this is a meal.
  static _PostKind _kindOf(FeedPost post) {
    if (ExploreFilterX.isWorkout(post)) return _PostKind.workout;
    if (ExploreFilterX.isRun(post)) return _PostKind.run;
    if (ExploreFilterX.isMeal(post)) return _PostKind.meal;
    return _PostKind.text;
  }

  static IconData _iconFor(_PostKind kind) => switch (kind) {
        _PostKind.run => Icons.directions_run_rounded,
        _PostKind.workout => Icons.fitness_center_rounded,
        _PostKind.meal => Icons.restaurant_rounded,
        _PostKind.text => Icons.format_quote_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final kind = _kindOf(post);
    final metrics = post.metricLabels
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList(growable: false);

    // A run with a trace shows the trace. Everything else leads with what it
    // has: the headline number for a workout, a meal or a hand-typed run, and
    // for a written post the words themselves.
    final hasRoute = kind == _PostKind.run &&
        RouteSparkline.canDraw(post.routePoints);
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
      body = _Words(text: words.isEmpty ? post.activity : words, compact: compact);
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

    return Container(
      padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.sm + 2),
      decoration: BoxDecoration(
        // A whisper of a gradient rather than a flat fill: a grid of flat
        // cards reads as a spreadsheet, and this is the same lift the workout
        // card in the feed has always had.
        gradient: LinearGradient(
          colors: [palette.surface, palette.surfaceHigh],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: palette.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KindGlyph(icon: _iconFor(kind), size: compact ? 22 : 28),
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
  const MediaPlaceholder({this.borderRadius = 18, this.failed = false, super.key});

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
