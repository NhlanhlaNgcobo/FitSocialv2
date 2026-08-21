import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/music/application/music_island_controller.dart';
import 'package:fitsocial_app/features/music/application/music_presence_provider.dart';
import 'package:fitsocial_app/features/music/application/music_providers.dart';
import 'package:fitsocial_app/features/music/data/spotify_app_remote_service.dart';
import 'package:fitsocial_app/features/music/domain/music_playback.dart';
import 'package:fitsocial_app/features/music/domain/music_presence.dart';
import 'package:fitsocial_app/features/music/presentation/music_island_action.dart';
import 'package:fitsocial_app/features/music/presentation/music_mini_player.dart';

const _playing = MusicPresence(
  service: MusicProviderService.spotify,
  title: 'Bad Habits',
  artist: 'Ed Sheeran',
  isPlaying: true,
);

MusicPlayerSnapshot snapshotOf({
  String title = 'Bad Habits',
  bool playing = true,
}) {
  return MusicPlayerSnapshot(
    service: MusicProviderService.spotify,
    isPlaying: playing,
    track: NowPlayingTrack(
      title: title,
      artist: 'Ed Sheeran',
      duration: const Duration(minutes: 3),
      position: Duration.zero,
    ),
  );
}

/// An app bar with two ordinary actions, so the island's place among them can
/// be checked rather than assumed.
Future<void> pumpBar(WidgetTester tester, MusicPresence presence) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        musicAccountsEnabledProvider.overrideWithValue(true),
        musicPresenceProvider.overrideWithValue(presence),
        musicConnectionsProvider.overrideWith((ref) => _ConnectedSpotify(ref)),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          appBar: AppBar(
            title: const Text('What are you up to?'),
            actions: const [
              MusicIslandAction(),
              IconButton(
                onPressed: null,
                tooltip: 'Health',
                icon: Icon(Icons.monitor_heart_outlined),
              ),
              IconButton(
                onPressed: null,
                tooltip: 'Camera',
                icon: Icon(Icons.photo_camera_outlined),
              ),
            ],
          ),
          body: const SizedBox.expand(),
        ),
      ),
    ),
  );
  // Not pumpAndSettle: the waveform repeats for as long as music is playing,
  // so the tree never goes idle by design.
  await tester.pump();
}

Finder islandFinder() => find.descendant(
      of: find.byType(MusicIslandAction),
      matching: find.byType(GestureDetector),
    );

String islandLabel(WidgetTester tester) {
  final semantics = tester.widget<Semantics>(
    find
        .descendant(
          of: find.byType(MusicIslandAction),
          matching: find.byType(Semantics),
        )
        .first,
  );
  return semantics.properties.label ?? '';
}

