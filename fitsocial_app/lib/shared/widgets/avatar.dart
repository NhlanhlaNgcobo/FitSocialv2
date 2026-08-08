import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';

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

/// The disc a monogram or the empty-profile glyph sits on.
///
/// Listed per theme rather than derived from the palette: it has to read as a
/// deliberate chip in both themes, and a fill pulled from `surfaceHigh` sits
/// so close to the card behind it that the circle disappears.
LinearGradient avatarDiscGradient(AppPalette palette) {
  return LinearGradient(
    colors: palette.isDark
        ? const [Color(0xFF3A3A3A), Color(0xFF262626)]
        : const [Color(0xFFE8E1D6), Color(0xFFD8D0C2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// A user's profile photo, or what stands in for one.
///
/// There are exactly two stand-ins, in this order: the user's initials, and —
/// when there is no real name to build initials from — a neutral person glyph.
/// Never a stock photograph. An account that has just been installed has
/// neither photo nor name, and borrowing a face from the brand sheet for it
/// puts a stranger's portrait on someone's profile.
class Avatar extends StatelessWidget {
  const Avatar({
    required this.initials,
    this.size = 44,
    this.imageUrl,
    this.border = AvatarBorder.hairline,
    super.key,
  });

  /// The user's monogram, from `avatarInitials`. Empty is a valid value and
  /// means "no name yet" — it selects the glyph rather than blanking the
  /// circle.
  final String initials;

  final double size;

  /// The user's uploaded profile photo. Takes precedence over [initials]; a
  /// failed load falls back to them rather than showing a broken image inside
  /// the circle.
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
        gradient: avatarDiscGradient(palette),
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
    final monogram = initials.trim();
    if (monogram.isEmpty) {
      return Icon(
        Icons.person_rounded,
        // A filled glyph reads optically larger than letters do, so it sits at
        // just over half the circle instead of filling it.
        size: size * 0.54,
        color: palette.muted,
      );
    }
    return Text(
      monogram,
      maxLines: 1,
      style: TextStyle(
        color: palette.text,
        fontSize: size * 0.34,
        fontWeight: FontWeight.w700,
        // Two letters set tight read as one word; a little tracking makes them
        // read as a monogram.
        letterSpacing: 0.5,
        // Kills the font's line leading so the letters sit on the circle's
        // optical centre rather than a little below it.
        height: 1,
      ),
    );
  }
}
