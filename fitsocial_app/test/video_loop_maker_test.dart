import 'dart:io';

import 'package:fitsocial_app/shared/services/video_loop_maker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('video_loop_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('videoLoopBeside', () {
    test("finds a loop's clip from its first frame", () {
      final poster = File('${dir.path}/loop_123.jpg')..writeAsStringSync('');
      File('${dir.path}/loop_123.mp4').writeAsStringSync('');

      expect(videoLoopBeside(poster.path), '${dir.path}/loop_123.mp4');
    });

    test('a plain photo has no clip', () {
      final photo = File('${dir.path}/IMG_0042.jpg')..writeAsStringSync('');
      // Even with an mp4 of the same name beside it: only loops count.
      File('${dir.path}/IMG_0042.mp4').writeAsStringSync('');

      expect(videoLoopBeside(photo.path), isNull);
    });

    test('a loop whose clip has gone reads as a photo', () {
      final poster = File('${dir.path}/loop_9.jpg')..writeAsStringSync('');

      expect(videoLoopBeside(poster.path), isNull);
      expect(videoLoopBeside(null), isNull);
    });
  });

  test('loops are three to five seconds', () {
    expect(
      VideoLoopMaker.lengths.map((length) => length.inSeconds),
      [3, 4, 5],
    );
  });
}
