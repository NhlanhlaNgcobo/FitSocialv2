import 'dart:convert';

import 'package:http/http.dart' as http;

import 'pkce_oauth_client.dart';

/// The connected YouTube (Music) account.
class YouTubeMusicProfile {
  const YouTubeMusicProfile({
    required this.displayName,
    this.imageUrl,
  });

  final String displayName;
  final String? imageUrl;
}

/// A playlist from the connected YouTube account.
class YouTubeMusicPlaylist {
  const YouTubeMusicPlaylist({
    required this.id,
    required this.title,
    required this.itemCount,
    this.thumbnailUrl,
  });

  final String id;
  final String title;
  final int itemCount;
  final String? thumbnailUrl;
}

class YouTubeMusicApiException implements Exception {
  const YouTubeMusicApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Read-only wrapper over the YouTube Data API v3.
///
/// YouTube Music does not expose a public playback API, so this covers account
/// and library reads only — the player's transport controls are Spotify-only
/// for now, which the player UI states plainly rather than showing dead
/// buttons.
class YouTubeMusicApiService {
  YouTubeMusicApiService({
    required MusicAccessTokenSource authService,
    http.Client? httpClient,
  })  : _auth = authService,
        _http = httpClient ?? http.Client();

  final MusicAccessTokenSource _auth;
  final http.Client _http;

  static const _base = 'https://www.googleapis.com/youtube/v3';

  Future<Map<String, dynamic>> _get(
    String url, {
    Map<String, String>? query,
  }) async {
    final token = await _auth.currentAccessToken();
    if (token == null) {
      throw const YouTubeMusicApiException('YouTube Music is not connected.');
    }

    final uri = Uri.parse(url).replace(queryParameters: query);
    final response = await _http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 401) {
      throw const YouTubeMusicApiException(
        'YouTube Music session expired. Reconnect your account.',
      );
    }
    if (response.statusCode != 200) {
      throw YouTubeMusicApiException(
        'YouTube Music request failed (${response.statusCode}).',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<YouTubeMusicProfile> fetchProfile() async {
    final json = await _get(
      'https://www.googleapis.com/oauth2/v3/userinfo',
    );
    return YouTubeMusicProfile(
      displayName: (json['name'] as String?) ?? 'YouTube Music user',
      imageUrl: json['picture'] as String?,
    );
  }

  Future<List<YouTubeMusicPlaylist>> fetchMyPlaylists({int limit = 20}) async {
    final json = await _get('$_base/playlists', query: {
      'part': 'snippet,contentDetails',
      'mine': 'true',
      'maxResults': '$limit',
    });

    final items = json['items'] as List<dynamic>?;
    if (items == null) return const [];

    return items.whereType<Map<String, dynamic>>().map((item) {
      final snippet = item['snippet'] as Map<String, dynamic>?;
      final details = item['contentDetails'] as Map<String, dynamic>?;
      final thumbnails = snippet?['thumbnails'] as Map<String, dynamic>?;
      final medium = thumbnails?['medium'] as Map<String, dynamic>?;

      return YouTubeMusicPlaylist(
        id: (item['id'] as String?) ?? '',
        title: (snippet?['title'] as String?) ?? 'Untitled',
        itemCount: (details?['itemCount'] as num?)?.toInt() ?? 0,
        thumbnailUrl: medium?['url'] as String?,
      );
    }).where((p) => p.id.isNotEmpty).toList(growable: false);
  }
}
