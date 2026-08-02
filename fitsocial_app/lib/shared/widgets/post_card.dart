import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/main/application/content_providers.dart';
import '../../features/main/data/content_repository.dart';
import '../../features/main/domain/app_models.dart';
import 'avatar.dart';
import 'brand_image_tile.dart';
import 'run_route_map.dart';

class PostCard extends StatelessWidget {
  const PostCard({
    required this.postId,
    required this.userName,
    required this.activity,
    required this.caption,
    required this.metricLabels,
    required this.timestamp,
    this.likes = 0,
    this.comments = 0,
    this.backgroundColors = const [Color(0xFF332113), Color(0xFF0E0E0E)],
    this.visualTile,
    this.onCommentTapped,
    this.postType = PostType.text,
    this.imageUrl,
    this.workoutData,
    this.routePoints = const [],
    this.authorAvatarUrl,
    this.imageAspectRatio,
    super.key,
  });

  final String postId;
  final String userName;
  final String activity;
  final String caption;
  final List<String> metricLabels;
  final String timestamp;
  final int likes;
  final int comments;
  final List<Color> backgroundColors;
  final AppVisualTile? visualTile;
  final VoidCallback? onCommentTapped;
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

  /// A polyline needs at least two fixes; a single point is not a route.
  bool get _hasRoute => routePoints.length >= 2;

  bool get _hasPayload =>
      postType != PostType.text ||
      imageUrl != null ||
      workoutData != null ||
      _hasRoute;

  @override
  Widget build(BuildContext context) {
    // One layout for every post type. The header — and therefore the avatar —
    // sits in exactly the same place whether the post carries a photo, a run
    // map, a workout card or nothing but text. Only the body swaps: media posts
    // put their caption below the actions (Instagram), text posts put the words
    // where the media would have been.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        if (_hasPayload) _buildPayload() else _buildBodyText(),
        _InteractionRow(
          postId: postId,
          likes: likes,
          comments: comments,
          onCommentTapped: onCommentTapped,
        ),
        // A text post's words are already the body, so there's no caption line
        // to repeat underneath.
        if (_hasPayload) _buildCaption(),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  /// The words of a text-only post, set to Threads' body metrics: 15px on a
  /// 21px line box. Sits at the gutter, aligned with the caption and the
  /// username above it, so the left edge of every post's content lines up.
  Widget _buildBodyText() {
    if (caption.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 0, _gutter, 2),
      child: Text(
        caption,
        style: const TextStyle(
          fontSize: 15,
          height: 21 / 15,
          color: AppColors.white,
        ),
      ),
    );
  }

