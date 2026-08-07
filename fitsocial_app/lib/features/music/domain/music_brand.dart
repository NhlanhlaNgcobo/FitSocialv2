import 'package:flutter/material.dart';

import '../../main/domain/app_models.dart';

/// Per-service brand palette and copy for the connect flow.
///
/// Colours are taken from each service's published brand guidance:
///  - Spotify Green `#1DB954`, paired only with black or white as the
///    guidelines require.
///  - Apple Music's pink-to-red icon gradient, `#FB5C74` -> `#FA233B`.
///  - YouTube red `#FF0000` on black.
class MusicBrand {
  const MusicBrand({
    required this.service,
    required this.name,
    required this.tagline,
    required this.buttonColors,
    required this.foreground,
    required this.accent,
    this.comingSoon = false,
  });

  final MusicProviderService service;
  final String name;

  /// One line under the service name inside the connect button.
  final String tagline;

  /// Button background. A single entry paints flat; two paint a gradient.
  final List<Color> buttonColors;

  /// Text/icon colour that meets contrast on [buttonColors].
  final Color foreground;

  /// The service colour used for chips and highlights elsewhere in the app.
  final Color accent;

  /// Held back on purpose. The button still shows the brand so users can see
  /// it is planned, but it sits under a shade and does not open a sign-in page.
  final bool comingSoon;

  static const spotify = MusicBrand(
    service: MusicProviderService.spotify,
    name: 'Spotify',
    tagline: 'Playlists, search and playback control',
    // Spotify Green on black is the sanctioned pairing for a dark UI.
    buttonColors: [Color(0xFF1DB954), Color(0xFF1ED760)],
    foreground: Color(0xFF000000),
    accent: Color(0xFF1ED760),
  );

  // Paused for now: MusicKit has no native Android SDK, and its developer
  // token has to be minted server-side off an Apple Developer account. The
  // auth path is written and waiting behind AppleMusicConfig — flipping
  // [comingSoon] to false is all that turns the button back on.
  static const appleMusic = MusicBrand(
    service: MusicProviderService.appleMusic,
    name: 'Apple Music',
    tagline: 'Your library and Apple Music catalogue',
    buttonColors: [Color(0xFFFB5C74), Color(0xFFFA233B)],
    foreground: Color(0xFFFFFFFF),
    accent: Color(0xFFFA233B),
    comingSoon: true,
  );

  // Paused alongside Apple Music until the Google OAuth client is registered
  // and its reversed-client-ID callback is added to the manifest. The PKCE
  // flow itself is finished — see YouTubeMusicConfig — so clearing
  // [comingSoon] plus filling in the client ID is the whole job.
  static const youTubeMusic = MusicBrand(
    service: MusicProviderService.youtubeMusic,
    name: 'YouTube Music',
    tagline: 'Playlists from your Google account',
    buttonColors: [Color(0xFFFF0000), Color(0xFFCC0000)],
    foreground: Color(0xFFFFFFFF),
    accent: Color(0xFFFF0000),
    comingSoon: true,
  );

  static const all = <MusicBrand>[spotify, appleMusic, youTubeMusic];

  static MusicBrand of(MusicProviderService service) {
    switch (service) {
      case MusicProviderService.spotify:
        return spotify;
      case MusicProviderService.appleMusic:
        return appleMusic;
      case MusicProviderService.youtubeMusic:
        return youTubeMusic;
    }
  }
}
