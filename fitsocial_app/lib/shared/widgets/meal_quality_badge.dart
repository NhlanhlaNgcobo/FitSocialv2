import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../features/main/domain/meal_quality.dart';

/// The colour each band keeps wherever a meal's score is drawn.
///
/// The low end is a soft lilac rather than a warning red: the score is shown
/// on shared posts, and a dessert is not an error.
Color mealQualityColor(MealQualityBand band) => switch (band) {
      MealQualityBand.great => const Color(0xFF31C46C),
      MealQualityBand.good => const Color(0xFF8BD17C),
      MealQualityBand.fair => const Color(0xFFF5C451),
      MealQualityBand.treat => const Color(0xFFC9A0DC),
    };

/// "● Good · 7/10" in a dark pill, for drawing over a meal photo.
class MealQualityBadge extends StatelessWidget {
  const MealQualityBadge({required this.score, super.key});

  /// 0–10, as stored in a post's `mealData.quality`.
  final int score;

  @override
  Widget build(BuildContext context) {
    final band = MealQualityBand.of(score);
    final color = mealQualityColor(band);
    return Semantics(
      label: 'Meal quality ${band.label}, $score out of 10',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0x99050505),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              '${band.label} · $score/10',
              style: const TextStyle(
                color: AppColors.onMedia,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
