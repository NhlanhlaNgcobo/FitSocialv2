import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import 'brand_image_tile.dart';

class Avatar extends StatelessWidget {
  const Avatar({
    required this.initials,
    this.size = 44,
    this.visualTile,
    this.imageUrl,
    super.key,
  });

  final String initials;
  final double size;
  final AppVisualTile? visualTile;

  /// The user's uploaded profile photo. Takes precedence over [visualTile] and
  /// [initials]; a failed load falls back to them rather than showing a broken
  /// image inside the circle.
  final String? imageUrl;

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
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Never surface a broken-image glyph in an avatar — degrade to the
        // placeholder the user would otherwise have had.
        errorBuilder: (_, __, ___) => _placeholder(),
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    if (visualTile != null) {
      return BrandImageTile(
        tile: visualTile!,
        overlay: const Color(0x14050505),
      );
    }
    return Text(
      initials,
      style: TextStyle(
        color: AppColors.white,
        fontSize: size * 0.3,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
