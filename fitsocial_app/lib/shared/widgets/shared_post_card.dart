import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import '../../features/main/domain/shared_post.dart';
import '../identity/profile_identity.dart';
import 'app_photo.dart';
import 'avatar.dart';
import 'route_sparkline.dart';
import 'run_summary_card.dart';
import 'workout_summary_card.dart';

/// A post as it appears once it has been put on somebody's Pulse.
///
/// This is the shape Instagram's "add post to story" sticker takes, and the
/// proportions are deliberately theirs: a card a little under three quarters of
/// the frame wide, the author's name and photo across the top, the picture at
/// the ratio it was cropped to, the caption clipped underneath. What is on the
/// card is a snapshot — see [SharedPostRef] — so it keeps rendering after the
/// post it came from is edited or gone.
///
/// Always drawn in the on-media register: white type, dark card. A Pulse frame
/// is a dark canvas in both themes, so this does not follow the app palette.
class SharedPostCard extends StatelessWidget {
  const SharedPostCard({
    required this.post,
    this.width,
    this.onTap,
    super.key,
  });

  final SharedPostRef post;

  /// Card width. Defaults to [widthFor] of the incoming constraints, which is
  /// what both the composer preview and the viewer use — passing a value is
  /// for the odd case that needs a fixed size.
  final double? width;

  /// Opening the post behind the card. Null in the composer, where the card is
  /// a preview of something not yet published.
  final VoidCallback? onTap;

  /// Fraction of the frame the card spans. Instagram's post sticker sits just
  /// under three quarters of the screen, which leaves the story's own gradient
  /// reading as a mount around it rather than a thin border.
  static const double _widthFraction = 0.72;

  /// Ceiling for tablets and landscape, where 72% of the width would be a card
  /// wider than anything on it is worth reading at.
  static const double _maxWidth = 420;

  static double widthFor(double available) {
    final width = available * _widthFraction;
    return width > _maxWidth ? _maxWidth : width;
  }

