import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../features/main/domain/shared_post.dart';
import '../identity/profile_identity.dart';
import 'avatar.dart';

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
/// A photo post draws its photo. Everything else draws a tinted tile with the
/// glyph for what it was, because a run map and a workout block are both too
/// much detail at this size — the card is an invitation to open the post, not
/// a copy of it.
class _Body extends StatelessWidget {
  const _Body({required this.post});

  final SharedPostRef post;

  @override
  Widget build(BuildContext context) {
    if (post.kind == SharedPostKind.photo && post.hasImage) {
      return AspectRatio(
        // Same clamp the feed card uses, so a malformed stored ratio can't
        // produce a card taller than the frame it sits in.
        aspectRatio: (post.aspectRatio ?? 1.0).clamp(0.8, 1.91),
        child: Image.network(
          post.imageUrl!,
          fit: BoxFit.cover,
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

    switch (post.kind) {
      case SharedPostKind.route:
        return const _Placeholder(
          icon: Icons.route_rounded,
          label: 'Run route',
        );
      case SharedPostKind.workout:
        return const _Placeholder(
          icon: Icons.fitness_center_rounded,
          label: 'Workout',
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

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.label});

  final IconData icon;
  final String label;

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
