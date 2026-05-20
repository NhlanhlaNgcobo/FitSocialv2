import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

const kFitSocialBrandSheetAsset = 'assets/images/fitsocial_brand_sheet.png';

enum AppVisualTile {
  heroPortrait,
  coastalRunner,
  mealBowl,
  gymFlex,
  womanRunner,
  groupTraining,
}

class BrandImageTile extends StatelessWidget {
  const BrandImageTile({
    required this.tile,
    this.assetPath = kFitSocialBrandSheetAsset,
    this.borderRadius,
    this.overlay = const Color(0x33050505),
    this.showBorder = false,
    super.key,
  });

  final AppVisualTile tile;
  final String assetPath;
  final BorderRadius? borderRadius;
  final Color overlay;
  final bool showBorder;

  Alignment get _alignment {
    switch (tile) {
      case AppVisualTile.heroPortrait:
        return const Alignment(-1, -1);
      case AppVisualTile.coastalRunner:
        return const Alignment(0, -1);
      case AppVisualTile.mealBowl:
        return const Alignment(1, -1);
      case AppVisualTile.gymFlex:
        return const Alignment(-1, 1);
      case AppVisualTile.womanRunner:
        return const Alignment(0, 1);
      case AppVisualTile.groupTraining:
        return const Alignment(1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.zero;

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: showBorder ? Border.all(color: AppColors.stroke) : null,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final panelWidth = constraints.maxWidth <= 0 ? 120.0 : constraints.maxWidth;
            final panelHeight = constraints.maxHeight <= 0 ? 120.0 : constraints.maxHeight;

            return Stack(
              fit: StackFit.expand,
              children: [
                ClipRect(
                  child: OverflowBox(
                    maxWidth: panelWidth * 3,
                    maxHeight: panelHeight * 2,
                    alignment: _alignment,
                    child: Image.asset(
                      assetPath,
                      width: panelWidth * 3,
                      height: panelHeight * 2,
                      fit: BoxFit.cover,
                      alignment: _alignment,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
                if (overlay.opacity > 0)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: overlay,
                      borderRadius: radius,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
