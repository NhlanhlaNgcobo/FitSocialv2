import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/presentation/home_screen.dart';
import 'package:fitsocial_app/features/music/presentation/music_island_action.dart';
import 'package:fitsocial_app/features/music/application/music_providers.dart';
import 'package:fitsocial_app/features/music/data/cover_art_lookup_service.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart' show MusicProviderService;
import 'package:fitsocial_app/features/pulse/application/pulse_providers.dart';
import 'package:fitsocial_app/features/pulse/domain/pulse_music.dart';
import 'package:fitsocial_app/features/pulse/presentation/share_music_to_pulse_screen.dart';
import 'package:fitsocial_app/features/tracking/application/tracking_providers.dart';
import 'package:fitsocial_app/features/tracking/presentation/live_run_screen.dart';

import 'live_run_test.dart' show liveRun;
import 'shot_data.dart';
import 'shot_fakes.dart';
import 'shot_harness.dart';

/// What the phone's media session reports: a (fictional) track playing in the
/// Spotify app, which FitSocial reads and controls without any account.
const nowPlaying = <String, Object?>{
  'hasPermission': true,
  'hasTrack': true,
  'appPackage': 'com.spotify.music',
  'appName': 'Spotify',
  'title': 'Promenade at Sunrise',
  'artist': 'Umhlanga Nights',
  'durationMs': 214000,
  'positionMs': 96000,
  'isPlaying': true,
  'canSkipNext': true,
  'canSkipPrevious': true,
  'canSeek': true,
};

void musicPlaying(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('com.fitsocial.fitsocial_app/media_session'),
    (call) async => switch (call.method) {
      'hasPermission' => true,
      'refresh' => nowPlaying,
      _ => null,
    },
  );
  messenger.setMockStreamHandler(
    const EventChannel('com.fitsocial.fitsocial_app/media_session/events'),
    MockStreamHandler.inline(onListen: (args, sink) => sink.success(nowPlaying)),
  );
}

class _NoCovers implements CoverArtLookupService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<String?>.value(null);
}

void main() {
  testWidgets('share song', (tester) async {
    await shoot(tester, 'music_share_pulse',
        shotApp(
            const ShareMusicToPulseScreen(
                music: PulseMusic(
                    provider: MusicProviderService.spotify,
                    title: 'Promenade at Sunrise',
                    artist: 'Umhlanga Nights')),
            pushed: true,
            overrides: [
              ...signedIn(),
              coverArtLookupProvider.overrideWithValue(_NoCovers()),
            ]),
        setup: musicPlaying);
  });

  testWidgets('run with music', (tester) async {
    await shoot(tester, 'music_run',
        shotApp(const LiveRunScreen(), pushed: true, overrides: [
          ...signedIn(),
          liveRunStateProvider.overrideWith((ref) => Stream.value(liveRun())),
        ]),
        setup: musicPlaying, height: 1000);
  });

  testWidgets('home island', (tester) async {
    await shoot(tester, 'music_home',
        shotApp(inShell(const HomeScreen()), overrides: [
          ...signedIn(),
          feedPostsProvider.overrideWith((ref) => FeedPostsNotifier(const ShotContent(), null)),
          activePulsesProvider.overrideWith((ref) => Stream.value(trayPulses)),
          pulseSeenMarkersProvider.overrideWith((ref) => Stream.value(const <String, DateTime>{})),
        ]),
        setup: musicPlaying);
  });

  testWidgets('island open', (tester) async {
    await shoot(tester, 'music_island',
        shotApp(inShell(const HomeScreen()), overrides: [
          ...signedIn(),
          feedPostsProvider.overrideWith((ref) => FeedPostsNotifier(const ShotContent(), null)),
          activePulsesProvider.overrideWith((ref) => Stream.value(trayPulses)),
          pulseSeenMarkersProvider.overrideWith((ref) => Stream.value(const <String, DateTime>{})),
        ]),
        setup: musicPlaying, before: (t) async {
      await t.tap(find.byType(MusicIslandAction));
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    });
  });
}
