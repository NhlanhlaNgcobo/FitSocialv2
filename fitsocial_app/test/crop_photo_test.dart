import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:fitsocial_app/shared/services/photo_crop.dart';
import 'package:fitsocial_app/shared/widgets/crop_photo_screen.dart';
import 'package:fitsocial_app/shared/widgets/picture_ratio.dart';

/// A [width] by [height] PNG, red on its left half and blue on its right.
Uint8List _halves(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(
          x, y, x < width / 2 ? 255 : 0, 0, x < width / 2 ? 0 : 255);
    }
  }
  return img.encodePng(image);
}

bool _isRed(img.Pixel p) => p.r > 200 && p.b < 60;
bool _isBlue(img.Pixel p) => p.b > 200 && p.r < 60;

void main() {
  group('crop geometry', () {
    test('the frame is the largest of its shape that fits', () {
      expect(
        CropGeometry.fitFrame(const Size(360, 800), 9 / 16),
        const Size(360, 640),
      );
      // Too short for a full-width 9:16, so height decides.
      expect(
        CropGeometry.fitFrame(const Size(360, 480), 9 / 16),
        const Size(270, 480),
      );
    });

    test('the photo always covers the frame', () {
      // A landscape photo in a portrait frame is scaled to the frame's height.
      final scale = CropGeometry.coverScale(
        const Size(4000, 3000),
        const Size(360, 640),
      );
      expect(scale, closeTo(640 / 3000, 1e-9));
    });

    test('dragging stops at the photo\'s edge', () {
      const photo = Size(4000, 3000);
      const frame = Size(360, 640);
      final scale = CropGeometry.coverScale(photo, frame);
      final slack = (photo.width * scale - frame.width) / 2;

      final clamped = CropGeometry.clampOffset(
        const Offset(10000, 10000),
        photo,
        scale,
        frame,
      );
      expect(clamped.dx, closeTo(slack, 1e-9));
      // Exactly the frame's height: no room to move up or down at all.
      expect(clamped.dy, 0);
    });

    test('a centred photo crops from its middle', () {
      const photo = Size(4000, 3000);
      const frame = Size(360, 640);
      final scale = CropGeometry.coverScale(photo, frame);
      final crop = CropGeometry.cropFraction(
        photo: photo,
        scale: scale,
        offset: Offset.zero,
        frame: frame,
      );

      expect(crop.top, closeTo(0, 1e-9));
      expect(crop.height, closeTo(1, 1e-9));
      expect(crop.center.dx, closeTo(0.5, 1e-9));
      // A 9:16 slice of a 4:3 photo is 0.5625 * 0.75 of its width.
      expect(crop.width, closeTo((9 / 16) * (3000 / 4000), 1e-9));
    });

    test('dragging the photo right crops further left', () {
      const photo = Size(4000, 3000);
      const frame = Size(360, 640);
      final scale = CropGeometry.coverScale(photo, frame);
      final crop = CropGeometry.cropFraction(
        photo: photo,
        scale: scale,
        offset: const Offset(50, 0),
        frame: frame,
      );
      expect(crop.center.dx, lessThan(0.5));
    });

    test('a turned photo swaps its sides', () {
      expect(
        CropGeometry.turned(const Size(4, 3), 1),
        const Size(3, 4),
      );
      expect(CropGeometry.turned(const Size(4, 3), 2), const Size(4, 3));
    });

    test('the output is at most 1080 by 1920, never scaled up', () {
      expect(CropGeometry.outputSize(const Size(2160, 3840)), (1080, 1920));
      expect(CropGeometry.outputSize(const Size(540, 960)), (540, 960));
      // A wide crop is held to 1080 across.
      expect(CropGeometry.outputSize(const Size(3820, 2000)), (1080, 565));
    });
  });

  group('photo post framing', () {
    test('a post is shown at the shape it was cropped to', () {
      expect(photoPostRatio(9 / 16), 9 / 16);
      expect(photoPostRatio(4 / 5), 4 / 5);
      expect(photoPostRatio(1), 1);
      expect(photoPostRatio(1.91), 1.91);
    });

    test('a post that stored no shape is measured instead', () {
      expect(photoPostRatio(null), isNull);
      expect(photoPostRatio(0), isNull);
    });

    test('a malformed shape cannot blow out the feed', () {
      expect(photoPostRatio(0.1), 9 / 16);
      expect(photoPostRatio(5), 1.91);
    });
  });

  group('rendering the crop', () {
    testWidgets('keeps the whole photo when the frame covers it all',
        (tester) async {
      final jpeg = await tester.runAsync(
        () => renderCrop(
          _halves(200, 100),
          quarterTurns: 0,
          fraction: const Rect.fromLTWH(0, 0, 1, 1),
        ),
      );
      final out = img.decodeJpg(jpeg!)!;

      expect((out.width, out.height), (200, 100));
      expect(_isRed(out.getPixel(10, 50)), isTrue);
      expect(_isBlue(out.getPixel(190, 50)), isTrue);
    });

    testWidgets('turns the photo clockwise, as the screen showed it',
        (tester) async {
      final jpeg = await tester.runAsync(
        () => renderCrop(
          _halves(200, 100),
          quarterTurns: 1,
          fraction: const Rect.fromLTWH(0, 0, 1, 1),
        ),
      );
      final out = img.decodeJpg(jpeg!)!;

      // Turned clockwise, the red left half becomes the top.
      expect((out.width, out.height), (100, 200));
      expect(_isRed(out.getPixel(50, 10)), isTrue);
      expect(_isBlue(out.getPixel(50, 190)), isTrue);
    });

    testWidgets('cuts out only the framed part', (tester) async {
      final jpeg = await tester.runAsync(
        () => renderCrop(
          _halves(200, 100),
          quarterTurns: 0,
          // The right half: all blue.
          fraction: const Rect.fromLTWH(0.5, 0, 0.5, 1),
        ),
      );
      final out = img.decodeJpg(jpeg!)!;

      expect((out.width, out.height), (100, 100));
      expect(_isBlue(out.getPixel(5, 50)), isTrue);
      expect(_isBlue(out.getPixel(95, 50)), isTrue);
    });
  });

  group('crop screen', () {
    Future<void> pumpScreen(
      WidgetTester tester, {
      required List<CropShape> shapes,
    }) async {
      final bytes = _halves(40, 30);
      await tester.pumpWidget(
        MaterialApp(home: CropPhotoScreen(bytes: bytes, shapes: shapes)),
      );
      // Let the engine decode the photo, then build with it.
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 200),
          ));
      await tester.pump();
    }

    testWidgets('a photo post offers only 9:16, so shows no shape row',
        (tester) async {
      await pumpScreen(tester, shapes: CropShape.storyOnly);

      expect(find.text('Crop photo'), findsOneWidget);
      expect(find.text('Use photo'), findsOneWidget);
      expect(find.text('9:16'), findsNothing);
      expect(find.text('4:5'), findsNothing);
    });

    testWidgets('a profile photo is framed in a circle under its own title',
        (tester) async {
      final bytes = _halves(40, 30);
      await tester.pumpWidget(
        MaterialApp(
          home: CropPhotoScreen(
            bytes: bytes,
            shapes: const [CropShape.avatar],
            title: 'Move and scale',
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();

      expect(find.text('Move and scale'), findsOneWidget);
      expect(find.text('1:1'), findsNothing);
      expect(CropShape.avatar.circular, isTrue);
      expect(CropShape.avatar.ratio, 1);
    });

    testWidgets('a card background offers every shape, 9:16 first',
        (tester) async {
      await pumpScreen(tester, shapes: CropShape.all);

      for (final label in ['9:16', '4:5', '1:1', '1.91:1']) {
        expect(find.text(label), findsOneWidget);
      }
      final first = tester.getTopLeft(find.text('9:16')).dx;
      expect(first, lessThan(tester.getTopLeft(find.text('4:5')).dx));
    });
  });
}
