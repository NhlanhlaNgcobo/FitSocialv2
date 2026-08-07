/// Apple Music (MusicKit) sign-in configuration.
///
/// Apple Music is the odd one out: it is not OAuth. Getting a Music User Token
/// takes two pieces:
///
/// 1. **A developer token** — an ES256 JWT signed with a MusicKit private key
///    (`.p8`), carrying the team ID as `iss` and the key ID as `kid`. That key
///    is a secret and must never ship inside the APK, so the token has to be
///    minted server-side. This project already runs Cloud Functions, which is
///    where [developerTokenEndpoint] should point.
///
/// 2. **A user token** — obtained by loading MusicKit JS in a web page and
///    calling `music.authorize()`, which opens Apple's own sign-in at
///    `authorize.music.apple.com`. There is no native Android MusicKit SDK, so
///    a small hosted bridge page stands in for it.
///
/// ## The bridge page
/// [authBridgeUrl] must serve a page that:
///   - loads `https://js-cdn.music.apple.com/musickit/v3/musickit.js`,
///   - configures MusicKit with the developer token,
///   - calls `music.authorize()` on load,
///   - and finally redirects to
///     `fitsocial://apple-music-callback?music_user_token=<token>`
///     (or `?error=<reason>` when the user declines).
///
/// Until both values are filled in, [isConfigured] stays false and the connect
/// sheet explains what is missing instead of opening a page that would fail.
class AppleMusicConfig {
  const AppleMusicConfig._();

  /// Cloud Function that returns `{"token": "<developer JWT>"}`.
  static const developerTokenEndpoint = '';

  /// Hosted MusicKit JS page that performs `music.authorize()`.
  static const authBridgeUrl = '';

  /// Must match the intent-filter scheme/host in AndroidManifest.xml.
  static const callbackScheme = 'fitsocial';
  static const callbackHost = 'apple-music-callback';
  static const redirectUri = '$callbackScheme://$callbackHost';

  static bool get isConfigured => authBridgeUrl.isNotEmpty;

  /// What to tell the user when it isn't set up yet.
  static const setupHint =
      'Apple Music needs a MusicKit developer token from an Apple Developer '
      'account (\$99/year) before it can be connected.';
}
