/// Spotify app credentials and OAuth configuration.
///
/// The client ID is public by design — it ships inside the APK and is safe to
/// expose. The client *secret* is deliberately absent: PKCE does not need it,
/// and embedding it in a mobile binary would let anyone impersonate this app.
class SpotifyConfig {
  const SpotifyConfig._();

  static const clientId = 'd901cd2b06734efb814b22f23f1bf31b';

  /// Must match a Redirect URI registered in the Spotify developer dashboard
  /// exactly, and the intent-filter scheme/host in AndroidManifest.xml.
  static const callbackScheme = 'fitsocial';
  static const callbackHost = 'spotify-callback';
  static const redirectUri = '$callbackScheme://$callbackHost';

  /// Scopes requested at connect time.
  ///
  /// Playback control scopes (streaming / *-playback-state) only take effect
  /// for Spotify Premium accounts; reading playlists and profile works on
  /// free accounts too.
  static const scopes = <String>[
    'user-read-private',
    'user-read-email',
    'playlist-read-private',
    'playlist-read-collaborative',
    'playlist-modify-public',
    'playlist-modify-private',
    'user-top-read',
    'user-read-playback-state',
    'user-modify-playback-state',
  ];
}
