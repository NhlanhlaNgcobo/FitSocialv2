import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';

/// A logged workout drawn as a tinted block: title, duration and calories, then
/// the exercises that made it up.
///
/// The payload a workout post renders in place of a photo. Shared between the
/// feed card and the post detail page so a workout looks the same in both — the
/// detail page only widens the margin.
class WorkoutSummaryCard extends StatelessWidget {
  const WorkoutSummaryCard({
    required this.workoutData,
    required this.activity,
    this.margin = const EdgeInsets.symmetric(horizontal: 14),
    super.key,
  });

  /// The post's raw `workoutData` map. Absent keys simply drop their row, so a
  /// half-filled log still renders.
  final Map<String, dynamic>? workoutData;

  /// Fallback title when the log never carried one.
  final String activity;

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
      // Inset from the card's edges — a rounded block flush against the
      // enclosing card's sides reads as a mis-clipped card-in-a-card.
      margin: margin,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        // Listed per theme rather than derived from the palette so the dark
        // values stay exactly what the app shipped with.
        gradient: LinearGradient(
          colors: palette.isDark
              ? const [Color(0xFF1E1E1E), Color(0xFF111111)]
              : const [Color(0xFFFFFFFF), Color(0xFFF4EFE7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: palette.stroke, width: 1),
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
                  color: AppColors.onBrand,
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
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Workout Complete',
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.muted.withValues(alpha: 0.8),
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
                color: palette.overlay.withValues(alpha: 0.04),
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
                      color: palette.stroke,
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
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    palette.overlay.withValues(alpha: 0.27),
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
                color: palette.brandText.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: exercises.map((exercise) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: palette.overlay.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: palette.stroke.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Text(
                    exercise,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
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
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: context.palette.muted.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
