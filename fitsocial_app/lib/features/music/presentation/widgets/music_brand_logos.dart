import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../main/domain/app_models.dart';

/// The Spotify, Apple Music and YouTube Music marks.
///
/// Each is drawn from the service's own vector outline rather than a bitmap:
/// every one of the three brand guides forbids redrawing, recolouring or
/// stretching the logo, and a vector keeps it exact from the 20px chip in the
/// player bar up to the 140px watermark behind a connect button. The outlines
/// below are the public-domain single-path versions published by Simple Icons.
///
/// Each mark is one path in which the detail (Spotify's waves, Apple's note,
/// YouTube's ring and triangle) is a hole, so the full-colour version stacks
/// the path over a backing shape and lets the backing show through.
class MusicBrandArtwork {
  const MusicBrandArtwork._();

  static const _spotifyPath =
      'M12 0C5.4 0 0 5.4 0 12s5.4 12 12 12 12-5.4 12-12S18.66 0 12 0zm5.521 '
      '17.34c-.24.359-.66.48-1.021.24-2.82-1.74-6.36-2.101-10.561-1.141-.418.'
      '122-.779-.179-.899-.539-.12-.421.18-.78.54-.9 4.56-1.021 8.52-.6 11.64 '
      '1.32.42.18.479.659.301 1.02zm1.44-3.3c-.301.42-.841.6-1.262.3-3.239-1.98'
      '-8.159-2.58-11.939-1.38-.479.12-1.02-.12-1.14-.6-.12-.48.12-1.021.6-1.14'
      '1C9.6 9.9 15 10.561 18.72 12.84c.361.181.54.78.241 1.2zm.12-3.36C15.24 '
      '8.4 8.82 8.16 5.16 9.301c-.6.179-1.2-.181-1.38-.721-.18-.601.18-1.2.72-'
      '1.381 4.26-1.26 11.28-1.02 15.721 1.621.539.3.719 1.02.419 1.56-.299.421'
      '-1.02.599-1.559.3z';

  static const _appleMusicPath =
      'M23.994 6.124a9.23 9.23 0 00-.24-2.19c-.317-1.31-1.062-2.31-2.18-3.043a5'
      '.022 5.022 0 00-1.877-.726a10.496 10.496 0 00-1.564-.15c-.04-.003-.083-.'
      '01-.124-.013H5.986c-.152.01-.303.017-.455.026-.747.043-1.49.123-2.193.4-'
      '1.336.53-2.3 1.452-2.865 2.78-.192.448-.292.925-.363 1.408-.056.392-.088'
      '.785-.1 1.18 0 .032-.007.062-.01.093v12.223c.01.14.017.283.027.424.05.81'
      '5.154 1.624.497 2.373.65 1.42 1.738 2.353 3.234 2.801.42.127.856.187 1.2'
      '93.228.555.053 1.11.06 1.667.06h11.03a12.5 12.5 0 001.57-.1c.822-.106 1.'
      '596-.35 2.295-.81a5.046 5.046 0 001.88-2.207c.186-.42.293-.87.37-1.324.1'
      '13-.675.138-1.358.137-2.04-.002-3.8 0-7.595-.003-11.393zm-6.423 3.99v5.7'
      '12c0 .417-.058.827-.244 1.206-.29.59-.76.962-1.388 1.14-.35.1-.706.157-1'
      '.07.173-.95.045-1.773-.6-1.943-1.536a1.88 1.88 0 011.038-2.022c.323-.16.'
      '67-.25 1.018-.324.378-.082.758-.153 1.134-.24.274-.063.457-.23.51-.516a.'
      '904.904 0 00.02-.193c0-1.815 0-3.63-.002-5.443a.725.725 0 00-.026-.185c-'
      '.04-.15-.15-.243-.304-.234-.16.01-.318.035-.475.066-.76.15-1.52.303-2.28'
      '.456l-2.325.47-1.374.278c-.016.003-.032.01-.048.013-.277.077-.377.203-.3'
      '9.49-.002.042 0 .086 0 .13-.002 2.602 0 5.204-.003 7.805 0 .42-.047.836-'
      '.215 1.227-.278.64-.77 1.04-1.434 1.233-.35.1-.71.16-1.075.172-.96.036-1'
      '.755-.6-1.92-1.544-.14-.812.23-1.685 1.154-2.075.357-.15.73-.232 1.108-.'
      '31.287-.06.575-.116.86-.177.383-.083.583-.323.6-.714v-.15c0-2.96 0-5.922'
      '.002-8.882 0-.123.013-.25.042-.37.07-.285.273-.448.546-.518.255-.066.515'
      '-.112.774-.165.733-.15 1.466-.296 2.2-.444l2.27-.46c.67-.134 1.34-.27 2.'
      '01-.403.22-.043.442-.088.663-.106.31-.025.523.17.554.482.008.073.012.148'
      '.012.223.002 1.91.002 3.822 0 5.732z';

