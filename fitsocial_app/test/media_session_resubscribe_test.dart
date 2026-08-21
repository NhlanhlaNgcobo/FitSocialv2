import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitsocial_app/features/music/data/media_session_service.dart';

/// Does the shared upstream survive losing all of its listeners?
///
/// The player controller is autoDispose and the presence controller is rebuilt
/// whenever the permission flips, so the subscriber count genuinely reaches
/// zero in normal use. If the cached broadcast stream cannot be listened to
/// again after that, every later subscriber sits silent forever — which looks
/// exactly like "the music feature stopped responding".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const eventChannelName = 'test/media_session/events';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> emit(Map<String, Object?> event) async {
    await messenger.handlePlatformMessage(
      eventChannelName,
      const StandardMethodCodec().encodeSuccessEnvelope(event),
      (_) {},
    );
  }

  const playing = <String, Object?>{
    'hasPermission': true,
    'hasTrack': true,
    'appPackage': 'com.spotify.music',
    'appName': 'Spotify',
    'title': 'Bad Habits',
    'artist': 'Ed Sheeran',
    'durationMs': 200000,
    'positionMs': 1000,
    'isPlaying': true,
  };

  test('a second subscriber still receives events after the first cancelled',
      () async {
    final service = MediaSessionService(
      methodChannel: const MethodChannel('test/media_session'),
      eventChannel: const EventChannel(eventChannelName),
    );

    final first = <MediaSessionState>[];
    final sub = service.states().listen(first.add);
    await pumpEventQueue();
    await emit(playing);
    await pumpEventQueue();
    expect(first, isNotEmpty, reason: 'the first subscriber should work');

    // Everyone goes away — the player card left the tree, or the permission
    // flipped and rebuilt the presence controller.
    await sub.cancel();
    await pumpEventQueue();

    final second = <MediaSessionState>[];
    final sub2 = service.states().listen(second.add);
    addTearDown(sub2.cancel);
    await pumpEventQueue();
    await emit(playing);
    await pumpEventQueue();

    expect(
      second,
      isNotEmpty,
      reason: 'a later subscriber must still receive live events',
    );
  });
}
