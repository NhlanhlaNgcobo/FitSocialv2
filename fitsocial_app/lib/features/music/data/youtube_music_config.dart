import 'pkce_oauth_client.dart';

/// YouTube Music sign-in configuration.
///
/// YouTube Music has no OAuth surface of its own — it is a YouTube product, so
/// the account connection goes through Google's OAuth 2.0 endpoint with the
/// YouTube scopes. Signing in there is the same "choose a Google account"
/// screen users see for YouTube Music on the web.
///
/// ## Setting this up
/// 1. Google Cloud console -> APIs & Services -> Enable "YouTube Data API v3".
/// 2. Credentials -> Create OAuth client ID -> **Android** (and iOS for the
///    iOS build). Register the package name `com.fitsocial.fitsocial_app` —
///    it must match `applicationId` in android/app/build.gradle.kts — plus the
///    debug and release SHA-1 fingerprints.
/// 3. Paste the generated client ID into [clientId] below.
///
/// Installed-app clients have no secret, which is why PKCE is mandatory here.
class YouTubeMusicConfig {
  const YouTubeMusicConfig._();

  /// e.g. '801328750075-abc123def456.apps.googleusercontent.com'.
  ///
  /// Left empty until the OAuth client is created; the connect sheet reads
  /// [PkceOAuthConfig.isConfigured] and explains the setup step instead of
  /// opening a sign-in page that would immediately error.
  static const clientId = '';

  /// Google requires installed apps to redirect to the *reversed* client ID.
  /// `123-abc.apps.googleusercontent.com` becomes the URL scheme
  /// `com.googleusercontent.apps.123-abc`.
  static String get callbackScheme {
    const suffix = '.apps.googleusercontent.com';
    if (!clientId.endsWith(suffix)) return '';
    final id = clientId.substring(0, clientId.length - suffix.length);
    return 'com.googleusercontent.apps.$id';
  }

  static String get redirectUri => '$callbackScheme:/oauth2redirect';

  /// Read-only is all the app needs: it lists the user's YouTube Music
  /// playlists. Nothing here can modify or upload to their account.
  static const scopes = <String>[
    'https://www.googleapis.com/auth/youtube.readonly',
    'https://www.googleapis.com/auth/userinfo.profile',
  ];

  static PkceOAuthConfig get oauth => PkceOAuthConfig(
        serviceName: 'YouTube Music',
        clientId: clientId,
        authorizationEndpoint: Uri.https(
          'accounts.google.com',
          '/o/oauth2/v2/auth',
        ),
        tokenEndpoint: Uri.https('oauth2.googleapis.com', '/token'),
        redirectUri: redirectUri,
        callbackScheme: callbackScheme,
        scopes: scopes,
        // Google only issues a refresh token when both of these are present,
        // and only on the first consent — without `prompt=consent` a returning
        // user gets an access token that dies in an hour with no way to renew.
        extraAuthParams: const {
          'access_type': 'offline',
          'prompt': 'consent',
        },
      );
}
