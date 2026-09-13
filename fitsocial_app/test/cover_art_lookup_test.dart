import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsocial_app/features/music/data/cover_art_lookup_service.dart';

/// Two catalogues, each answering every search with its own fixed results,
/// and a record of what was asked of whom.
CoverArtLookupService catalogues({
  List<Map<String, Object?>> deezer = const [],
  List<Map<String, Object?>> apple = const [],
  List<Uri>? requests,
  int status = 200,
  String countryCode = 'ZA',
}) {
  return CoverArtLookupService(
    countryCode: countryCode,
    client: MockClient((request) async {
      requests?.add(request.url);
      final isDeezer = request.url.host == 'api.deezer.com';
      final body = isDeezer ? {'data': deezer} : {'results': apple};
      return http.Response(jsonEncode(body), status);
    }),
  );
}

Map<String, Object?> deezerSong(String track, String artist, {String? art}) => {
      'title': track,
      'artist': {'name': artist},
      'album': {
        'cover_xl': art ?? 'https://cdn-images.dzcdn.net/x/1000x1000.jpg',
        'cover_big': 'https://cdn-images.dzcdn.net/x/500x500.jpg',
      },
    };

Map<String, Object?> appleSong(String track, String artist, {String? art}) => {
      'trackName': track,
      'artistName': artist,
      'artworkUrl100':
          art ?? 'https://is1-ssl.mzstatic.com/image/thumb/abc/100x100bb.jpg',
    };

void main() {
  // The phone's media session names a track and nothing else, so this lookup
  // is what stands between a shared song and a grey square.
  group('finding cover art by name', () {
    test('takes the widest Deezer cover of a matching track', () async {
      final requests = <Uri>[];
      final service = catalogues(
        deezer: [deezerSong('90mph', 'JBee')],
        requests: requests,
      );

      final url = await service.findArtworkUrl(title: '90mph', artist: 'JBEE');

      expect(url, 'https://cdn-images.dzcdn.net/x/1000x1000.jpg');
      // Deezer answered, so Apple was never asked.
      expect(requests.map((r) => r.host), ['api.deezer.com']);
      expect(requests.single.queryParameters['q'], 'JBEE 90mph');
    });

    // Deezer reaches the small and regional releases Apple's index misses;
    // Apple is the fallback, in the phone's own storefront.
    test('falls back to Apple, in the device storefront', () async {
      final requests = <Uri>[];
      final service = catalogues(
        apple: [appleSong('Smile', 'Morgan Wallen')],
        requests: requests,
        countryCode: 'ZA',
      );

      final url = await service.findArtworkUrl(
        title: 'Smile',
        artist: 'Morgan Wallen',
      );

      expect(
        url,
        'https://is1-ssl.mzstatic.com/image/thumb/abc/600x600bb.jpg',
      );
      expect(
          requests.map((r) => r.host), ['api.deezer.com', 'itunes.apple.com']);
      final apple = requests.last.queryParameters;
      expect(apple['term'], 'Morgan Wallen Smile');
      expect(apple['entity'], 'song');
      expect(apple['country'], 'ZA');
    });

    // A wrong cover, confidently drawn, is worse than none: the first hit for
    // a common title is very often a different song of the same name.
    test('skips results whose artist does not match', () async {
      final service = catalogues(deezer: [
        deezerSong('Smile', 'Lily Allen', art: 'https://x/lily.jpg'),
        deezerSong('Smile', 'Morgan Wallen', art: 'https://x/wallen.jpg'),
      ]);

      final url = await service.findArtworkUrl(
        title: 'Smile',
        artist: 'Morgan Wallen',
      );

      expect(url, 'https://x/wallen.jpg');
    });

    test('returns nothing rather than guessing when no result matches',
        () async {
      final service = catalogues(
        deezer: [deezerSong('Frown', 'Someone Else')],
        apple: [appleSong('90 MPH', 'thom.ko')],
      );

      final url = await service.findArtworkUrl(title: '90mph', artist: 'JBEE');

      expect(url, isNull);
    });

    // The same song wears different decoration in every catalogue — the
    // session says "(feat. X)", the catalogue says "- Remastered".
    test('matches through featuring credits and remaster suffixes', () async {
      final service = catalogues(deezer: [
        deezerSong(
            'Bad Habits (feat. Someone) - Remastered 2021', 'Ed Sheeran'),
      ]);

      final url = await service.findArtworkUrl(
        title: 'Bad Habits',
        artist: 'Ed Sheeran',
      );

      expect(url, isNotNull);
    });

    test('matches through spacing and case the catalogues disagree on',
        () async {
      final service = catalogues(deezer: [deezerSong('90 MPH', 'J Bee')]);

      final url = await service.findArtworkUrl(title: '90mph', artist: 'JBee');

      expect(url, isNotNull);
    });

    test('checks only the title when the session named no artist', () async {
      final service =
          catalogues(deezer: [deezerSong('Smile', 'Morgan Wallen')]);

      final url = await service.findArtworkUrl(title: 'Smile', artist: '');

      expect(url, isNotNull);
    });

    test('searches for nothing when there is no title', () async {
      final requests = <Uri>[];
      final service = catalogues(requests: requests);

      final url = await service.findArtworkUrl(title: '  ', artist: 'Anyone');

      expect(url, isNull);
      expect(requests, isEmpty);
    });

    test('treats failed requests as no artwork', () async {
      final service = catalogues(
        deezer: [deezerSong('Smile', 'Morgan Wallen')],
        apple: [appleSong('Smile', 'Morgan Wallen')],
        status: 503,
      );

      final url = await service.findArtworkUrl(
        title: 'Smile',
        artist: 'Morgan Wallen',
      );

      expect(url, isNull);
    });

    test('treats a broken response as no artwork', () async {
      final service = CoverArtLookupService(
        countryCode: 'ZA',
        client: MockClient((_) async => http.Response('not json', 200)),
      );

      final url = await service.findArtworkUrl(
        title: 'Smile',
        artist: 'Morgan Wallen',
      );

      expect(url, isNull);
    });
  });

  group('normalising names', () {
    test('drops brackets, dash suffixes, credits and punctuation', () {
      expect(
        CoverArtLookupService.normalizeName(
          'Smile (feat. Someone) [Live] - Remastered 2019',
        ),
        'smile',
      );
      expect(CoverArtLookupService.normalizeName("Don't Stop Me Now!"),
          'don t stop me now');
      expect(CoverArtLookupService.normalizeName('  A   B  '), 'a b');
    });
  });

  group('sizing Apple artwork', () {
    test('swaps the thumbnail size for the full cover', () {
      expect(
        CoverArtLookupService.fullSizeArtwork('https://x/a/100x100bb.jpg'),
        'https://x/a/600x600bb.jpg',
      );
      expect(
        CoverArtLookupService.fullSizeArtwork('https://x/a/60x60.png'),
        'https://x/a/600x600bb.png',
      );
    });

    test('leaves a URL it does not recognise alone', () {
      expect(
        CoverArtLookupService.fullSizeArtwork('https://x/a/cover.jpg'),
        'https://x/a/cover.jpg',
      );
    });
  });
}
