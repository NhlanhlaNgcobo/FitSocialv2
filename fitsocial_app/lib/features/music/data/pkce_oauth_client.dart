import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import 'music_token_store.dart';

class MusicAuthException implements Exception {
  const MusicAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Anything that can hand an API service a currently-valid access token.
///
/// Both the PKCE services (Spotify, YouTube Music) and Apple Music's MusicKit
/// flow satisfy this, so API wrappers don't care how the token was obtained.
abstract interface class MusicAccessTokenSource {
  /// A usable access token, refreshed if needed, or null when the user has
  /// not connected this service.
  Future<String?> currentAccessToken();

  Future<bool> isConnected();

  Future<void> disconnect();
}

/// Everything that differs between one OAuth provider and the next.
class PkceOAuthConfig {
  const PkceOAuthConfig({
    required this.serviceName,
    required this.clientId,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.redirectUri,
    required this.callbackScheme,
    required this.scopes,
    this.extraAuthParams = const <String, String>{},
    this.scopeSeparator = ' ',
  });

  final String serviceName;
  final String clientId;
  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final String redirectUri;

  /// The custom URL scheme the redirect uses, registered in the Android
  /// manifest and the iOS Info.plist so the browser can hand control back.
  final String callbackScheme;

  final List<String> scopes;
  final Map<String, String> extraAuthParams;
  final String scopeSeparator;

  /// False when the app owner hasn't filled in a client ID yet, which lets the
  /// UI explain the setup step instead of bouncing the user to a broken page.
  bool get isConfigured => clientId.isNotEmpty;
}

/// OAuth 2.0 Authorization Code + PKCE.
///
/// PKCE is the correct flow for mobile: it needs no client secret, so nothing
/// extractable from the APK can be used to impersonate the app. The client
/// secret must never ship in the binary.
class PkceOAuthClient implements MusicAccessTokenSource {
  PkceOAuthClient({
    required this.config,
    required MusicTokenStore tokenStore,
    http.Client? httpClient,
  })  : _tokenStore = tokenStore,
        _http = httpClient ?? http.Client();

  final PkceOAuthConfig config;
  final MusicTokenStore _tokenStore;
  final http.Client _http;

  /// Launches the provider's consent screen and exchanges the returned code
  /// for tokens. Throws [MusicAuthException] on cancel/failure.
  Future<MusicTokens> connect() async {
    if (!config.isConfigured) {
      throw MusicAuthException(
        '${config.serviceName} is not set up yet: no client ID is configured '
        'in this build.',
      );
    }

    final verifier = _generateCodeVerifier();
    final challenge = _deriveCodeChallenge(verifier);
    final state = _randomString(16);

    final authUrl = config.authorizationEndpoint.replace(queryParameters: {
      'client_id': config.clientId,
      'response_type': 'code',
      'redirect_uri': config.redirectUri,
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
      'state': state,
      'scope': config.scopes.join(config.scopeSeparator),
      ...config.extraAuthParams,
    });

    final String result;
    try {
      result = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: config.callbackScheme,
      );
    } on PlatformException catch (e) {
      // Only CANCELED is the user changing their mind. Reporting the rest as
      // "cancelled" — as this used to — throws away the one piece of
      // information that says what actually broke.
      if (e.code == 'CANCELED') {
        throw MusicAuthException(
          '${config.serviceName} sign-in was cancelled.',
        );
      }
      throw MusicAuthException(
        '${config.serviceName} sign-in failed (${e.code}): '
        '${e.message ?? 'no details given'}',
      );
    } catch (e) {
      throw MusicAuthException(
        '${config.serviceName} sign-in could not start: $e',
      );
    }

    final returned = Uri.parse(result);
    final error = returned.queryParameters['error'];
    if (error != null) {
      throw MusicAuthException(
        '${config.serviceName} denied the request: $error',
      );
    }

    // Guard against a forged callback.
    if (returned.queryParameters['state'] != state) {
      throw MusicAuthException(
        '${config.serviceName} returned a mismatched state value.',
      );
    }

    final code = returned.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw MusicAuthException(
        '${config.serviceName} did not return an auth code.',
      );
    }

    final tokens = await _exchangeCode(code: code, verifier: verifier);
    await _tokenStore.save(tokens);
    return tokens;
  }

  @override
  Future<void> disconnect() => _tokenStore.clear();

  @override
  Future<String?> currentAccessToken() async {
    final stored = await _tokenStore.read();
    if (stored == null) return null;
    if (!stored.isExpired) return stored.accessToken;

    final refreshToken = stored.refreshToken;
    if (refreshToken == null) {
      await _tokenStore.clear();
      return null;
    }

    try {
      final refreshed = await _refresh(refreshToken);
      await _tokenStore.save(refreshed);
      return refreshed.accessToken;
    } catch (_) {
      // Refresh token revoked or invalid — force a clean reconnect.
      await _tokenStore.clear();
      return null;
    }
  }

  @override
  Future<bool> isConnected() async => (await _tokenStore.read()) != null;

  Future<MusicTokens> _exchangeCode({
    required String code,
    required String verifier,
  }) async {
    final response = await _http.post(
      config.tokenEndpoint,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': config.redirectUri,
        'client_id': config.clientId,
        'code_verifier': verifier,
      },
    );

    if (response.statusCode != 200) {
      throw MusicAuthException(
        'Token exchange failed (${response.statusCode}): ${response.body}',
      );
    }
    return _parseTokens(response.body, fallbackRefreshToken: null);
  }

  Future<MusicTokens> _refresh(String refreshToken) async {
    final response = await _http.post(
      config.tokenEndpoint,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': config.clientId,
      },
    );

    if (response.statusCode != 200) {
      throw MusicAuthException(
        'Token refresh failed (${response.statusCode}).',
      );
    }
    // Providers commonly omit refresh_token on refresh — keep the existing one.
    return _parseTokens(response.body, fallbackRefreshToken: refreshToken);
  }

  MusicTokens _parseTokens(
    String body, {
    required String? fallbackRefreshToken,
  }) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final accessToken = json['access_token'] as String?;
    final refreshToken =
        (json['refresh_token'] as String?) ?? fallbackRefreshToken;
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;

    if (accessToken == null) {
      throw MusicAuthException(
        '${config.serviceName} response was missing an access token.',
      );
    }

    return MusicTokens(
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
