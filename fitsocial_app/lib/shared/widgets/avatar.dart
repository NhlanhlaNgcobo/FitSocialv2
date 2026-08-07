import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import 'brand_image_tile.dart';

/// How an [Avatar] is edged.
enum AvatarBorder {
  /// No edge at all. For avatars that already sit inside something else that
  /// draws a ring — the Pulse tray, where a border here would read as a second
  /// ring inside the first.
  none,

  /// A hairline that separates the photo from the surface behind it. The
  /// default, and what Instagram uses.
  hairline,

  /// The brand ring. Reserved for places that deliberately want to draw the
  /// eye to a person; not a default, because a coloured ring around every
  /// avatar is the thing that makes a feed look busy.
  brand,
}

class Avatar extends StatelessWidget {
  const Avatar({
    required this.initials,
    this.size = 44,
    this.visualTile,
    this.imageUrl,
    this.border = AvatarBorder.hairline,
    super.key,
  });

  final String initials;
  final double size;
  final AppVisualTile? visualTile;

  /// The user's uploaded profile photo. Takes precedence over [visualTile] and
  /// [initials]; a failed load falls back to them rather than showing a broken
  /// image inside the circle.
  final String? imageUrl;

  final AvatarBorder border;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: _border(palette),
        // The empty-avatar fill, one step off the surface it sits on so the
        // circle is visible even before any photo or initials land in it.
        gradient: LinearGradient(
          colors: [palette.surfaceHigh, palette.background],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: _buildContent(palette),
    );
  }

  Border? _border(AppPalette palette) {
    switch (border) {
      case AvatarBorder.none:
        return null;
      case AvatarBorder.hairline:
        return Border.all(color: palette.stroke);
      case AvatarBorder.brand:
        return Border.all(color: AppColors.orangeBright, width: 2);
    }
  }

  Widget _buildContent(AppPalette palette) {
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Never surface a broken-image glyph in an avatar — degrade to the
        // placeholder the user would otherwise have had.
        errorBuilder: (_, __, ___) => _placeholder(palette),
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : _placeholder(palette),
      );
    }
    return _placeholder(palette);
  }

  Widget _placeholder(AppPalette palette) {
    if (visualTile != null) {
      return BrandImageTile(
        tile: visualTile!,
        overlay: const Color(0x14050505),
      );
    }
    return Text(
      initials,
      style: TextStyle(
        color: palette.text,
        fontSize: size * 0.3,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
