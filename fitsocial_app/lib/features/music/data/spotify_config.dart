import 'pkce_oauth_client.dart';

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

  /// The redirect the *App Remote* handshake uses, which is a separate URI
  /// from [redirectUri] on purpose.
  ///
  /// Spotify's auth library registers its own callback activity for whatever
  /// these placeholders spell (see `manifestPlaceholders` in
  /// android/app/build.gradle.kts). Pointing it at the same host as
  /// flutter_web_auth_2's callback would leave two activities claiming one URI,
  /// and Android answers that with an app-chooser dialog in the middle of
  /// sign-in.
  ///
  /// Both URIs must be registered in the Spotify dashboard.
  static const appRemoteCallbackHost = 'spotify-sdk-auth';
  static const appRemoteRedirectUri =
      '$callbackScheme://$appRemoteCallbackHost';

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
    'user-read-currently-playing',
    'user-modify-playback-state',
  ];

  static PkceOAuthConfig get oauth => PkceOAuthConfig(
        serviceName: 'Spotify',
        clientId: clientId,
        authorizationEndpoint: Uri.https('accounts.spotify.com', '/authorize'),
        tokenEndpoint: Uri.https('accounts.spotify.com', '/api/token'),
        redirectUri: redirectUri,
        callbackScheme: callbackScheme,
        scopes: scopes,
      );
}