  static const _youTubeMusicPath =
      'M12 0C5.376 0 0 5.376 0 12s5.376 12 12 12 12-5.376 12-12S18.624 0 12 0zm'
      '0 19.104c-3.924 0-7.104-3.18-7.104-7.104S8.076 4.896 12 4.896s7.104 3.18'
      ' 7.104 7.104-3.18 7.104-7.104 7.104zm0-13.332c-3.432 0-6.228 2.796-6.228'
      ' 6.228S8.568 18.228 12 18.228s6.228-2.796 6.228-6.228S15.432 5.772 12 5.'
      '772zM9.684 15.54V8.46L15.816 12l-6.132 3.54z';

  /// A plain music note, for a player we have no mark for.
  ///
  /// Not a brand: this is drawn by us, so unlike the three above it can be
  /// recoloured and scaled freely. It stands in whenever the media session
  /// belongs to an app outside the three services — a local-files player, a
  /// podcast app, a radio stream — which the media-session bridge reports as
  /// [MusicProviderService.device].
  static const _devicePath =
      'M12 3v10.55A4 4 0 1014 17V7h4V3h-6zm0 14a2 2 0 11-2-2 2 2 0 012 2z';

  static String pathData(MusicProviderService service) {
    switch (service) {
      case MusicProviderService.spotify:
        return _spotifyPath;
      case MusicProviderService.appleMusic:
        return _appleMusicPath;
      case MusicProviderService.youtubeMusic:
        return _youTubeMusicPath;
      case MusicProviderService.device:
        return _devicePath;
    }
  }

  /// The mark in its brand colours: a backing shape plus the outline on top,
  /// so the holes read as the logo's counter-colour.
  static String fullColour(MusicProviderService service) {
    switch (service) {
      case MusicProviderService.spotify:
        // Black disc behind, Spotify Green outline in front -> green disc with
        // black waves.
        return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
            '<circle cx="12" cy="12" r="12" fill="#000000"/>'
            '<path fill="#1ED760" d="$_spotifyPath"/>'
            '</svg>';
      case MusicProviderService.appleMusic:
        // White tile behind, pink-to-red gradient outline in front -> the
        // gradient tile with a white note.
        return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
            '<defs><linearGradient id="am" x1="0" y1="0" x2="0" y2="1">'
            '<stop offset="0" stop-color="#FB5C74"/>'
            '<stop offset="1" stop-color="#FA233B"/>'
            '</linearGradient></defs>'
            '<rect x="0" y="0" width="24" height="24" rx="5.4" fill="#FFFFFF"/>'
            '<path fill="url(#am)" d="$_appleMusicPath"/>'
            '</svg>';
      case MusicProviderService.youtubeMusic:
        // White disc behind, red outline in front -> red disc with a white
        // ring and play triangle.
        return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
            '<circle cx="12" cy="12" r="12" fill="#FFFFFF"/>'
            '<path fill="#FF0000" d="$_youTubeMusicPath"/>'
            '</svg>';
      case MusicProviderService.device:
        // No backing shape: an unbranded note sits directly on whatever
        // surface it is drawn over, so it reads as an icon rather than as a
        // logo we are pretending to own.
        return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
            '<path fill="#E5E5EA" d="$_devicePath"/>'
            '</svg>';
    }
  }

  /// The outline alone in a single colour, for watermarks and small chips.
  ///
  /// SVG has no place for the alpha channel inside a `fill` hex, so it is
  /// carried separately — without this the faded watermark would paint at full
  /// strength and swamp the button label.
  static String monochrome(MusicProviderService service, Color color) {
    final argb = color.toARGB32();
    final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final opacity = ((argb >> 24) & 0xFF) / 255;

    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
        '<path fill="#${rgb.toUpperCase()}" '
        'fill-opacity="${opacity.toStringAsFixed(3)}" '
        'd="${pathData(service)}"/>'
        '</svg>';
  }
}

/// A service mark at [size], in brand colours by default.
///
/// Pass [color] to get the flat single-colour outline instead — used for the
/// oversized watermark that sits behind each connect button.
class MusicServiceLogo extends StatelessWidget {
  const MusicServiceLogo({
    required this.service,
    this.size = 32,
    this.color,
    super.key,
  });

  final MusicProviderService service;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final flat = color;
    return SvgPicture.string(
      flat == null
          ? MusicBrandArtwork.fullColour(service)
          : MusicBrandArtwork.monochrome(service, flat),
      width: size,
      height: size,
    );
  }
}
