import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/music/application/music_player_controller.dart';
import 'package:fitsocial_app/features/music/application/music_providers.dart';
import 'package:fitsocial_app/features/music/data/media_session_service.dart';
import 'package:fitsocial_app/features/music/data/pkce_oauth_client.dart';
import 'package:fitsocial_app/features/music/data/spotify_api_service.dart';
import 'package:fitsocial_app/features/music/data/spotify_app_remote_service.dart';
import 'package:fitsocial_app/features/music/domain/music_playback.dart';
import 'package:fitsocial_app/features/music/presentation/connect_music_action.dart';
import 'package:fitsocial_app/features/music/presentation/connect_music_sheet.dart';
import 'package:fitsocial_app/features/music/presentation/music_mini_player.dart';
import 'package:fitsocial_app/features/music/presentation/music_player_card.dart';
import 'package:fitsocial_app/features/music/presentation/widgets/music_brand_logos.dart';

/// Seeds connection state without going near a real OAuth round trip.
class _SeededConnections extends MusicConnectionsController {
  _SeededConnections(super.ref, MusicConnectionsState seed) {
    state = seed;
  }
}

class _NoAuth implements MusicAccessTokenSource {
  @override
  Future<String?> currentAccessToken() async => 'test-token';

  @override
  Future<bool> isConnected() async => true;

  @override
  Future<void> disconnect() async {}
}

/// Stands in for the Spotify app not being installed.
///
/// Without this the tests reach the real bridge, whose platform channel has no
/// implementation under test — so the transport the player picks would depend
/// on how quickly a MissingPluginException happened to propagate.
class _NoAppRemote extends SpotifyAppRemoteService {
  final calls = <String>[];

  @override
  Future<bool> ensureConnected() async =>
      throw const SpotifyRemoteException(SpotifyRemoteBlock.notInstalled);

  @override
  Stream<MusicPlayerSnapshot> playerStates() => const Stream.empty();

  @override
  Future<void> disconnect() async {}
}

/// A live bridge, for the paths that only App Remote can serve.
class _FakeAppRemote extends SpotifyAppRemoteService {
  final calls = <String>[];
  final _states = StreamController<MusicPlayerSnapshot>.broadcast();

  void emit(MusicPlayerSnapshot snapshot) => _states.add(snapshot);

  @override
  Future<bool> ensureConnected() async => true;

  @override
  Stream<MusicPlayerSnapshot> playerStates() => _states.stream;

  @override
  Future<void> play(String spotifyUri) async => calls.add('play:$spotifyUri');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> skipNext() async => calls.add('next');

  @override
  Future<void> skipPrevious() async => calls.add('previous');

  @override
  Future<void> seek(Duration position) async =>
      calls.add('seek:${position.inSeconds}');

  @override
  Future<void> setShuffle(bool enabled) async => calls.add('shuffle:$enabled');

  @override
  Future<void> setRepeat(MusicRepeatMode mode) async =>
      calls.add('repeat:${mode.apiValue}');

  @override
  Future<Uint8List?> albumArt(String imageUriRaw) async => null;

  @override
  Future<void> disconnect() async => calls.add('disconnect');
}

/// Records which transport calls the UI actually made.
class _FakeSpotify extends SpotifyApiService {
  _FakeSpotify(this._snapshot) : super(authService: _NoAuth());

  /// Left deliberately stale after a command, so tests can prove the UI does
  /// not let a lagging poll undo what the user just did.
  final MusicPlayerSnapshot? _snapshot;
  final calls = <String>[];

  @override
  Future<MusicPlayerSnapshot?> fetchPlayerState() async => _snapshot;

  @override
  Future<void> seek(Duration position) async =>
      calls.add('seek:${position.inSeconds}');

  @override
  Future<void> setVolume(int percent) async => calls.add('volume:$percent');

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> nextTrack() async => calls.add('next');

  @override
  Future<void> previousTrack() async => calls.add('previous');

  @override
  Future<void> setShuffle(bool enabled) async => calls.add('shuffle:$enabled');

