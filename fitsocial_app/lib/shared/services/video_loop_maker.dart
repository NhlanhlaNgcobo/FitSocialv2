import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A finished card loop on disk: the clip, and its first frame.
class VideoLoop {
  const VideoLoop({required this.videoPath, required this.posterPath});

  final String videoPath;

  /// The JPEG the card shows before the clip plays — and what every
  /// background picker hands on as the "photo", so the upload, the preview
  /// and older builds all go on treating it as one.
  final String posterPath;
}

/// Cuts a picked video into the few silent seconds that loop behind a run or
/// workout card. The work is VideoLoopBridge.kt's, on `fitsocial/video_loop`.
///
/// Android only for now: there is no iOS half of the bridge yet, and the
/// picker hides its Video button where [isSupported] is false rather than
/// offering something that cannot finish.
abstract final class VideoLoopMaker {
  static const _channel = MethodChannel('fitsocial/video_loop');

  /// The lengths a loop can be. Long enough to read as motion, short enough
  /// to stay near a megabyte and to repeat without anyone counting.
  static const List<Duration> lengths = [
    Duration(seconds: 3),
    Duration(seconds: 4),
    Duration(seconds: 5),
  ];

  /// Longest source clip the trimmer will open. Scrubbing for five seconds in
  /// a ten-minute video is a chore, and decoding it is slow on older phones.
  static const Duration maxSource = Duration(minutes: 2);

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Trims [path] to [length] from [start], strips the sound and shrinks it.
  /// Throws a [PlatformException] when the phone cannot encode it.
  static Future<VideoLoop> make({
    required String path,
    required Duration start,
    required Duration length,
  }) async {
    final result = await _channel.invokeMapMethod<String, String>(
      'makeLoop',
      {
        'path': path,
        'startMs': start.inMilliseconds,
        'durationMs': length.inMilliseconds,
      },
    );
    final video = result?['video'];
    final poster = result?['poster'];
    if (video == null || poster == null) {
      throw PlatformException(
        code: 'no_result',
        message: 'The loop came back empty.',
      );
    }
    return VideoLoop(videoPath: video, posterPath: poster);
  }
}

/// The clip that goes with a background "photo", or null when the photo is
/// just a photo.
///
/// A loop's poster is `loop_<stamp>.jpg` with `loop_<stamp>.mp4` beside it,
/// which is how a path that has travelled through drafts and save screens as
/// an ordinary image path still finds its video at upload time.
String? videoLoopBeside(String? posterPath) {
  if (posterPath == null || kIsWeb) return null;
  final name = posterPath.split(RegExp(r'[\\/]')).last;
  if (!name.startsWith('loop_') || !name.endsWith('.jpg')) return null;
  final video = '${posterPath.substring(0, posterPath.length - 4)}.mp4';
  return File(video).existsSync() ? video : null;
}
