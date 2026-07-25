import 'dart:convert';

import 'package:http/http.dart' as http;

import 'spotify_auth_service.dart';

/// The connected Spotify account.
class SpotifyProfile {
  const SpotifyProfile({
    required this.displayName,
    required this.email,
    required this.isPremium,
    this.imageUrl,
  });

  final String displayName;
  final String? email;

  /// Playback control requires Premium; reads work on free accounts.
  final bool isPremium;
  final String? imageUrl;
}

/// A playlist from the user's Spotify library.
class SpotifyPlaylist {
  const SpotifyPlaylist({
    required this.id,
    required this.name,
    required this.trackCount,
    required this.owner,
    this.imageUrl,
  });

  final String id;
  final String name;
  final int trackCount;
  final String owner;
  final String? imageUrl;
}

class SpotifyApiException implements Exception {
  const SpotifyApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thin wrapper over the Spotify Web API. Every call transparently uses (and
/// refreshes) the stored OAuth token.
class SpotifyApiService {
  SpotifyApiService({
    required SpotifyAuthService authService,
    http.Client? httpClient,
  })  : _auth = authService,
        _http = httpClient ?? http.Client();

  final SpotifyAuthService _auth;
  final http.Client _http;

  static const _base = 'https://api.spotify.com/v1';

  Future<Map<String, dynamic>> _get(String path, {
    Map<String, String>? query,
  }) async {
    final token = await _auth.currentAccessToken();
    if (token == null) {
      throw const SpotifyApiException('Spotify is not connected.');
    }

    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final response = await _http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 401) {
      throw const SpotifyApiException(
        'Spotify session expired. Reconnect your account.',
      );
    }
    if (response.statusCode == 403) {
      throw const SpotifyApiException(
        'Spotify denied this request. If your app is in development mode, '
        'the account must be added to the dashboard user list.',
      );
    }
    if (response.statusCode != 200) {
      throw SpotifyApiException(
        'Spotify request failed (${response.statusCode}).',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<SpotifyProfile> fetchProfile() async {
    final json = await _get('/me');
    final images = json['images'] as List<dynamic>?;
    return SpotifyProfile(
      displayName: (json['display_name'] as String?) ?? 'Spotify user',
      email: json['email'] as String?,
      isPremium: (json['product'] as String?) == 'premium',
      imageUrl: (images != null && images.isNotEmpty)
          ? (images.first as Map<String, dynamic>)['url'] as String?
          : null,
    );
  }

  /// The user's own playlists.
  Future<List<SpotifyPlaylist>> fetchMyPlaylists({int limit = 20}) async {
    final json = await _get('/me/playlists', query: {'limit': '$limit'});
    return _parsePlaylists(json['items'] as List<dynamic>?);
  }

  /// Playlist search — used to surface workout-appropriate playlists
  /// (e.g. query 'running', 'hiit', 'lifting').
  Future<List<SpotifyPlaylist>> searchPlaylists(
    String query, {
    int limit = 20,
  }) async {
    final json = await _get('/search', query: {
      'q': query,
      'type': 'playlist',
      'limit': '$limit',
    });
    final playlists = json['playlists'] as Map<String, dynamic>?;
    return _parsePlaylists(playlists?['items'] as List<dynamic>?);
  }

  List<SpotifyPlaylist> _parsePlaylists(List<dynamic>? items) {
    if (items == null) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final images = item['images'] as List<dynamic>?;
          final tracks = item['tracks'] as Map<String, dynamic>?;
          final owner = item['owner'] as Map<String, dynamic>?;
          return SpotifyPlaylist(
            id: (item['id'] as String?) ?? '',
            name: (item['name'] as String?) ?? 'Untitled',
            trackCount: (tracks?['total'] as num?)?.toInt() ?? 0,
            owner: (owner?['display_name'] as String?) ?? 'Spotify',
            imageUrl: (images != null && images.isNotEmpty)
                ? (images.first as Map<String, dynamic>)['url'] as String?
                : null,
          );
        })
        .where((p) => p.id.isNotEmpty)
        .toList(growable: false);
  }
}
