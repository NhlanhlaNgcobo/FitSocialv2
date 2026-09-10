import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/pulse/presentation/pulse_photo_frame.dart';

/// An [ImageProvider] that hands back an already-decoded image, so a frame can
/// be pumped without a file or a network fetch behind it.
class _FakePhoto extends ImageProvider<_FakePhoto> {
  const _FakePhoto(this.image);

  final ui.Image image;

  @override
  Future<_FakePhoto> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FakePhoto>(this);

  @override
  ImageStreamCompleter loadImage(_FakePhoto key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: image.clone())),
    );
  }
}

/// An [ImageProvider] whose decode always fails.
class _BrokenPhoto extends ImageProvider<_BrokenPhoto> {
  const _BrokenPhoto();

  @override
  Future<_BrokenPhoto> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_BrokenPhoto>(this);

  @override
  ImageStreamCompleter loadImage(
    _BrokenPhoto key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      Future<ImageInfo>.error(Exception('no such photo')),
    );
  }
}

void main() {
  testWidgets('the photo is shown whole rather than cropped to the screen',
      (tester) async {
    // A wide photo in a portrait frame: the shape a 9:16 crop used to destroy.
    final photo = await tester.runAsync(
      () => createTestImage(width: 40, height: 10),
    );
    await tester.pumpWidget(
      MaterialApp(home: PulsePhotoFrame(image: _FakePhoto(photo!))),
    );

    final foreground = find.descendant(
      of: find.byType(PulsePhotoFrame),
      matching: find.byWidgetPredicate(
        (widget) => widget is Image && widget.fit == BoxFit.contain,
      ),
    );
    expect(foreground, findsOneWidget);
  });

  testWidgets('what the photo does not cover is a blurred copy of it',
      (tester) async {
    final photo = await tester.runAsync(
      () => createTestImage(width: 40, height: 10),
    );
    await tester.pumpWidget(
      MaterialApp(home: PulsePhotoFrame(image: _FakePhoto(photo!))),
    );

    // The backdrop is the same photo, blurred and stretched to fill — not a
    // black bar, and not some unrelated colour.
    final backdrop = find.descendant(
      of: find.byType(ImageFiltered),
      matching: find.byType(Image),
    );
    expect(backdrop, findsOneWidget);
    expect(tester.widget<Image>(backdrop).fit, BoxFit.cover);
  });

  testWidgets('a photo that fails to decode reports itself once',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PulsePhotoFrame(
          image: const _BrokenPhoto(),
          errorBuilder: (_, __, ___) => const Text('unavailable'),
        ),
      ),
    );
    await tester.pump();

    // The backdrop fails silently alongside it: one message, not two.
    expect(find.text('unavailable'), findsOneWidget);
  });
}
