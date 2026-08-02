import 'package:flutter_test/flutter_test.dart';
import 'package:fitsocial_app/features/main/data/image_pipeline.dart';

void main() {
  group('FeedGeometry caps width at 1080', () {
    test('a wide landscape photo is scaled down to 1080 wide', () {
      // 4032x3024 — a typical 12MP phone photo, 4:3 landscape.
      final geometry = FeedGeometry.forSource(4032, 3024);

      expect(geometry.width, 1080);
      expect(geometry.height, 810); // 3024 * 1080/4032
      expect(geometry.cropRequired, isFalse);
    });

    test('a square photo stays square', () {
      final geometry = FeedGeometry.forSource(3000, 3000);

      expect(geometry.width, 1080);
      expect(geometry.height, 1080);
      expect(geometry.cropRequired, isFalse);
    });
  });

  group('FeedGeometry enforces the 4:5 portrait limit', () {
    test('a 9:16 photo is cropped to exactly 1080x1350', () {
      // 1080x1920 scales to 1920 tall, well beyond the 1350 ceiling.
      final geometry = FeedGeometry.forSource(1080, 1920);

      expect(geometry.width, 1080);
      expect(geometry.height, 1350);
      expect(geometry.cropRequired, isTrue);
      expect(geometry.scaledHeight, 1920);
      // Crop window centred: (1920 - 1350) / 2
      expect(geometry.cropTop, 285);
    });

    test('an exactly 4:5 photo is not cropped', () {
      final geometry = FeedGeometry.forSource(1080, 1350);

      expect(geometry.height, 1350);
      expect(geometry.cropRequired, isFalse);
      expect(geometry.cropTop, 0);
    });

    test('one pixel past 4:5 does trigger a crop', () {
      final geometry = FeedGeometry.forSource(1080, 1351);

      expect(geometry.cropRequired, isTrue);
      expect(geometry.height, 1350);
    });

    test('an extremely tall panorama is still bounded at 1350', () {
      final geometry = FeedGeometry.forSource(1000, 20000);

      expect(geometry.cropRequired, isTrue);
      // Width is 1000 (never upscaled), so the 4:5 cap is proportional.
      expect(geometry.width, 1000);
      expect(geometry.height, 1250);
    });
  });

  group('FeedGeometry never upscales', () {
    test('a small image keeps its original dimensions', () {
      final geometry = FeedGeometry.forSource(640, 480);

      expect(geometry.width, 640);
      expect(geometry.height, 480);
      expect(geometry.cropRequired, isFalse);
    });

    test('a narrow tall image is capped proportionally, not stretched', () {
      final geometry = FeedGeometry.forSource(500, 2000);

      expect(geometry.width, 500);
      // 4:5 of 500 is 625, not the literal 1350.
      expect(geometry.height, 625);
      expect(geometry.cropRequired, isTrue);
    });
  });

  group('FeedGeometry rejects nonsense input', () {
    test('zero and negative dimensions throw', () {
      expect(() => FeedGeometry.forSource(0, 100),
          throwsA(isA<ImageProcessingException>()));
      expect(() => FeedGeometry.forSource(100, 0),
          throwsA(isA<ImageProcessingException>()));
      expect(() => FeedGeometry.forSource(-10, 100),
          throwsA(isA<ImageProcessingException>()));
    });
  });

  group('InstagramImageSpec matches the documented standards', () {
    test('constants are the published feed values', () {
      expect(InstagramImageSpec.maxWidth, 1080);
      expect(InstagramImageSpec.maxPortraitHeight, 1350);
      expect(InstagramImageSpec.jpegQuality, 80);
      expect(InstagramImageSpec.maxBytes, 10 * 1024 * 1024);
    });

    test('the aspect ceiling is 4:5', () {
      expect(InstagramImageSpec.maxAspectRatio, closeTo(1.25, 0.0001));
    });
  });
}
