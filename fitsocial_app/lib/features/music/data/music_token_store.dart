import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A music-service session persisted between app launches.
///
/// [refreshToken] and [expiresAt] are nullable because not every service hands
/// them out: Apple Music's MusicKit returns a single long-lived user token with
/// no refresh companion, while Spotify and Google both issue refreshable
/// short-lived tokens.
class MusicTokens {
  const MusicTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

  /// Treat the token as expired a minute early so an in-flight request
  /// doesn't race the expiry.
  bool get isExpired {
    final expiry = expiresAt;
    if (expiry == null) return false;
    return DateTime.now().isAfter(expiry.subtract(const Duration(minutes: 1)));
  }
}

/// Persists music-service tokens in platform-encrypted storage (Android
/// Keystore / iOS Keychain). Refresh tokens are long-lived credentials — they
/// must never go in SharedPreferences or Firestore documents the client can
/// read.
///
/// One store per service; [serviceKey] namespaces the entries so connecting
/// Spotify never clobbers a YouTube Music session.
class MusicTokenStore {
  // v10+ encrypts on Android by default; no extra options needed.
  MusicTokenStore({
    required this.serviceKey,
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final String serviceKey;
  final FlutterSecureStorage _storage;

  String get _accessTokenKey => '${serviceKey}_access_token';
  String get _refreshTokenKey => '${serviceKey}_refresh_token';
  String get _expiresAtKey => '${serviceKey}_expires_at';

  Future<void> save(MusicTokens tokens) async {
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: tokens.accessToken),
      _storage.write(key: _refreshTokenKey, value: tokens.refreshToken),
      _storage.write(
        key: _expiresAtKey,
        value: tokens.expiresAt?.toIso8601String(),
      ),
    ]);
  }

  Future<MusicTokens?> read() async {
    try {
      final accessToken = await _storage.read(key: _accessTokenKey);
      if (accessToken == null) return null;

      final refreshToken = await _storage.read(key: _refreshTokenKey);
      final expiresAtRaw = await _storage.read(key: _expiresAtKey);
      return MusicTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt:
            expiresAtRaw == null ? null : DateTime.tryParse(expiresAtRaw),
      );
    } catch (_) {
      // Corrupt/unreadable keystore entry — treat as signed out.
      return null;
    }
  }

  /// Best-effort erase.
  ///
  /// A throw here would leave the caller mid-logout: the UI still showing the
  /// account as connected, with no way out. [read] already treats an
  /// unreadable entry as signed out, so a failed delete lands in the same
  /// place — the app forgets the session either way.
  Future<void> clear() async {
    try {
      await Future.wait([
        _storage.delete(key: _accessTokenKey),
        _storage.delete(key: _refreshTokenKey),
        _storage.delete(key: _expiresAtKey),
      ]);
    } catch (_) {
      // Nothing useful to do: the session is being abandoned regardless.
    }
  }
}
