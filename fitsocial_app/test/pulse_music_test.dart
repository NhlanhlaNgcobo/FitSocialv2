import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/music/application/music_providers.dart';
import 'package:fitsocial_app/features/music/data/pkce_oauth_client.dart';
import 'package:fitsocial_app/features/music/data/spotify_api_service.dart';
import 'package:fitsocial_app/features/pulse/domain/pulse_models.dart';
import 'package:fitsocial_app/features/pulse/domain/pulse_music.dart';
import 'package:fitsocial_app/features/pulse/presentation/pulse_music_card.dart';
import 'package:fitsocial_app/features/pulse/presentation/share_music_to_pulse_screen.dart';

const _track = PulseMusic(
  provider: MusicProviderService.spotify,
  title: 'Bad Habits',
  artist: 'Ed Sheeran',
  trackUri: 'spotify:track:6PQ88X9TkUIAUIZJHW2upE',
  albumArtUrl: 'https://i.scdn.co/image/abc',
);

/// What sharing looks like on the App Remote path: a track that names itself
/// but arrived with no fetchable cover.
const _uncoveredTrack = PulseMusic(
  provider: MusicProviderService.spotify,
  title: 'Bad Habits',
  artist: 'Ed Sheeran',
  trackUri: 'spotify:track:6PQ88X9TkUIAUIZJHW2upE',
);

/// A Spotify account that is linked, so the api service will make its call.
class _NoAuth implements MusicAccessTokenSource {
  @override
  Future<String?> currentAccessToken() async => 'test-token';

  @override
  Future<bool> isConnected() async => true;

  @override
  Future<void> disconnect() async {}
}

/// Answers the cover-art lookup without going near the network.
class _FakeSpotify extends SpotifyApiService {
  _FakeSpotify({this.artworkUrl}) : super(authService: _NoAuth());

  /// Null stands in for a track Spotify has no artwork for.
  final String? artworkUrl;
  final lookups = <String>[];

  @override
  Future<String?> fetchTrackArtworkUrl(String trackUri) async {
    lookups.add(trackUri);
    return artworkUrl;
  }
}

Future<void> pumpCard(
  WidgetTester tester,
  PulseMusic music, {
  bool accountsEnabled = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        musicAccountsEnabledProvider.overrideWithValue(accountsEnabled),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(body: PulseMusicCard(music: music)),
      ),
    ),
  );
  await tester.pump();
}

Future<void> pumpShareScreen(
  WidgetTester tester,
  SpotifyApiService spotify,
  PulseMusic music,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [spotifyApiServiceProvider.overrideWithValue(spotify)],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: ShareMusicToPulseScreen(music: music),
      ),
    ),
  );
  // Twice: once for the frame, once for the lookup that initState kicked off.
  await tester.pump();
  await tester.pump();
}

