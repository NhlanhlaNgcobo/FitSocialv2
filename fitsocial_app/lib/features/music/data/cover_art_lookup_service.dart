import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;

/// Finds a public https cover-art URL for a track named only by title and
/// artist.
///
/// The phone's media session — the path every user is on — hands over cover
/// art as raw bytes and nothing else: no track id, no URL. Bytes cannot leave
/// this device, and a Pulse is seen on other people's phones, so a shared
/// track needs a URL some CDN already serves. Deezer's and Apple's search
/// APIs answer that with no key, no sign-in and no per-user gate, which is
/// the same bar the media session itself clears.
///
/// Deezer is asked first: its catalogue reaches the small and regional
/// releases Apple's store index misses, which is most of what plays in a
/// gym. Apple is the fallback, asked in the phone's own storefront — the US
/// store, its default, does not list what a South African account streams.
///
/// A lookup by name is a guess, and a confident wrong cover on a Pulse is
/// worse than the placeholder. So a result is only accepted when its track and
/// artist names line up with what the session reported, after both have been
/// stripped of the "(feat. …)" and "- Remastered" decoration that the same
/// song wears differently in every catalogue.
class CoverArtLookupService {
  CoverArtLookupService({http.Client? client, String? countryCode})
      : _client = client ?? http.Client(),
        _countryCode = countryCode ?? _deviceCountry();

  final http.Client _client;

  /// ISO 3166-1 alpha-2, for the Apple storefront. Never null: an unknown
  /// locale falls back to the US store rather than to no store at all.
  final String _countryCode;

  static const _deezerEndpoint = 'https://api.deezer.com/search';
  static const _appleEndpoint = 'https://itunes.apple.com/search';
  static const _timeout = Duration(seconds: 8);

  static String _deviceCountry() {
    // en_ZA, en-ZA, en_ZA.UTF-8 — the region is the second piece, whatever
    // separates the pieces.
    final parts = Platform.localeName.split(RegExp('[_\\-.]'));
    if (parts.length >= 2 && parts[1].length == 2) {
      return parts[1].toUpperCase();
    }
    return 'US';
  }

  /// Null when nothing in either catalogue matches closely enough, when both
  /// requests fail, or when there is not enough of a name to search for.
  Future<String?> findArtworkUrl({
    required String title,
    required String artist,
  }) async {
    final wantedTitle = normalizeName(title);
    if (wantedTitle.isEmpty) return null;
    final wantedArtist = normalizeName(artist);
    final term = '$artist $title'.trim();

    return await _fromDeezer(term, wantedTitle, wantedArtist) ??
        await _fromApple(term, wantedTitle, wantedArtist);
  }

  Future<String?> _fromDeezer(
    String term,
    String wantedTitle,
    String wantedArtist,
  ) async {
    final results = await _fetchList(
      Uri.parse(_deezerEndpoint).replace(queryParameters: {
        'q': term,
        'limit': '10',
      }),
      listKey: 'data',
    );
    for (final result in results) {
      final artist = result['artist'];
      final album = result['album'];
      if (!_isMatch(
        trackName: result['title'],
        artistName: artist is Map ? artist['name'] : null,
        wantedTitle: wantedTitle,
        wantedArtist: wantedArtist,
      )) {
        continue;
      }
      // Widest first; every Deezer cover is served in all four sizes.
      for (final key in const ['cover_xl', 'cover_big', 'cover_medium']) {
        final url = album is Map ? (album[key] ?? '').toString().trim() : '';
        if (url.isNotEmpty) return url;
      }
    }
    return null;
  }

  Future<String?> _fromApple(
    String term,
    String wantedTitle,
    String wantedArtist,
  ) async {
    final results = await _fetchList(
      Uri.parse(_appleEndpoint).replace(queryParameters: {
        'term': term,
        'entity': 'song',
        'media': 'music',
        'limit': '10',
        'country': _countryCode,
      }),
      listKey: 'results',
    );
    for (final result in results) {
      if (!_isMatch(
        trackName: result['trackName'],
        artistName: result['artistName'],
        wantedTitle: wantedTitle,
        wantedArtist: wantedArtist,
      )) {
        continue;
      }
      final url = (result['artworkUrl100'] ?? '').toString().trim();
      if (url.isNotEmpty) return fullSizeArtwork(url);
    }
    return null;
  }

  /// The list under [listKey] in the JSON at [uri], or nothing at all for a
  /// failed request, a bad status, or a body that is not what was expected.
  /// Either catalogue being down is not worth more than the placeholder.
  Future<List<Map>> _fetchList(Uri uri, {required String listKey}) async {
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } catch (_) {
      return const [];
    }
    if (response.statusCode != 200) return const [];

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      return const [];
    }
    if (decoded is! Map) return const [];
    final list = decoded[listKey];
    if (list is! List) return const [];
    return list.whereType<Map>().toList(growable: false);
  }

  static bool _isMatch({
    required Object? trackName,
    required Object? artistName,
    required String wantedTitle,
    required String wantedArtist,
  }) {
    if (!_matches(normalizeName((trackName ?? '').toString()), wantedTitle)) {
      return false;
    }
    // An artist the session did not name cannot be checked — the title alone
    // has to carry it.
    if (wantedArtist.isEmpty) return true;
    return _matches(normalizeName((artistName ?? '').toString()), wantedArtist);
  }

  /// Whether two normalised names are the same, allowing for one side
  /// carrying a suffix the other dropped ("smile" vs "smile feat someone"),
  /// and for spacing the catalogues disagree on ("90mph" vs "90 mph").
  static bool _matches(String found, String wanted) {
    if (found.isEmpty || wanted.isEmpty) return false;
    return _compact(found) == _compact(wanted) ||
        found.startsWith('$wanted ') ||
        wanted.startsWith('$found ');
  }

  static String _compact(String name) => name.replaceAll(' ', '');

  /// Lower-cases, drops anything in brackets and after a " - ", and collapses
  /// punctuation and whitespace — so "Smile (feat. X) - Remastered 2019" and
  /// "smile" compare equal.
  static String normalizeName(String raw) {
    var text = raw.toLowerCase();
    text = text.replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ');
    final dash = text.indexOf(' - ');
    if (dash > 0) text = text.substring(0, dash);
    text = text.replaceAll(RegExp(r'\bfeat\.?\b.*$'), ' ');
    text = text.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// iTunes serves every size of the same image under the same path; only
  /// the trailing `100x100bb` names the size. A sticker may be drawn at any
  /// size on any density of screen, so the 100px thumbnail is swapped for
  /// the full cover.
  static String fullSizeArtwork(String url) =>
      url.replaceFirst(RegExp(r'\d+x\d+(bb)?(?=\.\w+$)'), '600x600bb');
}
