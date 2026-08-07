import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'apple_music_config.dart';
import 'music_token_store.dart';
import 'pkce_oauth_client.dart';

/// Apple Music sign-in via the MusicKit web authorization flow.
///
/// See [AppleMusicConfig] for what has to exist server-side first. The Music
/// User Token this returns does not expire on a fixed clock the way an OAuth
/// access token does — Apple invalidates it when the user revokes access — so
/// there is no refresh step. A 401 from the Apple Music API is the signal to
/// clear it and reconnect.
class AppleMusicAuthService implements MusicAccessTokenSource {
  AppleMusicAuthService({required MusicTokenStore tokenStore})
      : _tokenStore = tokenStore;

  final MusicTokenStore _tokenStore;

  Future<MusicTokens> connect() async {
    if (!AppleMusicConfig.isConfigured) {
      throw const MusicAuthException(AppleMusicConfig.setupHint);
    }

    final authUrl = Uri.parse(AppleMusicConfig.authBridgeUrl).replace(
      queryParameters: {'redirect_uri': AppleMusicConfig.redirectUri},
    );

    final String result;
    try {
      result = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: AppleMusicConfig.callbackScheme,
      );
    } catch (_) {
      throw const MusicAuthException('Apple Music sign-in was cancelled.');
    }

    final returned = Uri.parse(result);
    final error = returned.queryParameters['error'];
    if (error != null) {
      throw MusicAuthException('Apple Music denied the request: $error');
    }

    final userToken = returned.queryParameters['music_user_token'];
    if (userToken == null || userToken.isEmpty) {
      throw const MusicAuthException(
        'Apple Music did not return a user token.',
      );
    }

    final tokens = MusicTokens(accessToken: userToken);
    await _tokenStore.save(tokens);
    return tokens;
  }

  @override
  Future<String?> currentAccessToken() async =>
      (await _tokenStore.read())?.accessToken;

  @override
  Future<bool> isConnected() async => (await _tokenStore.read()) != null;

  @override
  Future<void> disconnect() => _tokenStore.clear();
}
