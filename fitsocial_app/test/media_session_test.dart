import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/music/data/media_session_service.dart';
import 'package:fitsocial_app/features/music/domain/music_playback.dart';

/// The media-session bridge, exercised from the Dart side of the channel.
///
/// Everything below is about the seam between Android's media session and the
/// app's own model, because that seam is where this feature actually lives:
/// the native side just forwards what the OS says, and the UI just draws a
/// [MusicPlayerSnapshot]. The mapping in between is the part with opinions in
/// it — which packages get branding, what an absent artwork blob means, what a
/// missing capability flag defaults to.
TestDefaultBinaryMessenger get messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('test/media_session');
  const eventChannelName = 'test/media_session/events';

  late List<MethodCall> calls;
  late MediaSessionService service;

  /// Answers `hasPermission` and records everything else.
  void mockMethods({bool permitted = true}) {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      if (call.method == 'hasPermission') return permitted;
      if (call.method == 'openPermissionSettings') return true;
      return null;
    });
  }

  /// Subscribes and waits for the event channel to actually be wired up.
  ///
  /// The service hands out a generator that only subscribes upstream once it
  /// starts running, and EventChannel installs its message handler inside that
  /// subscription — so an event fired in the same microtask as `listen` lands
  /// before anyone is there to catch it.
  Future<List<MediaSessionState>> subscribe() async {
    final received = <MediaSessionState>[];
    final sub = service.states().listen(received.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    return received;
  }

  /// Pushes one event down the event channel, as the native side would.
  Future<void> emit(Map<String, Object?> event) async {
    await messenger.handlePlatformMessage(
      eventChannelName,
      const StandardMethodCodec().encodeSuccessEnvelope(event),
      (_) {},
    );
  }

  /// A playing session, with every field the bridge sends filled in.
  Map<String, Object?> session({
    String package = 'com.example.player',
    String title = 'Bad Habits',
    String artist = 'Ed Sheeran',
    bool isPlaying = true,
    int positionMs = 30000,
    int durationMs = 231000,
    bool artChanged = true,
    Uint8List? art,
    Map<String, Object?> overrides = const {},
  }) {
    return {
      'hasPermission': true,
      'hasTrack': true,
      'appPackage': package,
      'appName': 'Example Player',
      'title': title,
      'artist': artist,
      'album': 'Equals',
      'durationMs': durationMs,
      'positionMs': positionMs,
      'isPlaying': isPlaying,
      'shuffle': false,
      'repeat': 'off',
      'canSkipNext': true,
      'canSkipPrevious': true,
      'canSeek': true,
      'volumePercent': 50,
      'supportsVolume': true,
      'albumArtChanged': artChanged,
      'albumArt': art,
      ...overrides,
    };
  }

  setUp(() {
    calls = <MethodCall>[];
    service = MediaSessionService(
      methodChannel: methodChannel,
      eventChannel: const EventChannel(eventChannelName),
    );
    mockMethods();
    // Lets receiveBroadcastStream's own listen/cancel calls succeed.
    messenger.setMockMethodCallHandler(
      const MethodChannel(eventChannelName),
      (call) async => null,
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel(eventChannelName),
      null,
    );
  });

  group('reading what is playing', () {
    test('maps a session onto the app\'s own snapshot', () async {
      final states = await subscribe();

      await emit(session());
      await pumpEventQueue();

      final snapshot = states.single.snapshot!;
      final track = snapshot.track!;
      expect(states.single.hasPermission, isTrue);
      expect(track.title, 'Bad Habits');
      expect(track.artist, 'Ed Sheeran');
      expect(track.duration, const Duration(milliseconds: 231000));
      expect(track.position, const Duration(seconds: 30));
      expect(snapshot.isPlaying, isTrue);
      expect(snapshot.sourceAppName, 'Example Player');
      expect(snapshot.deviceName, 'This phone');
    });

    test('a media session carries no track URI', () async {
      // Not an oversight: Android publishes no stable id for the playing item,
      // which is exactly why nothing downstream can deep-link back to it.
      final states = await subscribe();

      await emit(session());
      await pumpEventQueue();

      expect(states.single.snapshot!.track!.uri, isNull);
    });

    test('reports missing permission separately from nothing playing',
        () async {
      final states = await subscribe();

      await emit({'hasPermission': false, 'hasTrack': false});
      await emit({'hasPermission': true, 'hasTrack': false});
      await pumpEventQueue();

      // The UI asks for something in the first case and says nothing in the
      // second, so collapsing them into one empty state would be wrong.
      expect(states[0].hasPermission, isFalse);
      expect(states[0].snapshot, isNull);
      expect(states[1].hasPermission, isTrue);
      expect(states[1].snapshot, isNull);
    });

    test('replays the last state to a listener that arrives late', () async {
      await subscribe();
      await emit(session());
      await pumpEventQueue();

      // Sessions only emit on change, so without a replay the island would sit
      // blank until the user next pressed a button.
      final late = await subscribe();
      await pumpEventQueue();

      expect(late.single.snapshot!.track!.title, 'Bad Habits');
    });
  });

  group('which app is playing', () {
    test('gives a recognised app its own branding', () async {
      final states = await subscribe();

      await emit(session(package: 'com.spotify.music'));
      await emit(session(package: 'com.google.android.apps.youtube.music'));
      await pumpEventQueue();

      expect(states[0].snapshot!.service, MusicProviderService.spotify);
      expect(states[1].snapshot!.service, MusicProviderService.youtubeMusic);
    });

    test('falls back to the unbranded player for anything else', () async {
      final states = await subscribe();

      await emit(session(package: 'au.com.shiftyjelly.pocketcasts'));
      await pumpEventQueue();

      expect(states.single.snapshot!.service, MusicProviderService.device);
      // The real name still survives, so the card is not reduced to saying
      // "Your music" about an app the phone can perfectly well name.
      expect(states.single.snapshot!.sourceAppName, 'Example Player');
    });

    test('naming a known package is cosmetic, not a connection', () async {
      await subscribe();

      await emit(session(package: 'com.spotify.music'));
      await pumpEventQueue();

      // Nothing here went through an auth flow — the point of the whole
      // feature is that a Spotify-branded snapshot implies no Spotify account.
      expect(
        calls.where((c) => c.method != 'hasPermission'),
        isEmpty,
      );
    });
  });

  group('cover art', () {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);

    test('holds artwork across updates that do not resend it', () async {
      final states = await subscribe();

      await emit(session(artChanged: true, art: bytes));
      // A position tick: same track, no bytes on the wire.
      await emit(session(artChanged: false, positionMs: 31000));
      await pumpEventQueue();

      expect(states[0].snapshot!.track!.albumArtBytes, bytes);
      expect(
        states[1].snapshot!.track!.albumArtBytes,
        bytes,
        reason: 'a position tick must not blank the cover',
      );
    });

    test('clears artwork when the new track genuinely has none', () async {
      final states = await subscribe();

      await emit(session(artChanged: true, art: bytes));
      await emit(session(title: 'Shivers', artChanged: true, art: null));
      await pumpEventQueue();

      // The flag is the whole difference between "unchanged" and "none", and
      // getting it wrong leaves the previous song's cover on the new track.
      expect(states[1].snapshot!.track!.albumArtBytes, isNull);
    });

    test('drops artwork when playback stops', () async {
      final states = await subscribe();

      await emit(session(artChanged: true, art: bytes));
      await emit({'hasPermission': true, 'hasTrack': false});
      await emit(session(title: 'Shivers', artChanged: false));
      await pumpEventQueue();

      expect(states[2].snapshot!.track!.albumArtBytes, isNull);
    });
  });

  group('what the session says it will accept', () {
    test('carries the published capabilities through', () async {
      final states = await subscribe();

      await emit(session(overrides: {'canSeek': false, 'canSkipNext': false}));
      await pumpEventQueue();

      // A live radio stream offers no seek; the UI has to be able to dim the
      // control rather than show a button that does nothing.
      expect(states.single.snapshot!.canSeek, isFalse);
      expect(states.single.snapshot!.canSkipNext, isFalse);
      expect(states.single.snapshot!.canSkipPrevious, isTrue);
    });

    test('never claims shuffle or repeat', () async {
      final states = await subscribe();

      await emit(session());
      await pumpEventQueue();

      // Not a per-app limitation: android.media.session.MediaController has no
      // accessor for either, so there is nothing to read and nothing to set.
      // Reporting anything but the resting values would be invention.
      final snapshot = states.single.snapshot!;
      expect(snapshot.canSetShuffleRepeat, isFalse);
      expect(snapshot.shuffleEnabled, isFalse);
      expect(snapshot.repeatMode, MusicRepeatMode.off);
    });

    test('treats a terse session as permissive', () async {
      final states = await subscribe();

      await emit({
        'hasPermission': true,
        'hasTrack': true,
        'appPackage': 'com.example.player',
        'title': 'Bad Habits',
        'artist': 'Ed Sheeran',
      });
      await pumpEventQueue();

      // A session that publishes no action mask is far likelier to be terse
      // than to genuinely refuse every button.
      final snapshot = states.single.snapshot!;
      expect(snapshot.canSeek, isTrue);
      expect(snapshot.canSkipNext, isTrue);
      expect(snapshot.canSkipPrevious, isTrue);
      expect(snapshot.track!.duration, Duration.zero);
    });
  });

  group('driving playback', () {
    test('sends each transport command with its arguments', () async {
      await service.play();
      await service.pause();
      await service.skipNext();
      await service.skipPrevious();
      await service.seek(const Duration(seconds: 42));
      await service.setVolume(70);

      expect(
        calls.map((c) => c.method).toList(),
        ['play', 'pause', 'skipNext', 'skipPrevious', 'seek', 'setVolume'],
      );
      expect(calls[4].arguments, {'positionMs': 42000});
      expect(calls[5].arguments, {'percent': 70});
    });

    test('clamps a volume outside the usable range', () async {
      await service.setVolume(140);
      expect(calls.single.arguments, {'percent': 100});
    });

    test('turns a missing permission into something the user can act on',
        () async {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        throw PlatformException(code: 'no_permission', message: 'not granted');
      });

      await expectLater(
        service.play(),
        throwsA(
          isA<MediaSessionException>()
              .having((e) => e.block, 'block', MediaSessionBlock.noPermission)
              .having((e) => e.message, 'message', contains('not granted')),
        ),
      );
    });

    test('separates nothing-playing from a real failure', () async {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        throw PlatformException(code: 'no_session');
      });
      await expectLater(
        service.pause(),
        throwsA(isA<MediaSessionException>()
            .having((e) => e.block, 'block', MediaSessionBlock.noSession)),
      );

      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        throw PlatformException(code: 'failed', message: 'rejected');
      });
      await expectLater(
        service.pause(),
        throwsA(isA<MediaSessionException>()
            .having((e) => e.block, 'block', MediaSessionBlock.failed)),
      );
    });

    test('reports an absent channel as unsupported rather than crashing',
        () async {
      // An iOS build, or any platform with no bridge registered. Callers must
      // get a typed no, not a MissingPluginException escaping into the UI.
      messenger.setMockMethodCallHandler(methodChannel, null);

      await expectLater(
        service.play(),
        throwsA(isA<MediaSessionException>()
            .having((e) => e.block, 'block', MediaSessionBlock.unsupported)),
      );
      expect(await service.hasPermission(), isFalse);
      expect(await service.openPermissionSettings(), isFalse);
      expect((await service.refresh()).hasPermission, isFalse);
    });
  });

  group('permission', () {
    test('reads the granted state from the platform', () async {
      expect(await service.hasPermission(), isTrue);

      mockMethods(permitted: false);
      expect(await service.hasPermission(), isFalse);
    });

    test('refresh re-reads state without waiting for a session callback',
        () async {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call);
        if (call.method == 'refresh') return session(title: 'Shivers');
        return null;
      });

      final state = await service.refresh();

      // Android delivers no callback when the user grants access from
      // settings, so returning to the app has to ask.
      expect(state.hasPermission, isTrue);
      expect(state.snapshot!.track!.title, 'Shivers');
    });
  });
}