  @override
  Widget build(BuildContext context) {
    final card = LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = width ??
            widthFor(
              constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width,
            );

        return SizedBox(
          width: cardWidth,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x1FFFFFFF)),
              boxShadow: const [
                // Lifts the card off the gradient. Without it the two read as
                // one flat surface and the card stops looking like an object.
                BoxShadow(
                  color: Color(0x59000000),
                  blurRadius: 28,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(post: post),
                _Body(post: post),
                _Footer(post: post),
              ],
            ),
          ),
        );
      },
    );

    if (onTap == null) return card;
    return GestureDetector(
      onTap: onTap,
      // Opaque so the tap belongs to the card rather than falling through to
      // the viewer's own tap zones, which would advance the Pulse instead.
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.post});

  final SharedPostRef post;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Row(
        children: [
          Avatar(
            initials: avatarInitials(post.authorName),
            size: 28,
            imageUrl: post.authorAvatarUrl,
            // The card is fixed to the on-media register; a palette-coloured
            // hairline would vanish against it in light mode.
            border: AvatarBorder.none,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.authorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.onMedia,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                if (post.activity.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    post.activity,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.onMediaMuted,
                      fontSize: 11,
                      height: 1.2,
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
}

/// The picture, or what stands in for one.
///
/// A photo post draws its photo and a run draws the line it was: the shape of
/// somebody's route is the one thing on a run post worth recognising across a
/// room, and it comes off the snapshot with no map, no tiles and no network.
/// A run that was logged on a photo draws the line on that photo, the same
/// way the feed card does — the picture is the runner's own, and the card
/// should look like the post it opens. A workout draws its log sheet — the
/// same [WorkoutSummaryCard] the feed draws, on its photo if it had one —
/// because a workout *is* its numbers, and a glyph in their place said nothing
/// about the session. Only a share too old to carry what it needs falls back
/// to a tinted tile with a glyph and a label.
class _Body extends StatelessWidget {
  const _Body({required this.post});

  final SharedPostRef post;

  @override
  Widget build(BuildContext context) {
    if (post.kind == SharedPostKind.photo && post.hasImage) {
      return _Photo(post: post);
    }

    switch (post.kind) {
      case SharedPostKind.route:
        // A share written before the snapshot carried the trace has the kind
        // but not the shape, and still gets the label.
        if (!post.hasRoute) {
          return const _Placeholder(
            icon: Icons.route_rounded,
            label: 'Run route',
          );
        }
        final line = Padding(
          // Generous, because the line is scaled to whatever box it is given
          // — crowding the edges here would only make it bigger, not better.
          padding: const EdgeInsets.all(20),
          child: RouteSparkline(
            route: post.route,
            strokeWidth: 3,
            // The card is fixed to the on-media register whatever the app
            // theme is doing, and so is the line drawn on it.
            onMedia: true,
          ),
        );
        if (!post.hasImage) return _Tile(child: line);
        // The runner's map, with the route already drawn on it.
        // Contained rather than cropped: the branding sits in its corners.
        if (post.routeOnImage) return _Photo(post: post, fit: BoxFit.contain);
        // The runner's backdrop with the line over it and no scrim — what the
        // feed shows for this post. The photo sets the shape, as it does
        // there, so the line lands where the runner saw it land.
        return Stack(
          fit: StackFit.passthrough,
          children: [
            _Photo(post: post),
            Positioned.fill(child: line),
          ],
        );
      case SharedPostKind.workout:
        // A share written before the snapshot carried the log has the kind
        // but not the numbers, and still gets the label — unless it has a
        // photo, which the sheet can at least sit on with its title.
        if (!post.hasWorkout && !post.hasImage) {
          return const _Placeholder(
            icon: Icons.fitness_center_rounded,
            label: 'Workout',
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          // The sheet reads its colours off the app palette when it has no
          // photo, and this card is dark whatever the app is doing — so it is
          // handed the dark palette, and its type stays white on it.
          child: Theme(
            data: Theme.of(context).copyWith(
              extensions: const [AppPalette.dark],
            ),
            child: WorkoutSummaryCard(
              workoutData: post.workoutData,
              activity: post.activity,
              backgroundImageUrl: post.imageUrl,
              margin: EdgeInsets.zero,
            ),
          ),
        );
      case SharedPostKind.photo:
      case SharedPostKind.text:
        // A text post has no picture by definition, and a photo post whose URL
        // went missing falls here too. Either way the caption below is the
        // whole card, so nothing is reserved above it.
        return const SizedBox.shrink();
    }
  }
}

/// The post's photo, at the shape it was cropped to.
///
/// A photo post stores that shape. A run does not — its backdrop is measured
/// as it decodes, the way the feed's run card measures it — so a null ratio
/// here means "the photo's own", not "square".
class _Photo extends StatelessWidget {
  const _Photo({required this.post, this.fit = BoxFit.cover});

  final SharedPostRef post;
  final BoxFit fit;

  /// Same clamp the feed card uses, so neither a malformed stored ratio nor a
  /// very tall photo can produce a card taller than the frame it sits in.
  static const double _minRatio = 0.8;
  static const double _maxRatio = 1.91;

  @override
  Widget build(BuildContext context) {
    final image = appPhoto(post.imageUrl!);
    return PhotoAspectRatio(
      background: image,
      // Only a run is left to measure. A photo post without a stored ratio
      // is square, exactly as the feed draws it.
      pinned: post.kind == SharedPostKind.route
          ? post.aspectRatio
          : post.aspectRatio ?? 1.0,
      minRatio: _minRatio,
      maxRatio: _maxRatio,
      child: Image(
        image: image,
        fit: fit,
        errorBuilder: (_, __, ___) => const _Placeholder(
          icon: Icons.broken_image_rounded,
          label: 'Photo unavailable',
        ),
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const _Placeholder(icon: Icons.image_rounded, label: ''),
      ),
    );
  }
}

/// The band where the picture goes: one shape and one wash, whatever ends up
/// drawn on it, so a run and a workout are the same object seen twice.
class _Tile extends StatelessWidget {
  const _Tile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.4,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A1A0F), Color(0xFF101010)],
          ),
        ),
        child: child,
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return _Tile(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.onMediaMuted, size: 28),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.onMediaMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The caption, and the line that says the card is a way through to something.
class _Footer extends StatelessWidget {
  const _Footer({required this.post});

  final SharedPostRef post;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post.caption.isNotEmpty) ...[
            Text(
              post.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.onMedia,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
          ],
          const Row(
            children: [
              Icon(Icons.bolt_rounded, size: 13, color: AppColors.orangeBright),
              SizedBox(width: 4),
              Text(
                'VIEW POST',
                style: TextStyle(
                  color: AppColors.orangeBright,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
