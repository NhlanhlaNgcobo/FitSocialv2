import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'dart:async';

import 'package:fitsocial_app/features/music/application/music_providers.dart';
import 'package:fitsocial_app/features/music/data/cover_art_lookup_service.dart';
import 'package:fitsocial_app/features/music/data/pkce_oauth_client.dart';
import 'package:fitsocial_app/features/music/data/spotify_api_service.dart';
import 'package:fitsocial_app/features/pulse/application/pulse_providers.dart';
import 'package:fitsocial_app/features/pulse/domain/pulse_models.dart';
import 'package:fitsocial_app/features/pulse/domain/pulse_music.dart';
import 'package:fitsocial_app/features/pulse/domain/pulse_text_style.dart';
import 'package:fitsocial_app/features/pulse/presentation/pulse_music_frame.dart';
import 'package:fitsocial_app/features/pulse/presentation/pulse_photo_frame.dart';
import 'package:fitsocial_app/features/pulse/presentation/pulse_share_controls.dart';
import 'package:fitsocial_app/features/pulse/presentation/pulse_text_tool.dart';
import 'package:fitsocial_app/shared/widgets/liquid_glass.dart';
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

/// What sharing looks like on the media-session path — the one every user is
/// on: the phone named the song and nothing else. No URI to look up by, no
/// URL to share, and the cover it did hand over is bytes stuck on this phone.
const _sessionTrack = PulseMusic(
  provider: MusicProviderService.spotify,
  title: 'Smile',
  artist: 'Morgan Wallen',
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

/// Answers the by-name lookup without going near the network.
class _FakeCatalogue extends CoverArtLookupService {
  _FakeCatalogue({this.artworkUrl, this.gate});

  /// Null stands in for a song the catalogue does not know.
  final String? artworkUrl;

  /// When given, the answer is held back until this completes — a catalogue
  /// on a slow connection.
  final Completer<void>? gate;
  final lookups = <String>[];

  @override
  Future<String?> findArtworkUrl({
    required String title,
    required String artist,
  }) async {
    lookups.add('$artist – $title');
    await gate?.future;
    return artworkUrl;
  }
}

/// Keeps the drafts the share button sends, instead of writing them.
class RecordingActions extends PulseActions {
  RecordingActions(super.ref);

  final published = <PulseDraft>[];

  @override
  Future<PulseSegment> publish(PulseDraft draft) async {
    published.add(draft);
    throw StateError('recorded');
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
        home: Scaffold(
          body: PulseMusicFrame(
            music: music,
            gradient: PulseGradient.ember,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> pumpShareScreen(
  WidgetTester tester,
  SpotifyApiService spotify,
  PulseMusic music, {
  CoverArtLookupService? catalogue,
  RecordingActions Function(Ref ref)? actions,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        spotifyApiServiceProvider.overrideWithValue(spotify),
        coverArtLookupProvider.overrideWithValue(catalogue ?? _FakeCatalogue()),
        if (actions != null) pulseActionsProvider.overrideWith(actions),
      ],
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
      // The artist alone: the service is named by the eyebrow above the
      // cover, and printing it twice on one sticker reads as a stutter.
      expect(find.text('Ed Sheeran'), findsOneWidget);
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

    // The whole point of the layout: the album art is the frame, not a
    // thumbnail on a card floating over a gradient.
    testWidgets('the cover art is the background', (tester) async {
      await pumpCard(tester, _track);

      expect(find.byType(PulseBlurredBackdrop), findsOneWidget);
    });

    // With nothing to fill the frame with, the Pulse gradient is what is left
    // — a blurred backdrop of no image would be a blank grey screen.
    testWidgets('a track with no art falls back to the gradient',
        (tester) async {
      await pumpCard(tester, _uncoveredTrack);

      expect(find.byType(PulseBlurredBackdrop), findsNothing);
    });

    testWidgets('the control under the track is glass', (tester) async {
      await pumpCard(tester, _track);

      // Orange is the app's brand fill, and a slab of it over album art fights
      // the artwork it is sitting on.
      expect(find.text('Connect Spotify'), findsOneWidget);
      expect(find.byType(LiquidGlass), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
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
      // Two: the cover now does both jobs, sharp in the middle of the frame
      // and blurred behind it.
      expect(find.byType(Image), findsNWidgets(2));
    });

    testWidgets('does not look one up when the track already has a cover',
        (tester) async {
      final spotify = _FakeSpotify(artworkUrl: 'https://i.scdn.co/image/xyz');
      await pumpShareScreen(tester, spotify, _track);

      expect(spotify.lookups, isEmpty);
    });

    // A track no catalogue has artwork for still gets shared: the sticker
    // names the song, which is the point of it.
    testWidgets('keeps the placeholder when there is no artwork to find',
        (tester) async {
      final spotify = _FakeSpotify();
      await pumpShareScreen(tester, spotify, _uncoveredTrack);

      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    // The bug as shipped: every track shared from the phone's media session
    // arrived bare, because the only lookup wanted a Spotify id and the
    // session has none to give. The song's name is what it does have.
    testWidgets('a track with no id is looked up by name', (tester) async {
      final spotify = _FakeSpotify(artworkUrl: 'https://i.scdn.co/image/abc');
      final catalogue =
          _FakeCatalogue(artworkUrl: 'https://mzstatic/600x600bb.jpg');
      await pumpShareScreen(tester, spotify, _sessionTrack,
          catalogue: catalogue);

      expect(spotify.lookups, isEmpty);
      expect(catalogue.lookups, ['Morgan Wallen – Smile']);
      expect(find.byType(Image), findsNWidgets(2));
    });

    // The id is the exact answer, so it goes first — and the name lookup is
    // only spent when it comes back empty.
    testWidgets('falls back to the name when Spotify has no cover',
        (tester) async {
      final spotify = _FakeSpotify();
      final catalogue =
          _FakeCatalogue(artworkUrl: 'https://mzstatic/600x600bb.jpg');
      await pumpShareScreen(tester, spotify, _uncoveredTrack,
          catalogue: catalogue);

      expect(spotify.lookups, [_uncoveredTrack.trackUri]);
      expect(catalogue.lookups, ['Ed Sheeran – Bad Habits']);
      expect(find.byType(Image), findsNWidgets(2));
    });

    // The bug as reported: open the share screen, press Share straight away,
    // and the Pulse went out bare — and a Pulse is a snapshot, so it stayed
    // bare. Share has to wait for a lookup that is still in flight.
    testWidgets('Share waits for a cover that is still being looked up',
        (tester) async {
      final gate = Completer<void>();
      final catalogue = _FakeCatalogue(
        artworkUrl: 'https://mzstatic/600x600bb.jpg',
        gate: gate,
      );
      RecordingActions? actions;
      await pumpShareScreen(
        tester,
        _FakeSpotify(),
        _sessionTrack,
        catalogue: catalogue,
        actions: (ref) => actions = RecordingActions(ref),
      );

      // Still looking: the placeholder says so, and Share is pressed anyway.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Share Pulse'));
      await tester.pump();
      // Nothing has been published — the actions have not even been asked
      // for yet, because the share is still waiting on the cover.
      expect(actions?.published ?? const [], isEmpty);

      // The cover lands, and only then does the draft go out — with it.
      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(actions!.published, hasLength(1));
      expect(
        actions!.published.single.music!.albumArtUrl,
        'https://mzstatic/600x600bb.jpg',
      );
    });

    // The share screen and the composer are one place: the same Share pill,
    // the same "Aa" rail, and the same text tool behind it. Words written
    // here leave with their style, and land on the Pulse where they were put.
    testWidgets('writes over the track with the same text tool as the composer',
        (tester) async {
      RecordingActions? actions;
      await pumpShareScreen(
        tester,
        _FakeSpotify(),
        _track,
        actions: (ref) => actions = RecordingActions(ref),
      );

      expect(find.byType(PulseShareButton), findsOneWidget);
      expect(find.byType(PulseTextToolButton), findsOneWidget);
      // No caption box: the words go on the frame, not under it.
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.byType(PulseTextToolButton));
      await tester.pump();
      expect(find.byType(PulseTextEditor), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'On repeat');
      await tester.tap(find.text('Strong'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pump();

      expect(find.byType(PulseTextSticker), findsOneWidget);
      expect(find.text('On repeat'), findsOneWidget);

      await tester.tap(find.text('Share Pulse'));
      await tester.pump();
      await tester.pump();

      final draft = actions!.published.single;
      expect(draft.text, 'On repeat');
      expect(draft.textStyle!.font, PulseFont.strong);
      expect(draft.music, _track);
    });

    testWidgets('does not spend a name lookup once the id found a cover',
        (tester) async {
      final spotify = _FakeSpotify(artworkUrl: 'https://i.scdn.co/image/abc');
      final catalogue = _FakeCatalogue(artworkUrl: 'https://mzstatic/x.jpg');
      await pumpShareScreen(tester, spotify, _uncoveredTrack,
          catalogue: catalogue);

      expect(catalogue.lookups, isEmpty);
    });
  });
}