  @override
  Future<void> setRepeat(MusicRepeatMode mode) async =>
      calls.add('repeat:${mode.apiValue}');
}

MusicConnectionsState _connectedTo(MusicProviderService service) {
  return MusicConnectionsState(
    services: {
      for (final each in MusicProviderService.values)
        each: MusicServiceConnection(
          service: each,
          isConnected: each == service,
          supportsPlayback: each == service,
          accountName: each == service ? 'Test account' : null,
        ),
    },
    primary: service,
  );
}

const _track = NowPlayingTrack(
  title: 'Leg Day Anthem',
  artist: 'Test Artist',
  duration: Duration(minutes: 3, seconds: 20),
  position: Duration(seconds: 40),
);

/// Stands in for the platform bridge, so the sheet can be driven without one.
class _FakeMediaSession extends MediaSessionService {
  _FakeMediaSession({this.granted = false, this.canOpenSettings = true});

  final bool granted;

  /// A handful of OEM builds have no notification-access screen to open.
  final bool canOpenSettings;

  int settingsOpened = 0;

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<bool> openPermissionSettings() async {
    settingsOpened++;
    return canOpenSettings;
  }

  @override
  Stream<MediaSessionState> states() => const Stream.empty();
}

Widget _host({
  required Widget child,
  MusicConnectionsState? connections,
  _FakeSpotify? spotify,
  SpotifyAppRemoteService? appRemote,
  MediaSessionService? session,
  bool accountsEnabled = true,
}) {
  return ProviderScope(
    overrides: [
      // The account half of the music feature is off in the shipped app, and
      // most of these exercise exactly that half. Turning it on by default
      // keeps the OAuth, Web API and App Remote paths under test rather than
      // deleting their coverage along with the UI that reaches them; the group
      // at the bottom of this file turns it back off to cover what ships.
      musicAccountsEnabledProvider.overrideWithValue(accountsEnabled),
      // Defaults to "notification access not granted", which is every test
      // below that is not specifically about the media session.
      mediaSessionServiceProvider
          .overrideWithValue(session ?? _FakeMediaSession()),
      if (connections != null)
        musicConnectionsProvider
            .overrideWith((ref) => _SeededConnections(ref, connections)),
      if (spotify != null) spotifyApiServiceProvider.overrideWithValue(spotify),
      // Defaults to "no Spotify app", which is the Web API path the bulk of
      // these tests assert against.
      spotifyAppRemoteServiceProvider
          .overrideWithValue(appRemote ?? _NoAppRemote()),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  // The connections controller probes secure storage on construction. Without
  // a binding the plain (non-widget) tests below blow up before they start.
  TestWidgetsFlutterBinding.ensureInitialized();

  // Token reads and deletes go through a platform channel with no
  // implementation under test. Left unmocked its futures never complete inside
  // testWidgets' fake-async zone, so a disconnect would hang forever rather
  // than fail — which is exactly what it did before this was added.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  group('phone music', () {
    /// Opens the sheet and returns the fake behind it.
    Future<_FakeMediaSession> openSheet(
      WidgetTester tester, {
      bool granted = false,
      bool canOpenSettings = true,
      bool accountsEnabled = true,
    }) async {
      final session = _FakeMediaSession(
        granted: granted,
        canOpenSettings: canOpenSettings,
      );
      await tester.pumpWidget(
        _host(
          accountsEnabled: accountsEnabled,
          connections: MusicConnectionsState.initial(),
          session: session,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showConnectMusicSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return session;
    }

    testWidgets('offers the phone itself before any account', (tester) async {
      await openSheet(tester);

      // The whole point of the feature: this row needs no sign-in, so it leads
      // and the three services follow under their own heading.
      expect(find.text('Your music'), findsOneWidget);
      expect(find.text('Or connect an account'), findsOneWidget);
      expect(
        find.text('Show and control what is playing, in any app'),
        findsOneWidget,
      );
    });

    testWidgets('sends the user to settings to grant access', (tester) async {
      final session = await openSheet(tester);

      await tester.tap(find.text('Your music'));
      await tester.pumpAndSettle();

      // Notification access has no runtime dialog — the system screen is the
      // only way to grant it.
      expect(session.settingsOpened, 1);
    });

    testWidgets('says where to look when there is no settings screen',
        (tester) async {
      final session = await openSheet(tester, canOpenSettings: false);

      await tester.tap(find.text('Your music'));
      await tester.pumpAndSettle();

      expect(session.settingsOpened, 1);
      // A button that visibly does nothing is worse than instructions.
      expect(find.textContaining('Notification access'), findsOneWidget);
    });

    testWidgets('says what the scary screen is really asking for',
        (tester) async {
      await openSheet(tester);

      // The system grant screen warns about reading every notification on the
      // phone. Left unanswered, that is where a reasonable person quits — so
      // the answer goes in front of it, not after.
      expect(find.textContaining('It never reads one'), findsOneWidget);
    });

    testWidgets('drops the reassurance once there is nothing to reassure',
        (tester) async {
      await openSheet(tester, granted: true);

      expect(find.textContaining('It never reads one'), findsNothing);
    });

    testWidgets('stops asking once access is granted', (tester) async {
      final session = await openSheet(tester, granted: true);

      expect(
        find.text('On \u00b7 controlling whatever this phone plays'),
        findsOneWidget,
      );

      await tester.tap(find.text('Your music'));
      await tester.pumpAndSettle();

      // Sending someone back to stare at a switch they already flipped is not
      // an action, so the tile goes inert rather than staying tappable.
      expect(session.settingsOpened, 0);
    });
  });

  group('connect sheet', () {
    testWidgets('offers all three services, each with its own mark',
        (tester) async {
      await tester.pumpWidget(
        _host(
          connections: MusicConnectionsState.initial(),
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showConnectMusicSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('How should we find your music?'), findsOneWidget);
      expect(find.text('Spotify'), findsOneWidget);
      expect(find.text('Apple Music'), findsOneWidget);
      expect(find.text('YouTube Music'), findsOneWidget);

      // The phone's own music leads, because it is the only row here that
      // works without an account.
      expect(find.text('Your music'), findsOneWidget);

      // Each button carries the mark twice: once at readable size, once as the
      // oversized watermark behind the label.
      //
      // Walks connectable rather than values: MusicProviderService.device is
      // what the phone media session reports when it cannot name the player,
      // and it has no button here because there is no account behind it.
      for (final service in MusicProviderService.connectable) {
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is MusicServiceLogo && widget.service == service,
          ),
          findsNWidgets(2),
          reason: '${service.label} should show its logo and watermark',
        );
      }
    });

    // Apple Music and YouTube Music are both paused. They still show so users
    // can see they are planned, but under a shade, and tapping must not start
    // anything. Spotify has to stay live alongside them.
    testWidgets('shades the paused services and swallows their taps',
        (tester) async {
      await tester.pumpWidget(
        _host(
          connections: MusicConnectionsState.initial(),
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showConnectMusicSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Coming soon'), findsNWidgets(2));

      for (final name in ['Apple Music', 'YouTube Music']) {
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();

        expect(
          find.text('How should we find your music?'),
          findsOneWidget,
          reason: 'tapping $name should not dismiss or navigate',
        );
      }

      expect(find.textContaining('Apple Developer account'), findsNothing);
      expect(find.textContaining('Google OAuth client ID'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('a paused service reports itself as coming soon, not unconfigured',
        () {
      for (final service in [
        MusicProviderService.appleMusic,
        MusicProviderService.youtubeMusic,
      ]) {
        final connection = MusicServiceConnection(service: service);
        expect(connection.isComingSoon, isTrue);
        expect(connection.isAvailable, isFalse);
        expect(connection.unavailableReason, contains('coming soon'));
      }

      // Spotify is the one that must stay connectable.
      const spotify =
          MusicServiceConnection(service: MusicProviderService.spotify);
      expect(spotify.isComingSoon, isFalse);
      expect(spotify.isAvailable, isTrue);
    });
  });

  group('player', () {
    testWidgets('stays out of the tree until something is connected',
        (tester) async {
      await tester.pumpWidget(
        _host(
          connections: MusicConnectionsState.initial(),
          child: const MusicPlayerCard(),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      expect(find.byIcon(Icons.shuffle_rounded), findsNothing);
    });

    testWidgets('shows the track and the full transport once connected',
        (tester) async {
      final spotify = _FakeSpotify(
        const MusicPlayerSnapshot(
          service: MusicProviderService.spotify,
          track: _track,
          isPlaying: true,
        ),
      );

      await tester.pumpWidget(
        _host(
          connections: _connectedTo(MusicProviderService.spotify),
          spotify: spotify,
          child: const MusicPlayerCard(),
        ),
      );
      await tester.pump();

      expect(find.text('Leg Day Anthem'), findsOneWidget);
      expect(find.text('Test Artist'), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
      expect(find.text('0:40'), findsOneWidget);
      expect(find.text('3:20'), findsOneWidget);
    });

    testWidgets('every control reaches the service', (tester) async {
      final spotify = _FakeSpotify(
        const MusicPlayerSnapshot(
          service: MusicProviderService.spotify,
          track: _track,
          isPlaying: true,
        ),
      );

      await tester.pumpWidget(
        _host(
          connections: _connectedTo(MusicProviderService.spotify),
          spotify: spotify,
          child: const MusicPlayerCard(),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.skip_previous_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.shuffle_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.repeat_rounded));
      await tester.pump();

      expect(
        spotify.calls,
        containsAll(<String>[
          'pause',
          'next',
          'previous',
          'shuffle:true',
          'repeat:context',
        ]),
      );
    });

    // Nothing here can drive Apple Music or YouTube Music playback, so the
    // buttons must be visibly inert with a reason attached rather than
    // silently swallowing taps.
    testWidgets('says why the transport is inert on other services',
        (tester) async {
      await tester.pumpWidget(
        _host(
          connections: _connectedTo(MusicProviderService.youtubeMusic),
          child: const MusicPlayerCard(),
        ),
      );
      await tester.pump();

      expect(
        find.textContaining('no public remote-playback API'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byIcon(Icons.shuffle_rounded),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
    });
  });

  // The same card sits on the Music tab and the Live Run screen, so it has to
  // stand on its own rather than rely on anything either screen provides.
  group('connect card', () {
    testWidgets('invites a connection and opens the sheet from it',
        (tester) async {
      await tester.pumpWidget(
        _host(
          connections: MusicConnectionsState.initial(),
          child: const ConnectMusicAction(),
        ),
      );
      await tester.pump();

      expect(find.text('Connect your music app'), findsWidgets);

      await tester.tap(find.widgetWithText(FilledButton, 'Connect your music app'));
      await tester.pumpAndSettle();

      expect(find.text('How should we find your music?'), findsOneWidget);
      expect(find.text('Coming soon'), findsNWidgets(2));
    });

    testWidgets('becomes the account list once connected', (tester) async {
      await tester.pumpWidget(
        _host(
          connections: _connectedTo(MusicProviderService.spotify),
          child: const ConnectMusicAction(),
        ),
      );
      await tester.pump();

      expect(find.text('Your music accounts'), findsOneWidget);
      expect(find.text('Playing here'), findsOneWidget);
      expect(find.text('Connect another app'), findsOneWidget);
    });
  });

  // The Live Run screen's player. Mid-run the runner must be able to skip
  // without leaving tracking, and must not be handed controls they'd only hit
  // by accident.
  group('mini player', () {
    testWidgets('carries skip and play, and nothing else', (tester) async {
      final spotify = _FakeSpotify(
        const MusicPlayerSnapshot(
          service: MusicProviderService.spotify,
          track: _track,
          isPlaying: true,
          volumePercent: 70,
          supportsVolume: true,
        ),
      );

      await tester.pumpWidget(
        _host(
          connections: _connectedTo(MusicProviderService.spotify),
          spotify: spotify,
          child: const MusicMiniPlayer(),
        ),
      );
      await tester.pump();

      expect(find.text('Leg Day Anthem'), findsOneWidget);
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);

      // Deliberately absent: nobody picks a repeat mode at 5k.
      expect(find.byIcon(Icons.shuffle_rounded), findsNothing);
      expect(find.byIcon(Icons.repeat_rounded), findsNothing);
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('skipping reaches the service', (tester) async {
      final spotify = _FakeSpotify(
        const MusicPlayerSnapshot(
          service: MusicProviderService.spotify,
          track: _track,
          isPlaying: true,
        ),
      );

      await tester.pumpWidget(
        _host(
          connections: _connectedTo(MusicProviderService.spotify),
          spotify: spotify,
          child: const MusicMiniPlayer(),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      await tester.pump();

      expect(spotify.calls, contains('next'));
    });

    testWidgets('stays hidden until a service is connected', (tester) async {
      await tester.pumpWidget(
        _host(
          connections: MusicConnectionsState.initial(),
          child: const MusicMiniPlayer(),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.skip_next_rounded), findsNothing);
    });
  });

  group('log out', () {
    testWidgets('the player offers a way out of the connected account',
        (tester) async {
      final spotify = _FakeSpotify(
        const MusicPlayerSnapshot(
          service: MusicProviderService.spotify,
          track: _track,
        ),
      );

      await tester.pumpWidget(
        _host(
          connections: _connectedTo(MusicProviderService.spotify),
          spotify: spotify,
          child: const MusicPlayerCard(),
        ),
      );
      await tester.pump();

      // Tucked behind an overflow menu, not sitting beside the transport.
      expect(find.text('Log out of Spotify'), findsNothing);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Log out of Spotify'), findsOneWidget);
    });

    testWidgets('logging out clears the connection and hides the player',
        (tester) async {
      final spotify = _FakeSpotify(
        const MusicPlayerSnapshot(
          service: MusicProviderService.spotify,
          track: _track,
        ),
      );

      await tester.pumpWidget(
        _host(
          connections: _connectedTo(MusicProviderService.spotify),
          spotify: spotify,
          child: const MusicPlayerCard(),
        ),
      );
      await tester.pump();
      expect(find.text('Leg Day Anthem'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log out of Spotify'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MusicPlayerCard)),
      );
      expect(
        container.read(musicConnectionsProvider).hasAnyConnection,
        isFalse,
      );
      expect(find.text('Leg Day Anthem'), findsNothing);
    });
  });

  group('seek', () {
    testWidgets('dragging the bar seeks to where it was released',
        (tester) async {
      final spotify = _FakeSpotify(
        const MusicPlayerSnapshot(
          service: MusicProviderService.spotify,
          track: _track,
          isPlaying: true,
        ),
      );

      await tester.pumpWidget(
        _host(
          connections: _connectedTo(MusicProviderService.spotify),
          spotify: spotify,
          child: const MusicPlayerCard(),
        ),
      );
      await tester.pump();

      // Drag the seek thumb (the first slider) to roughly the middle.
      final bar = find.byType(Slider).first;
      final box = tester.getRect(bar);
      await tester.dragFrom(
        Offset(box.left + 4, box.center.dy),
        Offset(box.width / 2, 0),
      );
      await tester.pump();

      expect(
        spotify.calls.where((c) => c.startsWith('seek:')),
        isNotEmpty,
        reason: 'releasing the thumb should commit a seek',
      );
    });

    // Spotify reports the pre-seek position for a moment afterwards. Taking
    // that at face value would snap the bar backwards under the user's finger.
    testWidgets('a lagging poll does not undo the seek', (tester) async {
      final spotify = _FakeSpotify(
        const MusicPlayerSnapshot(
          service: MusicProviderService.spotify,
          track: _track,
          isPlaying: true,
        ),
      );

      await tester.pumpWidget(
        _host(
          connections: _connectedTo(MusicProviderService.spotify),
          spotify: spotify,
          child: const MusicPlayerCard(),
        ),
      );
      await tester.pump();
      expect(find.text('0:40'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MusicPlayerCard)),
      );
      await container
          .read(musicPlayerControllerProvider.notifier)
          .seek(const Duration(minutes: 2));
      await tester.pump();
      expect(find.text('2:00'), findsOneWidget);

      // The fake keeps answering with the original 0:40 position.
      await container.read(musicPlayerControllerProvider.notifier).refresh();
      await tester.pump();

      expect(
        find.text('2:00'),
        findsOneWidget,
        reason: 'the seek target should survive a stale poll',
      );
      expect(find.text('0:40'), findsNothing);
    });

    test('a seek past the end is clamped to the track length', () async {
      final container = ProviderContainer(
        overrides: [
          musicAccountsEnabledProvider.overrideWithValue(true),
          musicConnectionsProvider.overrideWith(
            (ref) => _SeededConnections(
              ref,
              _connectedTo(MusicProviderService.spotify),
            ),
          ),
          spotifyApiServiceProvider.overrideWithValue(
            _FakeSpotify(
              const MusicPlayerSnapshot(
                service: MusicProviderService.spotify,
                track: _track,
                isPlaying: true,
              ),
            ),
          ),
          spotifyAppRemoteServiceProvider.overrideWithValue(_NoAppRemote()),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(musicPlayerControllerProvider.notifier);
      await controller.refresh();
      await controller.seek(const Duration(hours: 1));

      expect(
        container.read(musicPlayerControllerProvider).snapshot?.track?.position,
        _track.duration,
      );
    });
  });

  group('volume', () {
    testWidgets('hides the slider when the device will not take a volume',
        (tester) async {
      final spotify = _FakeSpotify(
        const MusicPlayerSnapshot(
          service: MusicProviderService.spotify,
          track: _track,
        ),
      );

      await tester.pumpWidget(
        _host(
          connections: _connectedTo(MusicProviderService.spotify),
          spotify: spotify,
          child: const MusicPlayerCard(),
        ),
      );
      await tester.pump();

      expect(find.byType(Slider), findsOneWidget); // seek bar only
      expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
    });

    testWidgets('shows the level and mutes to zero', (tester) async {
      final spotify = _FakeSpotify(
        const MusicPlayerSnapshot(
          service: MusicProviderService.spotify,
          track: _track,
          volumePercent: 70,
          supportsVolume: true,
        ),
      );

      await tester.pumpWidget(
        _host(
          connections: _connectedTo(MusicProviderService.spotify),
          spotify: spotify,
          child: const MusicPlayerCard(),
        ),
      );
      await tester.pump();

      expect(find.text('70'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.volume_up_rounded));
      await tester.pump();

      expect(spotify.calls, contains('volume:0'));
    });
  });

  group('repeat', () {
    test('cycles off -> playlist -> track -> off', () {
      expect(MusicRepeatMode.off.next, MusicRepeatMode.context);
      expect(MusicRepeatMode.context.next, MusicRepeatMode.track);
      expect(MusicRepeatMode.track.next, MusicRepeatMode.off);
    });

    test('maps to the values Spotify expects', () {
      expect(MusicRepeatMode.off.apiValue, 'off');
      expect(MusicRepeatMode.context.apiValue, 'context');
      expect(MusicRepeatMode.track.apiValue, 'track');
      expect(MusicRepeatModeX.fromApi('track'), MusicRepeatMode.track);
      expect(MusicRepeatModeX.fromApi(null), MusicRepeatMode.off);
    });
  });

  /// What actually ships: notification access, and no accounts anywhere.
  ///
  /// Every other group here turns accounts back on, because that is the code
  /// they are about. This one is the shipped configuration, and it exists
  /// because the interesting failure is silent — a music feature that is fully
  /// built, fully tested, and reaches nothing on a real phone.
  group('accounts off', () {
    testWidgets('notification access alone puts the player on screen',
        (tester) async {
      await tester.pumpWidget(
        _host(
          accountsEnabled: false,
          connections: MusicConnectionsState.initial(),
          session: _FakeMediaSession(granted: true),
          child: const MusicPlayerCard(),
        ),
      );
      // The permission is read over a channel, so the first frame still says
      // no; the answer lands on the next one.
      await tester.pump();
      await tester.pump();

      // Nothing is connected and nothing ever will be, and the card is still
      // here. Gating this on an account is what used to hide the whole feature
      // from everyone who took the route that needs no account.
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    });

    testWidgets('without notification access there is still nothing to show',
        (tester) async {
      await tester.pumpWidget(
        _host(
          accountsEnabled: false,
          connections: MusicConnectionsState.initial(),
          session: _FakeMediaSession(),
          child: const MusicPlayerCard(),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.skip_next_rounded), findsNothing);
    });

    testWidgets('the sheet offers the phone and nothing else', (tester) async {
      await tester.pumpWidget(
        _host(
          accountsEnabled: false,
          connections: MusicConnectionsState.initial(),
          session: _FakeMediaSession(),
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showConnectMusicSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Your music'), findsOneWidget);
      // No sign-in on offer, so no heading promising one and no service
      // buttons under it.
      expect(find.text('Or connect an account'), findsNothing);
      expect(find.text('Spotify'), findsNothing);
      expect(find.text('Apple Music'), findsNothing);
      expect(find.text('YouTube Music'), findsNothing);
    });

    test('the player never reaches for Spotify, even if a token survived',
        () async {
      final appRemote = _FakeAppRemote();
      final container = ProviderContainer(
        overrides: [
          musicAccountsEnabledProvider.overrideWithValue(false),
          // A connection left over from a build that had accounts on. The
          // switch has to hold even then, or turning the feature off would
          // leave old installs still driving an account nobody can renew.
          musicConnectionsProvider.overrideWith(
            (ref) => _SeededConnections(
              ref,
              _connectedTo(MusicProviderService.spotify),
            ),
          ),
          spotifyAppRemoteServiceProvider.overrideWithValue(appRemote),
          mediaSessionServiceProvider.overrideWithValue(_FakeMediaSession()),
        ],
      );
      addTearDown(container.dispose);

      container.read(musicPlayerControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        container.read(musicPlayerControllerProvider).transport,
        MusicPlaybackTransport.none,
      );
      expect(appRemote.calls, isEmpty);
    });
  });

  group('app remote', () {
    ProviderContainer containerWith({
      required SpotifyAppRemoteService appRemote,
      _FakeSpotify? spotify,
    }) {
      final container = ProviderContainer(
        overrides: [
          musicAccountsEnabledProvider.overrideWithValue(true),
          musicConnectionsProvider.overrideWith(
            (ref) => _SeededConnections(
              ref,
              _connectedTo(MusicProviderService.spotify),
            ),
          ),
          spotifyApiServiceProvider
              .overrideWithValue(spotify ?? _FakeSpotify(null)),
          spotifyAppRemoteServiceProvider.overrideWithValue(appRemote),
        ],
      );
      addTearDown(container.dispose);
      // The player provider is autoDispose, so without a live listener it is
      // torn down the instant `read` returns and every later call throws.
      container.listen(musicPlayerControllerProvider, (_, __) {});
      return container;
    }

    test('takes over the transport once the bridge is up', () async {
      final appRemote = _FakeAppRemote();
      final container = containerWith(appRemote: appRemote);

      container.read(musicPlayerControllerProvider.notifier);
      // The bridge is brought up off the constructor, so the upgrade lands a
      // microtask later — the point of starting on the Web API.
      await pumpEventQueue();

      expect(
        container.read(musicPlayerControllerProvider).transport,
        MusicPlaybackTransport.appRemote,
      );
    });

    test('picking a playlist starts it on the phone', () async {
      final appRemote = _FakeAppRemote();
      final container = containerWith(appRemote: appRemote);

      final controller =
          container.read(musicPlayerControllerProvider.notifier);
      await pumpEventQueue();
      await controller.playContext('spotify:playlist:abc123');

      expect(appRemote.calls, contains('play:spotify:playlist:abc123'));
    });

    test('transport controls go to the bridge, not the Web API', () async {
      final appRemote = _FakeAppRemote();
      final spotify = _FakeSpotify(null);
      final container = containerWith(appRemote: appRemote, spotify: spotify);

      final controller =
          container.read(musicPlayerControllerProvider.notifier);
      await pumpEventQueue();

      appRemote.emit(
        const MusicPlayerSnapshot(
          service: MusicProviderService.spotify,
          track: _track,
          isPlaying: true,
        ),
      );
      await pumpEventQueue();

      await controller.togglePlayPause();
      await controller.next();
      await controller.seek(const Duration(seconds: 30));

      expect(appRemote.calls, containsAll(['pause', 'next', 'seek:30']));
      expect(
        spotify.calls,
        isEmpty,
        reason: 'App Remote is live, so nothing should reach the Web API',
      );
    });

    test('falls back to the Web API when Spotify is not installed', () async {
      final spotify = _FakeSpotify(
        const MusicPlayerSnapshot(
          service: MusicProviderService.spotify,
          track: _track,
          isPlaying: true,
        ),
      );
      final container =
          containerWith(appRemote: _NoAppRemote(), spotify: spotify);

      final controller =
          container.read(musicPlayerControllerProvider.notifier);
      await pumpEventQueue();
      await controller.togglePlayPause();

      final state = container.read(musicPlayerControllerProvider);
      expect(state.transport, MusicPlaybackTransport.webApi);
      expect(spotify.calls, contains('pause'));
    });

    test(
        'explains the missing Spotify app only when nothing is playing',
        () async {
      final silent = containerWith(appRemote: _NoAppRemote());
      silent.read(musicPlayerControllerProvider.notifier);
      await pumpEventQueue();

      expect(
        silent.read(musicPlayerControllerProvider).message,
        contains('Install the Spotify app'),
      );

      final playing = containerWith(
        appRemote: _NoAppRemote(),
        spotify: _FakeSpotify(
          const MusicPlayerSnapshot(
            service: MusicProviderService.spotify,
            track: _track,
            isPlaying: true,
          ),
        ),
      );
      playing.read(musicPlayerControllerProvider.notifier);
      await pumpEventQueue();

      expect(
        playing.read(musicPlayerControllerProvider).message,
        isNull,
        reason: 'a working Connect session should not be nagged at',
      );
    });

    test('signing out drops the bridge as well as the token', () async {
      final appRemote = _FakeAppRemote();
      final container = containerWith(appRemote: appRemote);

      await container
          .read(musicConnectionsProvider.notifier)
          .disconnect(MusicProviderService.spotify);

      expect(appRemote.calls, contains('disconnect'));
    });
  });

  group('now playing', () {
    // copyWith is called once a second to advance the position, and again when
    // artwork resolves. Anything it forgets to carry is erased a beat after it
    // arrives — which is exactly what would strand a shared Pulse with no way
    // to play the track it names.
    test('carries every field through a position update', () {
      const track = NowPlayingTrack(
        uri: 'spotify:track:6PQ88X9TkUIAUIZJHW2upE',
        title: 'Bad Habits',
        artist: 'Ed Sheeran',
        duration: Duration(minutes: 3, seconds: 51),
        position: Duration.zero,
        albumArtUrl: 'https://i.scdn.co/image/abc',
        albumArtUri: 'spotify:image:abc',
      );

      final advanced = track.copyWith(position: const Duration(seconds: 30));

      expect(advanced.position, const Duration(seconds: 30));
      expect(advanced.uri, track.uri);
      expect(advanced.title, track.title);
      expect(advanced.artist, track.artist);
      expect(advanced.duration, track.duration);
      expect(advanced.albumArtUrl, track.albumArtUrl);
      expect(advanced.albumArtUri, track.albumArtUri);
    });

    test('reports no URI when the transport did not give one', () {
      const track = NowPlayingTrack(
        title: 'Bad Habits',
        artist: 'Ed Sheeran',
        duration: Duration(minutes: 3),
        position: Duration.zero,
      );
      expect(track.uri, isNull);
      expect(track.copyWith(position: const Duration(seconds: 5)).uri, isNull);
    });
  });
}
