import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../main/domain/app_models.dart';
import '../domain/music_playback.dart';
import 'pkce_oauth_client.dart';

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

  /// The URI both playback paths take: App Remote's `play(spotifyUri:)` and
  /// the Web API's `context_uri`.
  String get uri => 'spotify:playlist:$id';
}

/// A Spotify Connect target the account can play through.
class SpotifyDevice {
  const SpotifyDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.isActive,
    required this.isRestricted,
  });

  final String id;
  final String name;

  /// Spotify's own category string: `Computer`, `Smartphone`, `Speaker`, …
  final String type;

  final bool isActive;

  /// Restricted devices report state but refuse Web API commands (some cars
  /// and TVs). Offering them as a playback target would only fail later.
  final bool isRestricted;

  bool get isPlayable => !isRestricted;
}

class SpotifyApiException implements Exception {
  const SpotifyApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thrown when a transport control is rejected because the account is not
/// Premium or no Spotify device is currently open. The player surfaces this as
/// a hint rather than a hard error — both are user-fixable states.
class SpotifyPlaybackUnavailable implements Exception {
  const SpotifyPlaybackUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thin wrapper over the Spotify Web API. Every call transparently uses (and
/// refreshes) the stored OAuth token.
class SpotifyApiService {
  SpotifyApiService({
    required MusicAccessTokenSource authService,
    http.Client? httpClient,
  })  : _auth = authService,
        _http = httpClient ?? http.Client();

  final MusicAccessTokenSource _auth;
  final http.Client _http;

  static const _base = 'https://api.spotify.com/v1';

  Future<String> _requireToken() async {
    final token = await _auth.currentAccessToken();
    if (token == null) {
      throw const SpotifyApiException('Spotify is not connected.');
    }
    return token;
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final token = await _requireToken();
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers['Authorization'] = 'Bearer $token';

    if (body == null) {
      // Spotify rejects bodyless PUT/POST without a declared content type.
      request.headers['Content-Length'] = '0';
    } else {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    return http.Response.fromStream(await _http.send(request));
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await _send('GET', path, query: query);
    _throwOnError(response);
    if (response.body.isEmpty) return const {};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Transport calls answer 204 (accepted, no content) on success.
  Future<void> _command(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final response = await _send(method, path, query: query, body: body);
    if (response.statusCode == 204 ||
        response.statusCode == 200 ||
        response.statusCode == 202) {
      return;
    }
    if (response.statusCode == 403) {
      throw const SpotifyPlaybackUnavailable(
        'Spotify Premium is required to control playback from another app.',
      );
    }
    if (response.statusCode == 404) {
      throw const SpotifyPlaybackUnavailable(
        'No active Spotify device. Start playing something in the Spotify app, '
        'then come back.',
      );
    }
    _throwOnError(response);
  }

  void _throwOnError(http.Response response) {
    if (response.statusCode == 200 || response.statusCode == 204) return;
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
    if (response.statusCode == 429) {
      throw const SpotifyApiException(
        'Spotify is rate limiting this app. Try again in a moment.',
      );
    }
    throw SpotifyApiException(
      'Spotify request failed (${response.statusCode}).',
    );
  }

  Future<SpotifyProfile> fetchProfile() async {
    final json = await _get('/me');
    return SpotifyProfile(
      displayName: (json['display_name'] as String?) ?? 'Spotify user',
      email: json['email'] as String?,
      isPremium: (json['product'] as String?) == 'premium',
      imageUrl: _imageUrl(json['images']),
    );
  }

  /// The album cover for a single track, as an https URL.
  ///
  /// The only way to get *shareable* artwork for something App Remote started:
  /// the bridge reports covers as `spotify:image:…` plus raw bytes, and neither
  /// travels — a `spotify:image:` reference means nothing to another person's
  /// device, and bytes would mean re-hosting label artwork on our own Storage.
  /// Spotify's own image CDN is already public, so its URL is the thing to put
  /// on a Pulse.
  ///
  /// Null when [trackUri] is not a track (a podcast episode or a local file
  /// has no id to look up) or when the track carries no artwork at all.
  Future<String?> fetchTrackArtworkUrl(String trackUri) async {
    final id = trackIdOf(trackUri);
    if (id == null) return null;

    final json = await _get('/tracks/$id');
    final album = json['album'] as Map<String, dynamic>?;
    return _imageUrl(album?['images']);
  }

  /// The bare id in `spotify:track:<id>`, or in an open.spotify.com track link.
  ///
  /// Null for anything else — episode URIs, `spotify:local:…` files, and empty
  /// strings all reach here from the player and none of them can be looked up.
  static String? trackIdOf(String uri) {
    final trimmed = uri.trim();
    if (trimmed.isEmpty) return null;

    final match = RegExp(
      r'^(?:spotify:track:|https?://open\.spotify\.com/track/)([A-Za-z0-9]+)',
    ).firstMatch(trimmed);
    return match?.group(1);
  }

  /// Spotify orders every image list widest-first, so the head of the list is
  /// the full-size cover — the one worth keeping, since a sticker may be drawn
  /// at any size on any density of screen.
  static String? _imageUrl(Object? images) {
    if (images is! List || images.isEmpty) return null;
    final first = images.first;
    if (first is! Map) return null;
    final url = (first['url'] as String?)?.trim();
    return (url == null || url.isEmpty) ? null : url;
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

  // --- Player ---

  /// The current remote-player state, or null when Spotify has no active
  /// session (the API answers 204 with an empty body in that case).
  Future<MusicPlayerSnapshot?> fetchPlayerState() async {
    final response = await _send('GET', '/me/player');
    if (response.statusCode == 204 || response.body.isEmpty) return null;
    _throwOnError(response);

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final item = json['item'] as Map<String, dynamic>?;
    final device = json['device'] as Map<String, dynamic>?;

    return MusicPlayerSnapshot(
      service: MusicProviderService.spotify,
      track: item == null ? null : _parseTrack(item, json['progress_ms']),
      isPlaying: json['is_playing'] as bool? ?? false,
      shuffleEnabled: json['shuffle_state'] as bool? ?? false,
      repeatMode: MusicRepeatModeX.fromApi(json['repeat_state'] as String?),
      deviceName: device?['name'] as String?,
      volumePercent: (device?['volume_percent'] as num?)?.toInt(),
      // Some Connect targets (TVs, certain speakers) report their volume but
      // refuse to have it set. Where the flag is absent, having a reading at
      // all is the best signal available.
      supportsVolume: (device?['supports_volume'] as bool?) ??
          (device?['volume_percent'] != null),
    );
  }

  /// Spotify Connect targets this account can currently reach.
  ///
  /// Only devices where Spotify is running (or was, very recently) appear —
  /// an installed-but-closed phone app is not in this list, which is exactly
  /// why App Remote exists.
  Future<List<SpotifyDevice>> fetchDevices() async {
    final json = await _get('/me/player/devices');
    final items = json['devices'] as List<dynamic>?;
    if (items == null) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(
          (d) => SpotifyDevice(
            id: (d['id'] as String?) ?? '',
            name: (d['name'] as String?) ?? 'Unknown device',
            type: (d['type'] as String?) ?? 'Unknown',
            isActive: d['is_active'] as bool? ?? false,
            isRestricted: d['is_restricted'] as bool? ?? false,
          ),
        )
        .where((d) => d.id.isNotEmpty)
        .toList(growable: false);
  }

  /// Moves the account's playback to [deviceId].
  ///
  /// [andPlay] false hands the device the session paused, which is what you
  /// want right before starting a specific context — otherwise Spotify resumes
  /// whatever was last playing for a beat first.
  Future<void> transferPlayback(String deviceId, {bool andPlay = true}) =>
      _command('PUT', '/me/player', body: {
        'device_ids': [deviceId],
        'play': andPlay,
      });

  /// Starts a playlist, album or artist ([contextUri]) rather than resuming.
  ///
  /// The Web API can only do this against an already-active device; with none
  /// it answers 404 and the caller gets [SpotifyPlaybackUnavailable].
  Future<void> playContext(String contextUri, {String? deviceId}) => _command(
        'PUT',
        '/me/player/play',
        query: deviceId == null ? null : {'device_id': deviceId},
        body: {'context_uri': contextUri},
      );

  Future<void> play() => _command('PUT', '/me/player/play');

  Future<void> pause() => _command('PUT', '/me/player/pause');

  Future<void> nextTrack() => _command('POST', '/me/player/next');

  Future<void> previousTrack() => _command('POST', '/me/player/previous');

  Future<void> setShuffle(bool enabled) =>
      _command('PUT', '/me/player/shuffle', query: {'state': '$enabled'});

  Future<void> setRepeat(MusicRepeatMode mode) =>
      _command('PUT', '/me/player/repeat', query: {'state': mode.apiValue});

  Future<void> seek(Duration position) => _command(
        'PUT',
        '/me/player/seek',
        query: {'position_ms': '${position.inMilliseconds}'},
      );

  Future<void> setVolume(int percent) => _command(
        'PUT',
        '/me/player/volume',
        query: {'volume_percent': '${percent.clamp(0, 100)}'},
      );

  NowPlayingTrack _parseTrack(Map<String, dynamic> item, Object? progressMs) {
    final album = item['album'] as Map<String, dynamic>?;
    final artists = (item['artists'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map((a) => (a['name'] as String?) ?? '')
            .where((name) => name.isNotEmpty)
            .toList() ??
        const <String>[];

    return NowPlayingTrack(
      uri: item['uri'] as String?,
      title: (item['name'] as String?) ?? 'Unknown track',
      artist: artists.isEmpty ? 'Unknown artist' : artists.join(', '),
      duration: Duration(
        milliseconds: (item['duration_ms'] as num?)?.toInt() ?? 0,
      ),
      position: Duration(milliseconds: (progressMs as num?)?.toInt() ?? 0),
      albumArtUrl: _imageUrl(album?['images']),
    );
  }

  List<SpotifyPlaylist> _parsePlaylists(List<dynamic>? items) {
    if (items == null) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final tracks = item['tracks'] as Map<String, dynamic>?;
          final owner = item['owner'] as Map<String, dynamic>?;
          return SpotifyPlaylist(
            id: (item['id'] as String?) ?? '',
            name: (item['name'] as String?) ?? 'Untitled',
            trackCount: (tracks?['total'] as num?)?.toInt() ?? 0,
            owner: (owner?['display_name'] as String?) ?? 'Spotify',
            imageUrl: _imageUrl(item['images']),
          );
        })
        .where((p) => p.id.isNotEmpty)
        .toList(growable: false);
  }
}
