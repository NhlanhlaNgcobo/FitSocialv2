import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import 'app_photo.dart';
import 'fit_social_logo.dart';
import 'macro_ring.dart';
import 'network_photo_aspect.dart';
import 'picture_ratio.dart';

/// A logged meal drawn the way it is shared: the photo, the FitSocial
/// wordmark, the calorie total and a macro ring apiece for protein, carbs and
/// fat — the same hero the review screen shows before the meal is saved, so a
/// posted meal keeps looking the way it did when it was confirmed.
class MealSummaryCard extends StatelessWidget {
  const MealSummaryCard({
    required this.mealData,
    required this.activity,
    this.backgroundImageUrl,
    this.backgroundImage,
    this.aspectRatio = kPictureAspectRatio,
    this.margin = EdgeInsets.zero,
    super.key,
  });

  /// The post's raw `mealData` map: `calories`, `protein`, `carbs`, `fat`.
  /// Absent keys read as zero.
  final Map<String, dynamic>? mealData;

  /// The meal's name, printed where the review screen prints it.
  final String activity;

  /// A meal is a photo of food, so this is normally set; null falls back to a
  /// flat tint rather than crop nothing to nothing.
  final String? backgroundImageUrl;

  /// An already-resolved photo, supplied only by the export pipeline: it
  /// measures and holds the photo itself before this card is ever built, and
  /// cannot afford to resolve the same image a second time inside an
  /// off-screen overlay. Takes precedence over [backgroundImageUrl].
  final ImageProvider? backgroundImage;

  /// Used only while the real photo hasn't resolved its shape yet, and as the
  /// shape outright when there is no photo — the app's 9:16, since a meal post
  /// has never recorded the crop ratio the user picked.
  final double aspectRatio;

  final EdgeInsetsGeometry margin;

  static int _numberFrom(Object? value) {
    if (value == null) return 0;
    if (value is num) return value.round();
    return int.tryParse(value.toString().trim()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final resolved = backgroundImage;
    if (resolved != null) {
      return _card(context, aspectRatio, resolved);
    }
    final url = backgroundImageUrl;
    if (url == null || url.isEmpty) {
      return _card(context, aspectRatio, null);
    }
    // Sized to the photo's own shape rather than forced square, so a portrait
    // or panoramic meal shot keeps its edges instead of having them cropped
    // away.
    return NetworkPhotoAspect(
      imageUrl: url,
      fallbackAspectRatio: aspectRatio,
      builder: (context, ratio) => _card(context, ratio, appPhoto(url)),
    );
  }

  Widget _card(BuildContext context, double ratio, ImageProvider? image) {
    final data = mealData ?? const {};
    final calories = _numberFrom(data['calories']);
    final protein = _numberFrom(data['protein']);
    final carbs = _numberFrom(data['carbs']);
    final fat = _numberFrom(data['fat']);

    // Rings read as a share of the meal's own calories — computed the same
    // way the review screen's hero computes it, so a meal rings identically
    // in both places.
    final macroCalories = protein * 4 + carbs * 4 + fat * 9;
    final totalCalories = calories > 0 ? calories : macroCalories;
    double fractionOf(int kcal) =>
        totalCalories <= 0 ? 0 : (kcal / totalCalories).clamp(0.0, 1.0);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x38F7F7F7)),
      ),
      child: ClipRRect(
        // Inset by the border width so the photo stops at the inside edge of
        // the stroke rather than painting over it.
        borderRadius: BorderRadius.circular(19),
        child: AspectRatio(
          aspectRatio: ratio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null)
                Image(
                  image: image,
                  fit: BoxFit.cover,
                  // A backdrop that fails to load must not take the meal's
                  // numbers down with it — fall back to the flat tint.
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFF1E1E1E)),
                )
              else
                const ColoredBox(color: Color(0xFF1E1E1E)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0x8C050505),
                      Color(0x30050505),
                      Color(0xCC050505),
                    ],
                    stops: [0, 0.45, 1],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Same lockup and the same size as the run card's, so a
                    // meal shared out of the app is signed the way the app
                    // signs itself everywhere else.
                    const FitSocialLogo(
                      size: 15,
                      animated: false,
                      color: AppColors.onMedia,
                    ),
                    const Spacer(),
                    // Wraps rather than ellipsises: the picture is what gets
                    // shared, and a name cut short in it cannot be read back.
                    Text(
                      activity,
                      style: const TextStyle(
                        color: AppColors.onMedia,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Takes the room the rings leave and shrinks to it,
                        // so a big total on a narrow card is never pushed off
                        // the edge.
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.bottomLeft,
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(text: '$calories'),
                                    const TextSpan(
                                      text: ' kcal',
                                      style: TextStyle(
                                        color: AppColors.onMediaMuted,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                style: const TextStyle(
                                  color: AppColors.onMedia,
                                  fontSize: 30,
                                  height: 1,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.8,
                                  shadows: onMediaTextShadows,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        MacroRing(
                          label: 'Protein',
                          grams: protein,
                          fraction: fractionOf(protein * 4),
                          color: proteinMacroColor,
                        ),
                        const SizedBox(width: 10),
                        MacroRing(
                          label: 'Carbs',
                          grams: carbs,
                          fraction: fractionOf(carbs * 4),
                          color: carbsMacroColor,
                        ),
                        const SizedBox(width: 10),
                        MacroRing(
                          label: 'Fat',
                          grams: fat,
                          fraction: fractionOf(fat * 9),
                          color: fatMacroColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