  /// Horizontal inset for everything except the media, which runs edge to edge.
  static const double _gutter = 16;

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 10, 6, 10),
      child: Row(
        children: [
          Avatar(
            initials: _initials(userName),
            size: 34,
            visualTile: visualTile,
            imageUrl: authorAvatarUrl,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    userName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.white,
                    ),
                  ),
                ),
                const Text(
                  ' • ',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                Text(
                  timestamp,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.more_horiz_rounded,
                color: AppColors.white, size: 22),
          ),
        ],
      ),
    );
  }

  /// Username in semibold followed by the caption on the same line — the
  /// Instagram convention, and it reads as one sentence rather than a header.
  Widget _buildCaption() {
    if (caption.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 6, _gutter, 0),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 14,
            height: 1.35,
            color: AppColors.white,
          ),
          children: [
            TextSpan(
              text: userName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const TextSpan(text: '  '),
            TextSpan(text: caption),
          ],
        ),
      ),
    );
  }

  /// Selects the correct visual payload based on [postType].
  Widget _buildPayload() {
    // Run posts are stored as PostType.text — the route, not the type, is what
    // marks them out, so it is checked before the type switch.
    if (_hasRoute) return _buildRoutePayload();

    switch (postType) {
      case PostType.image:
        return _buildImagePayload();
      case PostType.workout:
        return _buildWorkoutPayload();
      case PostType.text:
        return _buildTextPayload();
    }
  }

  // ── ROUTE payload (completed run map preview) ─────────────────────────────

  Widget _buildRoutePayload() {
    return RunRouteMap(
      route: routePoints
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList(growable: false),
      mode: RunRouteMapMode.completed,
      height: 200,
    );
  }

  // ── TEXT payload (original gradient tile) ──────────────────────────────────

  Widget _buildTextPayload() {
    return const SizedBox.shrink();
  }

  // ── IMAGE payload (AspectRatio 4:5 clamped) ───────────────────────────────

  Widget _buildImagePayload() {
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
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(
                    Icons.broken_image_rounded,
                    color: AppColors.muted.withValues(alpha: 0.5),
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
            // Activity badge top-right
            Positioned(
              top: AppSpacing.md,
              right: AppSpacing.md,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  activity,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── WORKOUT payload (charcoal DarkCard with structured data) ──────────────

  Widget _buildWorkoutPayload() {
    final data = workoutData ?? const {};
    final title = (data['title'] as String?) ?? activity;
    final duration = data['duration'] as String?;
    final calories = data['calories'] as String?;
    final exercises = (data['exercises'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1E1E), Color(0xFF111111)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.stroke, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Workout title row
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFA053), Color(0xFFFF6B2C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.fitness_center_rounded,
                  color: AppColors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm + 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Workout Complete',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.muted.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Metrics row (duration + calories)
          if (duration != null || calories != null)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm + 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  if (duration != null)
                    Expanded(
                      child: _WorkoutMetric(
                        icon: Icons.timer_outlined,
                        label: 'Duration',
                        value: duration,
                      ),
                    ),
                  if (duration != null && calories != null)
                    Container(
                      width: 1,
                      height: 32,
                      color: AppColors.stroke,
                    ),
                  if (calories != null)
                    Expanded(
                      child: _WorkoutMetric(
                        icon: Icons.local_fire_department_rounded,
                        label: 'Calories',
                        value: calories,
                      ),
                    ),
                ],
              ),
            ),

          // Exercises list
          if (exercises.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Color(0x44FFFFFF),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm + 4),
            Text(
              '${exercises.length} EXERCISES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppColors.orangeBright.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: exercises.map((exercise) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.stroke.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Text(
                    exercise,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.white,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
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

  String _initials(String name) {
    final parts = name.split(' ');
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _InteractionRow extends ConsumerWidget {
  const _InteractionRow({
    required this.postId,
    required this.likes,
    required this.comments,
    this.onCommentTapped,
  });

  final String postId;
  final int likes;
  final int comments;
  final VoidCallback? onCommentTapped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLiked = ref.watch(postLikeStatusProvider(postId)).valueOrNull ?? false;
    final isBookmarked = ref.watch(postBookmarkStatusProvider(postId)).valueOrNull ?? false;

    // Spread evenly across the full width rather than clustered on the left,
    // so the row reads as a balanced base to the post. Counts sit inline with
    // their icon (Threads-style) instead of on separate lines, which keeps the
    // card short and the layout identical for text and media posts.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ActionIcon(
          icon: isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          // Only the active like takes the brand colour; everything at rest is
          // muted so the row stays quiet until the user acts.
          color: isLiked ? AppColors.orange : AppColors.muted,
          count: likes,
          onTap: () async {
            final userId = FirebaseAuth.instance.currentUser?.uid;
            if (userId == null) return;
            await ref.read(contentRepositoryProvider).toggleLike(postId, userId);
          },
        ),
        _ActionIcon(
          icon: Icons.mode_comment_outlined,
          color: AppColors.muted,
          count: comments,
          onTap: onCommentTapped,
        ),
        _ActionIcon(
          icon: Icons.send_outlined,
          color: AppColors.muted,
          onTap: () {},
        ),
        _ActionIcon(
          icon: isBookmarked
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          color: isBookmarked ? AppColors.orange : AppColors.muted,
          onTap: () async {
            final userId = FirebaseAuth.instance.currentUser?.uid;
            if (userId == null) return;
            await ref
                .read(contentRepositoryProvider)
                .toggleBookmark(postId, userId);
          },
        ),
      ],
    );
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
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final int count;
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
            Icon(icon, color: color, size: 20),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(color: color, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkoutMetric extends StatelessWidget {
  const _WorkoutMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.orangeBright, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.muted.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
