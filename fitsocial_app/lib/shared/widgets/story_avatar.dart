import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import 'avatar.dart';
import 'brand_image_tile.dart';

class StoryAvatar extends StatelessWidget {
  const StoryAvatar({
    required this.name,
    required this.initials,
    this.visualTile,
    this.isOwnStory = false,
    super.key,
  });

  final String name;
  final String initials;
  final AppVisualTile? visualTile;
  final bool isOwnStory;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.orangeBright, width: 2),
              ),
              child: Avatar(
                initials: initials,
                size: 58,
                visualTile: visualTile,
              ),
            ),
            if (isOwnStory)
              Positioned(
                right: 0,
                bottom: -2,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppColors.orangeBright,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.black, width: 2),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: AppColors.white,
                    size: 14,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          name,
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
