import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import 'spotify_config.dart';
import 'spotify_token_store.dart';

class SpotifyAuthException implements Exception {
  const SpotifyAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Spotify OAuth using Authorization Code + PKCE.
///
/// PKCE is the correct flow for mobile: it needs no client secret, so nothing
/// extractable from the APK can be used to impersonate the app. The client
/// secret must never ship in the binary.
class SpotifyAuthService {
  SpotifyAuthService({
    required SpotifyTokenStore tokenStore,
    http.Client? httpClient,
  })  : _tokenStore = tokenStore,
        _http = httpClient ?? http.Client();

  final SpotifyTokenStore _tokenStore;
  final http.Client _http;

  static final _authorizeEndpoint =
      Uri.parse('https://accounts.spotify.com/authorize');
  static final _tokenEndpoint =
      Uri.parse('https://accounts.spotify.com/api/token');

  /// Launches the Spotify consent screen and exchanges the returned code
  /// for tokens. Throws [SpotifyAuthException] on cancel/failure.
  Future<SpotifyTokens> connect() async {
    final verifier = _generateCodeVerifier();
    final challenge = _deriveCodeChallenge(verifier);
    final state = _randomString(16);

    final authUrl = _authorizeEndpoint.replace(queryParameters: {
      'client_id': SpotifyConfig.clientId,
      'response_type': 'code',
      'redirect_uri': SpotifyConfig.redirectUri,
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
      'state': state,
      'scope': SpotifyConfig.scopes.join(' '),
    });

    final String result;
    try {
      result = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: SpotifyConfig.callbackScheme,
      );
    } catch (e) {
      throw const SpotifyAuthException('Spotify sign-in was cancelled.');
    }

    final returned = Uri.parse(result);
    final error = returned.queryParameters['error'];
    if (error != null) {
      throw SpotifyAuthException('Spotify denied the request: $error');
    }

    // Guard against a forged callback.
    if (returned.queryParameters['state'] != state) {
      throw const SpotifyAuthException(
        'Spotify returned a mismatched state value.',
      );
    }

    final code = returned.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw const SpotifyAuthException('Spotify did not return an auth code.');
    }

    final tokens = await _exchangeCode(code: code, verifier: verifier);
    await _tokenStore.save(tokens);
    return tokens;
  }

  Future<void> disconnect() => _tokenStore.clear();

  /// Returns a usable access token, refreshing it when expired.
  /// Returns null when the user has not connected Spotify.
  Future<String?> currentAccessToken() async {
    final stored = await _tokenStore.read();
    if (stored == null) return null;
    if (!stored.isExpired) return stored.accessToken;

    try {
      final refreshed = await _refresh(stored.refreshToken);
      await _tokenStore.save(refreshed);
      return refreshed.accessToken;
    } catch (_) {
      // Refresh token revoked or invalid — force a clean reconnect.
      await _tokenStore.clear();
      return null;
    }
  }

  Future<bool> isConnected() async => (await _tokenStore.read()) != null;

  Future<SpotifyTokens> _exchangeCode({
    required String code,
    required String verifier,
  }) async {
    final response = await _http.post(
      _tokenEndpoint,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': SpotifyConfig.redirectUri,
        'client_id': SpotifyConfig.clientId,
        'code_verifier': verifier,
      },
    );

    if (response.statusCode != 200) {
      throw SpotifyAuthException(
        'Token exchange failed (${response.statusCode}): ${response.body}',
      );
    }
    return _parseTokens(response.body, fallbackRefreshToken: null);
  }

  Future<SpotifyTokens> _refresh(String refreshToken) async {
    final response = await _http.post(
      _tokenEndpoint,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': SpotifyConfig.clientId,
      },
    );

    if (response.statusCode != 200) {
      throw SpotifyAuthException(
        'Token refresh failed (${response.statusCode}).',
      );
    }
    // Spotify may omit refresh_token on refresh — keep the existing one.
    return _parseTokens(response.body, fallbackRefreshToken: refreshToken);
  }

  SpotifyTokens _parseTokens(
    String body, {
    required String? fallbackRefreshToken,
  }) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final accessToken = json['access_token'] as String?;
    final refreshToken =
        (json['refresh_token'] as String?) ?? fallbackRefreshToken;
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;

    if (accessToken == null || refreshToken == null) {
      throw const SpotifyAuthException(
        'Spotify response was missing tokens.',
      );
    }

    return SpotifyTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  // --- PKCE helpers ---

  String _generateCodeVerifier() => _randomString(64);

  String _deriveCodeChallenge(String verifier) {
    final digest = sha256.convert(ascii.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  String _randomString(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }
}
