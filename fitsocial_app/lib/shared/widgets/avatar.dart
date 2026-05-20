import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import 'brand_image_tile.dart';

class Avatar extends StatelessWidget {
  const Avatar({
    required this.initials,
    this.size = 44,
    this.visualTile,
    super.key,
  });

  final String initials;
  final double size;
  final AppVisualTile? visualTile;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.orangeBright, width: 2),
        gradient: const LinearGradient(
          colors: [AppColors.surfaceHigh, AppColors.black],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: visualTile != null
          ? BrandImageTile(
              tile: visualTile!,
              overlay: const Color(0x14050505),
            )
          : Text(
              initials,
              style: TextStyle(
                color: AppColors.white,
                fontSize: size * 0.3,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}
