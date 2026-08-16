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
///
/// With a [backgroundImageUrl] the tint gives way to the user's photo under a
/// scrim. That flips every colour decision in here: on a photo the card is no
/// longer sitting on a themed surface, so text that followed the palette would
/// go black-on-dark-photo the moment the viewer used the light theme.
class WorkoutSummaryCard extends StatelessWidget {
  const WorkoutSummaryCard({
    required this.workoutData,
    required this.activity,
    this.backgroundImageUrl,
    this.margin = const EdgeInsets.symmetric(horizontal: 14),
    super.key,
  });

  /// The post's raw `workoutData` map. Absent keys simply drop their row, so a
  /// half-filled log still renders.
  final Map<String, dynamic>? workoutData;

  /// Fallback title when the log never carried one.
  final String activity;

  /// A photo to draw behind the card. Null keeps the original tinted gradient,
  /// which is what every workout logged before this existed still uses.
  final String? backgroundImageUrl;

  final EdgeInsetsGeometry margin;

  /// One value from the log, as text, whatever Firestore is holding it as.
  ///
  /// A cast would be wrong here for the same reason [_exerciseLabel] handles
  /// two shapes: the app writes `duration` and `calories` as labels ('45 min'),
  /// but the sibling `workouts` document writes the same names as numbers, and
  /// a post whose map came from that shape would throw mid-layout — which does
  /// not merely drop the row, it blanks the whole page the card sits on.
  /// Returns null for an absent or empty value, so the row drops as intended.
  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  /// One exercise chip's text.
  ///
  /// Firestore stores each exercise as a map, so calling toString() on it
  /// renders the literal `{reps: 25, sets: 5, name: legs}` in the feed. Older
  /// posts wrote plain strings, so both shapes have to survive here.
  static String _exerciseLabel(dynamic exercise) {
    if (exercise is! Map) {
      return exercise?.toString().trim() ?? '';
    }
    final name = exercise['name']?.toString().trim() ?? '';
    if (name.isEmpty) {
      return '';
    }
    final sets = exercise['sets']?.toString().trim() ?? '';
    final reps = exercise['reps']?.toString().trim() ?? '';
    if (sets.isEmpty && reps.isEmpty) {
      return name;
    }
    // "legs · 5 × 25", falling back to whichever number is present.
    final volume = (sets.isNotEmpty && reps.isNotEmpty)
        ? '$sets × $reps'
        : (sets.isNotEmpty ? '$sets sets' : '$reps reps');
    return '$name · $volume';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final data = workoutData ?? const {};
    final title = _text(data['title']) ?? activity;
    final duration = _text(data['duration']);
    final calories = _text(data['calories']);
    final exercises = (data['exercises'] as List<dynamic>?)
            ?.map(_exerciseLabel)
            .where((label) => label.isNotEmpty)
            .toList() ??
        const [];

    final skin = _CardSkin.resolve(palette, hasPhoto: backgroundImageUrl != null);

    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: skin.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Workout Complete',
                      style: TextStyle(
                        fontSize: 12,
                        color: skin.muted,
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
                color: skin.fill,
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
                        skin: skin,
                      ),
                    ),
                  if (duration != null && calories != null)
                    Container(
                      width: 1,
                      height: 32,
                      color: skin.stroke,
                    ),
                  if (calories != null)
                    Expanded(
                      child: _WorkoutMetric(
                        icon: Icons.local_fire_department_rounded,
                        label: 'Calories',
                        value: calories,
                        skin: skin,
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
                    skin.divider,
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
                color: skin.accent,
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
                    color: skin.chipFill,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: skin.stroke),
                  ),
                  child: Text(
                    exercise,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: skin.text,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );

    return Container(
      // Inset from the card's edges — a rounded block flush against the
      // enclosing card's sides reads as a mis-clipped card-in-a-card.
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: skin.border, width: 1),
      ),
      child: ClipRRect(
        // Inset by the border width so the photo stops at the inside edge of
        // the stroke rather than painting over it.
        borderRadius: BorderRadius.circular(19),
        child: backgroundImageUrl == null
            ? DecoratedBox(
                decoration: BoxDecoration(
                  // Listed per theme rather than derived from the palette so
                  // the dark values stay exactly what the app shipped with.
                  gradient: LinearGradient(
                    colors: palette.isDark
                        ? const [Color(0xFF1E1E1E), Color(0xFF111111)]
                        : const [Color(0xFFFFFFFF), Color(0xFFF4EFE7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: content,
              )
            : Stack(
                children: [
                  Positioned.fill(
                    child: Image.network(
                      backgroundImageUrl!,
                      fit: BoxFit.cover,
                      // A backdrop that fails to load must not take the
                      // workout's numbers down with it — fall back to the flat
                      // tint and carry on.
                      errorBuilder: (context, error, stackTrace) =>
                          ColoredBox(color: skin.photoFallback),
                    ),
                  ),
                  // Without this the metrics sit on whatever the photo happens
                  // to be, and a bright gym window erases them.
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0x66050505), Color(0xD9050505)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  content,
                ],
              ),
      ),
    );
  }
}

/// The colours the card draws itself in, resolved once for whichever backdrop
/// it has.
///
/// On the themed gradient these follow the palette as they always did. On a
/// photo they are fixed light values: the photo is the same in both themes, so
/// a colour that flipped with the theme would be legible in only one of them.
class _CardSkin {
  const _CardSkin({
    required this.text,
    required this.muted,
    required this.accent,
    required this.fill,
    required this.chipFill,
    required this.stroke,
    required this.divider,
    required this.border,
    required this.photoFallback,
  });

  factory _CardSkin.resolve(AppPalette palette, {required bool hasPhoto}) {
    if (!hasPhoto) {
      return _CardSkin(
        text: palette.text,
        muted: palette.muted.withValues(alpha: 0.8),
        accent: palette.brandText.withValues(alpha: 0.9),
        fill: palette.overlay.withValues(alpha: 0.04),
        chipFill: palette.overlay.withValues(alpha: 0.06),
        stroke: palette.stroke.withValues(alpha: 0.6),
        divider: palette.overlay.withValues(alpha: 0.27),
        border: palette.stroke,
        photoFallback: palette.surfaceHigh,
      );
    }

    return _CardSkin(
      text: AppColors.onMedia,
      muted: AppColors.onMedia.withValues(alpha: 0.78),
      // The bright orange, not brandText: on a darkened photo the small-text
      // variant tuned for cream loses against the scrim.
      accent: AppColors.orangeBright,
      fill: AppColors.onMedia.withValues(alpha: 0.14),
      chipFill: AppColors.onMedia.withValues(alpha: 0.16),
      stroke: AppColors.onMedia.withValues(alpha: 0.28),
      divider: AppColors.onMedia.withValues(alpha: 0.35),
      border: AppColors.onMedia.withValues(alpha: 0.22),
      photoFallback: const Color(0xFF1E1E1E),
    );
  }

  final Color text;
  final Color muted;
  final Color accent;
  final Color fill;
  final Color chipFill;
  final Color stroke;
  final Color divider;
  final Color border;

  /// Painted when the photo itself fails to load.
  final Color photoFallback;
}

class _WorkoutMetric extends StatelessWidget {
  const _WorkoutMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.skin,
  });

  final IconData icon;
  final String label;
  final String value;
  final _CardSkin skin;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.orangeBright, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: skin.text,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: skin.muted),
        ),
      ],
    );
  }
}
