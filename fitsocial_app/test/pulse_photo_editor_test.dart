import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/pulse/presentation/pulse_photo_editor.dart';

/// An [ImageProvider] that hands back an already-decoded image, so the editor
/// can be measured without a file or a network fetch behind it.
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

/// A 400x800 frame — a phone, near enough — so the arithmetic below is the
/// arithmetic a thumb actually drives.
const Size _frame = Size(400, 800);

Matrix4 _placement(WidgetTester tester) {
  return tester
      .widget<Transform>(
        find.descendant(
          of: find.byType(PulsePhotoEditor),
          matching: find.byType(Transform),
        ),
      )
      .transform;
}

double _scaleOf(WidgetTester tester) => _placement(tester).getMaxScaleOnAxis();

/// Pinches with two fingers, from [from] apart to [to] apart, centred on the
/// frame.
Future<void> pinch(WidgetTester tester, double from, double to) async {
  final centre = Offset(_frame.width / 2, _frame.height / 2);
  final first = await tester.startGesture(centre - Offset(from / 2, 0));
  final second = await tester.startGesture(centre + Offset(from / 2, 0));
  await tester.pump();

  await first.moveTo(centre - Offset(to / 2, 0));
  await second.moveTo(centre + Offset(to / 2, 0));
  await tester.pump();

  await first.up();
  await second.up();
  await tester.pump();
}

Future<void> pumpEditor(WidgetTester tester, ui.Image photo) async {
  tester.view.physicalSize = _frame;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(home: PulsePhotoEditor(image: _FakePhoto(photo))),
  );
  // One frame to lay out, a second for the measurement the first scheduled.
  await tester.pump();
  await tester.pump();
}

void main() {
  // A wide photo in a portrait frame: fitted it spans the full width and
  // leaves blurred backdrop above and below.
  Future<ui.Image> widePhoto(WidgetTester tester) async {
    final photo = await tester.runAsync(
      () => createTestImage(width: 40, height: 10),
    );
    return photo!;
  }

  testWidgets('opens on the whole photo, untouched', (tester) async {
    await pumpEditor(tester, await widePhoto(tester));

    expect(_scaleOf(tester), 1);
    expect(_placement(tester).getTranslation().x, 0);
  });

  testWidgets('fingers moving apart expand the photo', (tester) async {
    await pumpEditor(tester, await widePhoto(tester));

    await pinch(tester, 60, 120);

    expect(_scaleOf(tester), closeTo(2, 0.01));
  });

  testWidgets('fingers moving together shrink it back', (tester) async {
    await pumpEditor(tester, await widePhoto(tester));

    await pinch(tester, 60, 240);
    expect(_scaleOf(tester), closeTo(4, 0.01));

    await pinch(tester, 240, 120);
    expect(_scaleOf(tester), closeTo(2, 0.01));
  });

  // Pinching past the whole photo would only add blurred backdrop around a
  // picture that is already entirely visible.
  testWidgets('shrinking stops at the whole photo', (tester) async {
    await pumpEditor(tester, await widePhoto(tester));

    await pinch(tester, 60, 180);
    expect(_scaleOf(tester), closeTo(3, 0.01));

    await pinch(tester, 240, 40);

    expect(_scaleOf(tester), PulsePhotoEditor.minScale);
  });

  testWidgets('a zoomed photo cannot be dragged off its own edge',
      (tester) async {
    await pumpEditor(tester, await widePhoto(tester));

    await pinch(tester, 60, 120);
    // Zoomed 2x, the photo is 800 wide in a 400 frame, so it can travel 400px
    // left and no further right than its own left edge.
    await tester.drag(find.byType(PulsePhotoEditor), const Offset(600, 0));
    await tester.pump();

    expect(_placement(tester).getTranslation().x, 0);

    await tester.drag(find.byType(PulsePhotoEditor), const Offset(-600, 0));
    await tester.pump();

    expect(_placement(tester).getTranslation().x, -400);
  });

  // Nothing to pan to: the whole photo is on screen, and letting it slide
  // would just hang it off one side of the frame.
  testWidgets('an unzoomed photo stays put when dragged', (tester) async {
    await pumpEditor(tester, await widePhoto(tester));

    await tester.drag(find.byType(PulsePhotoEditor), const Offset(120, 90));
    await tester.pump();

    expect(_placement(tester).getTranslation().x, 0);
    expect(_scaleOf(tester), 1);
  });
}
