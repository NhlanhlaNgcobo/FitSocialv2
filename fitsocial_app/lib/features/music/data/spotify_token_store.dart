import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A Spotify OAuth session persisted between app launches.
class SpotifyTokens {
  const SpotifyTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  /// Treat the token as expired a minute early so an in-flight request
  /// doesn't race the expiry.
  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 1)));
}

/// Persists Spotify tokens in platform-encrypted storage (Android Keystore /
/// iOS Keychain). Refresh tokens are long-lived credentials — they must never
/// go in SharedPreferences or Firestore documents the client can read.
class SpotifyTokenStore {
  // v10+ encrypts on Android by default; no extra options needed.
  SpotifyTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kAccessToken = 'spotify_access_token';
  static const _kRefreshToken = 'spotify_refresh_token';
  static const _kExpiresAt = 'spotify_expires_at';

  Future<void> save(SpotifyTokens tokens) async {
    await Future.wait([
      _storage.write(key: _kAccessToken, value: tokens.accessToken),
      _storage.write(key: _kRefreshToken, value: tokens.refreshToken),
      _storage.write(
        key: _kExpiresAt,
        value: tokens.expiresAt.toIso8601String(),
      ),
    ]);
  }

  Future<SpotifyTokens?> read() async {
    try {
      final accessToken = await _storage.read(key: _kAccessToken);
      final refreshToken = await _storage.read(key: _kRefreshToken);
      final expiresAtRaw = await _storage.read(key: _kExpiresAt);
      if (accessToken == null || refreshToken == null || expiresAtRaw == null) {
        return null;
      }
      final expiresAt = DateTime.tryParse(expiresAtRaw);
      if (expiresAt == null) return null;
      return SpotifyTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: expiresAt,
      );
    } catch (_) {
      // Corrupt/unreadable keystore entry — treat as signed out.
      return null;
    }
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _kAccessToken),
      _storage.delete(key: _kRefreshToken),
      _storage.delete(key: _kExpiresAt),
    ]);
  }
}
