import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/shared/services/workout_card_exporter.dart';

/// The capture half of the workout exporter, on the live binding — see
/// run_card_capture_test.dart for why the default binding cannot drive it.
///
/// The cheap assertions about what the card *builds* stay under the default
/// binding in workout_card_export_test.dart.

/// Short names on purpose: `flutter_test` substitutes Ahem, whose every glyph
/// is a full em square, so a long exercise name would overflow the row here
/// and nowhere else.
const _spec = WorkoutCardExport(
  activity: 'Workout',
  workoutData: {
    'title': 'Legs',
    'duration': '45 min',
    'exercises': [
      {'name': 'Squat', 'sets': 5, 'reps': 8, 'weightKg': 80},
      {'name': 'Lunge', 'sets': 3, 'reps': 12, 'weightKg': 20},
    ],
  },
);

/// The RGBA pixel at ([x], [y]) of a raw buffer [width] pixels wide.
({int r, int g, int b, int a}) pixelAt(ByteData raw, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  return (
    r: raw.getUint8(offset),
    g: raw.getUint8(offset + 1),
    b: raw.getUint8(offset + 2),
    a: raw.getUint8(offset + 3),
  );
}

double lumaOf(({int r, int g, int b, int a}) pixel) =>
    0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b;

/// Pumps a host and hands back a context that can reach the root [Overlay].
Future<BuildContext> hostContext(
  WidgetTester tester, {
  bool dark = true,
}) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Builder(
        builder: (context) {
          captured = context;
          return const Scaffold(body: SizedBox.shrink());
        },
      ),
    ),
  );
  await tester.pump();
  return captured;
}

/// The exported PNG, decoded, with its raw pixels.
Future<(ui.Image, ByteData)> capture(
  WidgetTester tester, {
  bool dark = true,
  WorkoutCardExport spec = _spec,
}) async {
  final context = await hostContext(tester, dark: dark);
  final bytes = await renderWorkoutCardPng(context, spec);
  final image = await decodeImageFromList(bytes);
  addTearDown(image.dispose);
  final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return (image, raw);
}

/// A one-colour PNG of [width] by [height], standing in for a backdrop photo
/// without a network.
Future<Uint8List> solidPng(Color color, {int width = 8, int height = 8}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  final binding = LiveTestWidgetsFlutterBinding.ensureInitialized();
  // Free-running frames. The live binding otherwise only draws when the tester
  // pumps, and the exporter waits on `endOfFrame` from inside its own call —
  // there is no tester in there to pump for it.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('comes out 1080 wide and at least 9:16 tall', (tester) async {
    final (image, _) = await capture(tester);

    expect(image.width, 1080);
    // Two rows plus the totals strip need far less than that, so the app's
    // 9:16 is what sets the file. A few pixels short of 1920 at most: the
    // minimum is measured inside the card's one-pixel stroke.
    expect(image.height, closeTo(1920, 6));
  });

  testWidgets('is at least the photo\'s own shape when there is one',
      (tester) async {
    // 8 by 16: a 1:2 photo, which is clamped to the app's 9:16. Two rows of
    // log need far less than that in height, so the photo's minimum is what
    // sets the file — and the ratio came from the exporter's own decode, since
    // the card cannot measure a MemoryImage by URL.
    final photo = MemoryImage(
      await solidPng(const Color(0xFF00AA44), width: 8, height: 16),
    );

    final (image, _) = await capture(tester, spec: _spec.withBackground(photo));

    expect(image.width, 1080);
    // Within a few pixels: the minimum is a division at layout width inside
    // the card's stroke, not an AspectRatio, so it lands a little short.
    expect(image.height, closeTo(1920, 6));
  });

  testWidgets('grows past a short photo rather than clipping the log',
      (tester) async {
    // 16 by 8: a 2:1 photo, 540px tall at export width. Two rows plus the
    // totals strip need more than that, so the card takes the height the
    // sheet needs and the photo gives up its edges — the same trade the feed
    // makes.
    final photo = MemoryImage(
      await solidPng(const Color(0xFF00AA44), width: 16, height: 8),
    );

    final (image, _) = await capture(tester, spec: _spec.withBackground(photo));

    expect(image.width, 1080);
    expect(image.height, greaterThan(540));
  });

  testWidgets('is opaque and dark on the dark theme', (tester) async {
    final (image, raw) = await capture(tester);

    // Just under the card's stroke, mid-width: inside the top padding, clear
    // of the title at the left and the wordmark at the right.
    final pixel = pixelAt(raw, image.width, 540, 12);
    expect(pixel.a, 255, reason: 'a file has nothing to be transparent over');
    expect(lumaOf(pixel), lessThan(40));
  });

  testWidgets('has no transparent corner for Instagram to fill in black',
      (tester) async {
    final (image, raw) = await capture(tester);

    // Outside the card's 20px corner radius, where the app's page would show
    // through on screen.
    for (final (x, y) in [
      (2, 2),
      (image.width - 3, 2),
      (2, image.height - 3),
      (image.width - 3, image.height - 3),
    ]) {
      expect(
        pixelAt(raw, image.width, x, y).a,
        255,
        reason: 'corner ($x, $y) is see-through',
      );
    }
  });

  testWidgets('is opaque and light on the light theme', (tester) async {
    final (image, raw) = await capture(tester, dark: false);

    final pixel = pixelAt(raw, image.width, 540, 12);
    expect(pixel.a, 255);
    expect(lumaOf(pixel), greaterThan(200));
  });

  testWidgets('draws the photo when there is one', (tester) async {
    final photo = MemoryImage(
      await solidPng(const Color(0xFF00AA44), width: 16, height: 8),
    );
    final (image, raw) = await capture(
      tester,
      spec: _spec.withBackground(photo),
    );

    // Near the top edge, mid-width: the scrim is at its lightest there and
    // the sheet sits along the bottom.
    final pixel = pixelAt(raw, image.width, 540, 30);
    expect(pixel.g, greaterThan(pixel.r));
    expect(pixel.g, greaterThan(pixel.b));
  });

  testWidgets('says so when the photo will not load', (tester) async {
    final context = await hostContext(tester);

    await expectLater(
      renderWorkoutCardPng(
        context,
        _spec.withBackground(
          const NetworkImage('https://example.invalid/missing.jpg'),
        ),
      ),
      throwsA(isA<WorkoutCardExportException>()),
    );
  });
}

extension on WorkoutCardExport {
  WorkoutCardExport withBackground(ImageProvider background) =>
      WorkoutCardExport(
        activity: activity,
        workoutData: workoutData,
        background: background,
      );
}