void main() {
  group('storing what was playing', () {
    test('round-trips through a map', () {
      final restored = PulseMusic.fromMap(_track.toMap())!;

      expect(restored.provider, MusicProviderService.spotify);
      expect(restored.title, 'Bad Habits');
      expect(restored.artist, 'Ed Sheeran');
      expect(restored.trackUri, _track.trackUri);
      expect(restored.albumArtUrl, _track.albumArtUrl);
    });

    // The sticker's whole job is naming the song. Without a title there is
    // nothing to draw, so the segment falls back to its unavailable frame.
    test('refuses a map with no title', () {
      expect(PulseMusic.fromMap(null), isNull);
      expect(PulseMusic.fromMap('not a map'), isNull);
      expect(PulseMusic.fromMap(const {'artist': 'Ed Sheeran'}), isNull);
      expect(PulseMusic.fromMap(const {'title': '   '}), isNull);
    });

    test('survives a track with no URI or cover', () {
      final restored = PulseMusic.fromMap(const {
        'provider': 'spotify',
        'title': 'Bad Habits',
        'artist': 'Ed Sheeran',
      })!;

      expect(restored.trackUri, isNull);
      expect(restored.albumArtUrl, isNull);
      expect(restored.isPlayable, isFalse);
    });

    test('omits absent fields rather than writing empty strings', () {
      const bare = PulseMusic(
        provider: MusicProviderService.spotify,
        title: 'Bad Habits',
        artist: 'Ed Sheeran',
      );
      expect(bare.toMap().containsKey('trackUri'), isFalse);
      expect(bare.toMap().containsKey('albumArtUrl'), isFalse);
    });

    // An unreadable provider on a stored track is far likelier to be a typo
    // than a real fourth service, and dropping the sticker over it would lose
    // a song the app can perfectly well name.
    test('falls back to Spotify on an unrecognised provider', () {
      final restored = PulseMusic.fromMap(const {
        'provider': 'napster',
        'title': 'Bad Habits',
      })!;
      expect(restored.provider, MusicProviderService.spotify);
    });
  });

  group('what the sticker reads', () {
    test('joins the artist and the service', () {
      expect(_track.subtitle, 'Ed Sheeran · Spotify');
    });

    test('drops the artist when it is unknown', () {
      const noArtist = PulseMusic(
        provider: MusicProviderService.spotify,
        title: 'Untitled',
        artist: '',
      );
      expect(noArtist.subtitle, 'Spotify');
    });
  });

  group('playability', () {
    test('needs a URI and a service this app drives', () {
      expect(_track.isPlayable, isTrue);

      const noUri = PulseMusic(
        provider: MusicProviderService.spotify,
        title: 'Bad Habits',
        artist: 'Ed Sheeran',
      );
      expect(noUri.isPlayable, isFalse);

      const otherService = PulseMusic(
        provider: MusicProviderService.appleMusic,
        title: 'Bad Habits',
        artist: 'Ed Sheeran',
        trackUri: 'spotify:track:abc',
      );
      expect(otherService.isPlayable, isFalse);
    });
  });

  group('the pulse kind', () {
    test('round-trips through its stored key', () {
      expect(PulseMediaType.music.key, 'music');
      expect(PulseMediaType.fromKey('music'), PulseMediaType.music);
    });

    // Text, shared posts and shared tracks all publish in a single write.
    test('carries no media, so publishing never touches Storage', () {
      expect(PulseMediaType.music.carriesMedia, isFalse);
    });

    test('is publishable on the track alone', () {
      const withTrack = PulseDraft(type: PulseMediaType.music, music: _track);
      const without = PulseDraft(type: PulseMediaType.music);

      expect(withTrack.isPublishable, isTrue);
      expect(without.isPublishable, isFalse);
    });

    // A key this build does not know must not crash the viewer.
    test('an unknown kind still reads as something', () {
      expect(PulseMediaType.fromKey('hologram'), PulseMediaType.photo);
    });
  });

  group('the sticker', () {
    testWidgets('names the track, the artist and the service', (tester) async {
      await pumpCard(tester, _track);

      expect(find.text('LISTENING TO'), findsOneWidget);
      expect(find.text('Bad Habits'), findsOneWidget);
      expect(find.text('Ed Sheeran · Spotify'), findsOneWidget);
    });

    // Playback runs against the account on the viewer's device, so someone
    // without Spotify linked is offered the connect flow.
    testWidgets('offers to connect when the viewer has no account linked',
        (tester) async {
      await pumpCard(tester, _track);

      expect(find.text('Connect Spotify'), findsOneWidget);
      expect(find.text('Play'), findsNothing);
    });

    testWidgets('shows no control at all for a track it cannot start',
        (tester) async {
      await pumpCard(
        tester,
        const PulseMusic(
          provider: MusicProviderService.spotify,
          title: 'Bad Habits',
          artist: 'Ed Sheeran',
        ),
      );

      expect(find.text('Bad Habits'), findsOneWidget);
      expect(find.text('Play'), findsNothing);
      expect(find.text('Connect Spotify'), findsNothing);
    });

    testWidgets('offers nothing to press while accounts are off',
        (tester) async {
      await pumpCard(tester, _track, accountsEnabled: false);

      // The sticker still names the song — that is the part that travels
      // between people. What it cannot do is start it: the phone's media
      // session steers what is playing but cannot pick it, and there is no
      // account on offer that could. A "Connect Spotify" button leading to a
      // sheet with no Spotify in it would be worse than no button.
      expect(find.text('Bad Habits'), findsOneWidget);
      expect(find.text('Play'), findsNothing);
      expect(find.text('Connect Spotify'), findsNothing);
    });

    testWidgets('falls back to a placeholder with no cover art',
        (tester) async {
      await pumpCard(
        tester,
        const PulseMusic(
          provider: MusicProviderService.spotify,
          title: 'Bad Habits',
          artist: 'Ed Sheeran',
          trackUri: 'spotify:track:abc',
        ),
      );

      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });

  // App Remote — the path that actually plays the music — reports cover art as
  // a `spotify:image:` reference plus raw bytes, neither of which another
  // person's phone can fetch. Everything below is how a shareable https URL is
  // found for a track that started there.
  group('finding shareable cover art', () {
    test('reads the id out of a track URI', () {
      expect(
        SpotifyApiService.trackIdOf('spotify:track:6PQ88X9TkUIAUIZJHW2upE'),
        '6PQ88X9TkUIAUIZJHW2upE',
      );
    });

    test('reads the id out of a shared open.spotify.com link', () {
      expect(
        SpotifyApiService.trackIdOf(
          'https://open.spotify.com/track/6PQ88X9TkUIAUIZJHW2upE?si=abc',
        ),
        '6PQ88X9TkUIAUIZJHW2upE',
      );
    });

    // Podcast episodes and local files reach the player too, and neither has a
    // track to look up — asking anyway would spend a request on a 404.
    test('refuses anything that is not a track', () {
      expect(SpotifyApiService.trackIdOf(''), isNull);
      expect(SpotifyApiService.trackIdOf('   '), isNull);
      expect(SpotifyApiService.trackIdOf('spotify:episode:abc'), isNull);
      expect(SpotifyApiService.trackIdOf('spotify:local:a:b:c:120'), isNull);
    });

    testWidgets('the share screen fills in a cover the player had not resolved',
        (tester) async {
      final spotify = _FakeSpotify(artworkUrl: 'https://i.scdn.co/image/abc');
      await pumpShareScreen(tester, spotify, _uncoveredTrack);

      expect(spotify.lookups, [_uncoveredTrack.trackUri]);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('does not look one up when the track already has a cover',
        (tester) async {
      final spotify = _FakeSpotify(artworkUrl: 'https://i.scdn.co/image/xyz');
      await pumpShareScreen(tester, spotify, _track);

      expect(spotify.lookups, isEmpty);
    });

    // A track Spotify has no artwork for still gets shared: the sticker names
    // the song, which is the point of it.
    testWidgets('keeps the placeholder when there is no artwork to find',
        (tester) async {
      final spotify = _FakeSpotify();
      await pumpShareScreen(tester, spotify, _uncoveredTrack);

      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });
}
