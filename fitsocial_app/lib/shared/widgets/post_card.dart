import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/main/domain/app_models.dart';
import 'avatar.dart';
import 'brand_image_tile.dart';
import 'dark_card.dart';

class PostCard extends StatelessWidget {
  const PostCard({
    required this.userName,
    required this.activity,
    required this.caption,
    required this.metricLabels,
    required this.timestamp,
    this.likes = 0,
    this.comments = 0,
    this.backgroundColors = const [Color(0xFF332113), Color(0xFF0E0E0E)],
    this.visualTile,
    this.isLikedByMe = false,
    this.onLikeTapped,
    this.onCommentTapped,
    this.postType = PostType.text,
    this.imageUrl,
    this.workoutData,
    super.key,
  });

  final String userName;
  final String activity;
  final String caption;
  final List<String> metricLabels;
  final String timestamp;
  final int likes;
  final int comments;
  final List<Color> backgroundColors;
  final AppVisualTile? visualTile;
  final bool isLikedByMe;
  final VoidCallback? onLikeTapped;
  final VoidCallback? onCommentTapped;
  final PostType postType;
  final String? imageUrl;
  final Map<String, dynamic>? workoutData;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.md, horizontal: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Avatar(initials: _initials(userName), visualTile: visualTile),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Row 1: Username and timestamp
                      Row(
                        children: [
                          Text(
                            userName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            timestamp,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.more_horiz_rounded,
                              color: AppColors.muted, size: 20),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Row 2: Caption
                      if (caption.isNotEmpty) ...[
                        Text(
                          caption,
                          style: const TextStyle(fontSize: 15, height: 1.3),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],

                      // Row 3: Payload
                      if (postType != PostType.text || imageUrl != null || workoutData != null) ...[
                        _buildPayload(),
                        const SizedBox(height: AppSpacing.sm),
                      ],

                      // Row 4: Interaction Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: onCommentTapped,
                            child: _MetaIcon(
                              icon: Icons.chat_bubble_outline_rounded,
                              value: comments > 0 ? '$comments' : '',
                            ),
                          ),
                          GestureDetector(
                            onTap: onLikeTapped,
                            child: _MetaIcon(
                              icon: isLikedByMe
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              value: likes > 0 ? '$likes' : '',
                              highlighted: isLikedByMe,
                            ),
                          ),
                          const Icon(Icons.bookmark_border_rounded,
                              color: AppColors.muted, size: 20),
                          const SizedBox(width: 24), // Spacer for visual balance
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(
            color: AppColors.muted.withOpacity(0.2),
            height: 1,
            thickness: 1,
          ),
        ],
      ),
    );
  }

  /// Selects the correct visual payload based on [postType].
  Widget _buildPayload() {
    switch (postType) {
      case PostType.image:
        return _buildImagePayload();
      case PostType.workout:
        return _buildWorkoutPayload();
      case PostType.text:
        return _buildTextPayload();
    }
  }

  // ── TEXT payload (original gradient tile) ──────────────────────────────────

  Widget _buildTextPayload() {
    return const SizedBox.shrink();
  }

  // ── IMAGE payload (AspectRatio 4:5 clamped) ───────────────────────────────

  Widget _buildImagePayload() {
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
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
                    color: AppColors.muted.withOpacity(0.5),
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
                  color: Colors.black.withOpacity(0.28),
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
                        color: AppColors.muted.withOpacity(0.8),
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
                color: Colors.white.withOpacity(0.04),
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
                color: AppColors.orangeBright.withOpacity(0.9),
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
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.stroke.withOpacity(0.6),
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

class _MetaIcon extends StatelessWidget {
  const _MetaIcon({
    required this.icon,
    required this.value,
    this.highlighted = false,
  });

  final IconData icon;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: highlighted ? AppColors.danger : AppColors.muted,
          size: 20,
        ),
        if (value.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(value, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ],
      ],
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
            color: AppColors.muted.withOpacity(0.7),
          ),
        ),
      ],
    );
  }
}