void main() {
  group('what counts as something to show', () {
    // Playing, and only playing. A paused track is not music playing, so the
    // island goes rather than sitting there as a control.
    test('only a playing track puts the island on screen', () {
      expect(_playing.isLive, isTrue);
      expect(MusicPresence.fromSnapshot(snapshotOf(playing: false)).isLive,
          isFalse);
    });

    test('nothing loaded is nothing to show', () {
      expect(MusicPresence.none.isLive, isFalse);
      expect(MusicPresence.fromSnapshot(null).isLive, isFalse);

      const empty = MusicPlayerSnapshot(service: MusicProviderService.spotify);
      expect(MusicPresence.fromSnapshot(empty).isLive, isFalse);
    });

    // App Remote fires on every seek, several times a second while scrubbing.
    // Passing each through would rebuild an app bar on every frame.
    test('recognises a repeat of the same reading', () {
      expect(
        MusicPresence.fromSnapshot(snapshotOf())
            .isSameAs(MusicPresence.fromSnapshot(snapshotOf())),
        isTrue,
      );
    });

    test('spots a real change', () {
      final track = MusicPresence.fromSnapshot(snapshotOf());
      expect(
        track
            .isSameAs(MusicPresence.fromSnapshot(snapshotOf(title: 'Shivers'))),
        isFalse,
      );
      expect(
        track.isSameAs(MusicPresence.fromSnapshot(snapshotOf(playing: false))),
        isFalse,
      );
    });
  });

  group('expand and collapse', () {
    test('starts collapsed', () {
      final controller = MusicIslandController();
      addTearDown(controller.dispose);
      expect(controller.isExpanded, isFalse);
    });

    test('opens and folds itself away after the idle timeout', () async {
      // A real wait rather than a fake clock: the timeout is the whole
      // behaviour, and the controller takes it from a const so the test cannot
      // shorten it without changing what ships.
      final controller = MusicIslandController();
      addTearDown(controller.dispose);

      controller.expand();
      expect(controller.isExpanded, isTrue);

      await Future<void>.delayed(
        kIslandIdleTimeout + const Duration(seconds: 1),
      );
      expect(controller.isExpanded, isFalse);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('interaction pushes the collapse back', () async {
      final controller = MusicIslandController();
      addTearDown(controller.dispose);

      controller.expand();
      await Future<void>.delayed(const Duration(seconds: 4));
      controller.keepAlive();
      await Future<void>.delayed(const Duration(seconds: 4));

      // Without keepAlive this would already have collapsed at six seconds.
      expect(controller.isExpanded, isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('collapses on demand, and is safe to collapse twice', () {
      final controller = MusicIslandController();
      addTearDown(controller.dispose);

      controller.expand();
      controller.collapse();
      expect(controller.isExpanded, isFalse);

      controller.collapse();
      expect(controller.isExpanded, isFalse);
    });

    test('keepAlive on a collapsed island does not open it', () {
      final controller = MusicIslandController();
      addTearDown(controller.dispose);

      controller.keepAlive();
      expect(controller.isExpanded, isFalse);
    });

    test('toggles', () {
      final controller = MusicIslandController();
      addTearDown(controller.dispose);

      controller.toggle();
      expect(controller.isExpanded, isTrue);
      controller.toggle();
      expect(controller.isExpanded, isFalse);
    });
  });

  group('the slot in the app bar', () {
    // The point of moving it here: no floating pill over the page, and no rule
    // about which text to avoid. It is an action like any other.
    testWidgets('takes no space at all when nothing is playing',
        (tester) async {
      await pumpBar(tester, MusicPresence.none);

      expect(islandFinder(), findsNothing);
      // The title it used to cover is untouched, and the real actions remain.
      expect(find.text('What are you up to?'), findsOneWidget);
      expect(find.byTooltip('Health'), findsOneWidget);
      expect(find.byTooltip('Camera'), findsOneWidget);
    });

    testWidgets('appears once something is playing', (tester) async {
      await pumpBar(tester, _playing);
      expect(islandFinder(), findsOneWidget);
    });

    // "First counting from the left" — every action in this app is
    // right-aligned, so the island leads the cluster.
    testWidgets('sits left of every other action', (tester) async {
      await pumpBar(tester, _playing);

      final island = tester.getRect(islandFinder());
      final health = tester.getRect(find.byTooltip('Health'));
      final camera = tester.getRect(find.byTooltip('Camera'));

      expect(island.right, lessThanOrEqualTo(health.left));
      expect(health.right, lessThanOrEqualTo(camera.left));
    });

    testWidgets('never covers the title', (tester) async {
      await pumpBar(tester, _playing);

      final title = tester.getRect(find.text('What are you up to?'));
      expect(tester.getRect(islandFinder()).overlaps(title), isFalse);
    });

    testWidgets('is a pill, not a circle', (tester) async {
      await pumpBar(tester, _playing);

      // The slot keeps the row level with the icon buttons beside it...
      final slot = tester.getSize(islandFinder());
      expect(slot.width, MusicIslandAction.slotWidth);
      expect(slot.height, MusicIslandAction.slotHeight);

      // ...and the pill inside it is wider than it is tall, which is what
      // makes it read as a pill rather than another round glyph.
      final pill = tester.getSize(
        find.ancestor(
          of: find.byIcon(Icons.music_note_rounded),
          matching: find.byType(Container),
        ).first,
      );
      expect(pill.width, greaterThan(pill.height));
    });

    testWidgets('carries the music mark in the middle', (tester) async {
      await pumpBar(tester, _playing);
      expect(
        find.descendant(
          of: find.byType(MusicIslandAction),
          matching: find.byIcon(Icons.music_note_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('names the track to a screen reader', (tester) async {
      await pumpBar(tester, _playing);
      expect(islandLabel(tester), 'Now playing: Bad Habits');
    });

    // The reported complaint: the pill was there with nothing playing.
    testWidgets('disappears the moment the music is paused', (tester) async {
      await pumpBar(tester, _playing);
      expect(islandFinder(), findsOneWidget);

      await pumpBar(
        tester,
        const MusicPresence(
          service: MusicProviderService.spotify,
          title: 'Bad Habits',
          artist: 'Ed Sheeran',
          isPlaying: false,
        ),
      );

      expect(islandFinder(), findsNothing);
      // And the row closes up around it, as though it had never been there.
      expect(find.byTooltip('Health'), findsOneWidget);
      expect(find.byTooltip('Camera'), findsOneWidget);
    });

    testWidgets('pausing takes an open panel with it', (tester) async {
      await pumpBar(tester, _playing);
      await tester.tap(islandFinder());
      await tester.pump();
      expect(find.byTooltip('Next track'), findsOneWidget);

      await pumpBar(
        tester,
        const MusicPresence(
          service: MusicProviderService.spotify,
          title: 'Bad Habits',
          artist: 'Ed Sheeran',
          isPlaying: false,
        ),
      );

      expect(find.byTooltip('Next track'), findsNothing);
    });
  });

  group('expanding from the slot', () {
    // Inside the app bar the island has a Navigator and an Overlay above it,
    // which the floating version did not — that was what threw "No Overlay
    // widget found" the moment it was tapped.
    testWidgets('opens the controls without an Overlay error', (tester) async {
      await pumpBar(tester, _playing);

      await tester.tap(islandFinder());
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Next track'), findsOneWidget);
      expect(find.byTooltip('Previous track'), findsOneWidget);
    });

    testWidgets('opens below the bar, centred on the screen', (tester) async {
      await pumpBar(tester, _playing);
      final slot = tester.getRect(islandFinder());
      final screen = tester.view.physicalSize.width / tester.view.devicePixelRatio;

      await tester.tap(islandFinder());
      // Past the open animation: the card starts scaled down and slightly
      // raised, so measuring it mid-flight measures the animation.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final card = tester.getRect(find.byType(MusicMiniPlayer));

      // Below the bar it came from...
      expect(card.top, greaterThanOrEqualTo(slot.bottom));
      // ...and centred, rather than hung off a slot that sits far right.
      expect(card.center.dx, closeTo(screen / 2, 1));
    });

    // "Smooth" is only smooth if the frames in between exist. These assert the
    // card is genuinely part-way through on an intermediate frame rather than
    // snapping from absent to present.
    testWidgets('fades and scales in rather than appearing', (tester) async {
      await pumpBar(tester, _playing);
      await tester.tap(islandFinder());
      await tester.pump();

      // A third of the way through the opening run.
      await tester.pump(const Duration(milliseconds: 90));
      final opening = tester.widget<FadeTransition>(
        find.ancestor(
          of: find.byType(MusicMiniPlayer),
          matching: find.byType(FadeTransition),
        ).first,
      );
      expect(opening.opacity.value, greaterThan(0));
      expect(opening.opacity.value, lessThan(1));

      final scaling = tester.widget<ScaleTransition>(
        find.ancestor(
          of: find.byType(MusicMiniPlayer),
          matching: find.byType(ScaleTransition),
        ).first,
      );
      expect(scaling.scale.value, lessThan(1));

      // And it settles fully open.
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester
            .widget<FadeTransition>(
              find.ancestor(
                of: find.byType(MusicMiniPlayer),
                matching: find.byType(FadeTransition),
              ).first,
            )
            .opacity
            .value,
        1,
      );
    });

    testWidgets('fades out rather than vanishing', (tester) async {
      await pumpBar(tester, _playing);
      await tester.tap(islandFinder());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(islandFinder());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      // Still on screen, on its way out.
      expect(find.byType(MusicMiniPlayer), findsOneWidget);
      final closing = tester.widget<FadeTransition>(
        find.ancestor(
          of: find.byType(MusicMiniPlayer),
          matching: find.byType(FadeTransition),
        ).first,
      );
      expect(closing.opacity.value, lessThan(1));
      expect(closing.opacity.value, greaterThan(0));
    });

    testWidgets('a second tap closes it again', (tester) async {
      await pumpBar(tester, _playing);

      await tester.tap(islandFinder());
      await tester.pump();
      expect(find.byTooltip('Next track'), findsOneWidget);

      await tester.tap(islandFinder());
      // The panel outlives the request to close it while it animates out.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byTooltip('Next track'), findsNothing);
    });

    testWidgets('the track ending takes the panel with it', (tester) async {
      await pumpBar(tester, _playing);

      await tester.tap(islandFinder());
      await tester.pump();
      expect(find.byTooltip('Next track'), findsOneWidget);

      // Music stops: the slot disappears, and an open panel anchored to it
      // must not be left hanging over the page.
      await pumpBar(tester, MusicPresence.none);

      expect(islandFinder(), findsNothing);
      expect(find.byTooltip('Next track'), findsNothing);
    });
  });
  // The island went dark entirely once visibility was gated on isPlaying. The
  // presence controller has to actually receive what the bridge reports —
  // these cover the wiring between the two rather than the rule on top of it.
  group('presence reaches the island', () {
    test('a playing snapshot from the bridge turns the island on', () async {
      final remote = _FakeRemote();
      addTearDown(remote.dispose);

      final container = ProviderContainer(
        overrides: [
          musicAccountsEnabledProvider.overrideWithValue(true),
          spotifyAppRemoteServiceProvider.overrideWithValue(remote),
          musicConnectionsProvider.overrideWith((ref) => _LinkedSpotify(ref)),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(musicPresenceProvider).isLive, isFalse);

      // ensureConnected is awaited before the stream is listened to, and the
      // fake's stream is a broadcast one — an event emitted before the
      // subscription lands is dropped, so give the connect time to finish.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      remote.emit(snapshotOf());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(container.read(musicPresenceProvider).isLive, isTrue);
      expect(container.read(musicPresenceProvider).title, 'Bad Habits');
    });

    test('pausing turns it off again', () async {
      final remote = _FakeRemote();
      addTearDown(remote.dispose);

      final container = ProviderContainer(
        overrides: [
          musicAccountsEnabledProvider.overrideWithValue(true),
          spotifyAppRemoteServiceProvider.overrideWithValue(remote),
          musicConnectionsProvider.overrideWith((ref) => _LinkedSpotify(ref)),
        ],
      );
      addTearDown(container.dispose);

      // Reading is what instantiates the controller — and therefore what
      // subscribes it. Emitting before that would go nowhere.
      container.read(musicPresenceProvider);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      remote.emit(snapshotOf());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(container.read(musicPresenceProvider).isLive, isTrue);

      remote.emit(snapshotOf(playing: false));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(container.read(musicPresenceProvider).isLive, isFalse);
    });
  });
}

/// A connections state with Spotify already linked, so MusicMiniPlayer builds
/// its real controls rather than collapsing to nothing.
class _ConnectedSpotify extends MusicConnectionsController {
  _ConnectedSpotify(super.ref) {
    state = const MusicConnectionsState(
      services: {
        MusicProviderService.spotify: MusicServiceConnection(
          service: MusicProviderService.spotify,
          isConnected: true,
        ),
      },
      primary: MusicProviderService.spotify,
    );
  }
}

/// An App Remote bridge whose player stream this test drives.
class _FakeRemote extends SpotifyAppRemoteService {
  final _controller = StreamController<MusicPlayerSnapshot>.broadcast();
  int subscriptions = 0;

  @override
  Future<bool> ensureConnected() async => true;

  @override
  Stream<MusicPlayerSnapshot> playerStates() {
    subscriptions++;
    return _controller.stream;
  }

  @override
  Future<void> disconnect() async {}

  void emit(MusicPlayerSnapshot snapshot) => _controller.add(snapshot);
  void dispose() => _controller.close();
}

/// Connections with Spotify linked, for the presence controller's own tests.
class _LinkedSpotify extends MusicConnectionsController {
  _LinkedSpotify(super.ref) {
    state = const MusicConnectionsState(
      services: {
        MusicProviderService.spotify: MusicServiceConnection(
          service: MusicProviderService.spotify,
          isConnected: true,
        ),
      },
      primary: MusicProviderService.spotify,
    );
  }
}