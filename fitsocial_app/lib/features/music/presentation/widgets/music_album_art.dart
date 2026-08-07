import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';

/// Cover art for the current track, with a fallback for the gap before one
/// loads — or when the service hands back a track with no artwork.
///
/// Takes artwork in either form because the two Spotify transports disagree:
/// the Web API returns an https URL, while App Remote returns an opaque
/// `spotify:image:…` reference that only the SDK can turn into [imageBytes].
class MusicAlbumArt extends StatelessWidget {
  const MusicAlbumArt({
    required this.imageUrl,
    required this.accent,
    this.imageBytes,
    this.size = 62,
    super.key,
  });

  final String? imageUrl;

  /// Decoded cover art. Preferred over [imageUrl] when both are present, since
  /// bytes are already in hand and need no network round trip.
  final Uint8List? imageBytes;

  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bytes = imageBytes;
    final url = imageUrl;
    final palette = context.palette;

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: SizedBox(
        width: size,
        height: size,
        child: switch ((bytes, url)) {
          (final Uint8List data, _) => Image.memory(
              data,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _placeholder(palette),
            ),
          (_, final String link) => Image.network(
              link,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder(palette),
            ),
          _ => _placeholder(palette),
        },
      ),
    );
  }

  Widget _placeholder(AppPalette palette) {
    return ColoredBox(
      color: palette.surfaceHigh,
      child: Icon(
        Icons.music_note_rounded,
        color: accent.withValues(alpha: 0.7),
        size: size * 0.42,
      ),
    );
  }
}
