import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/shared/services/run_card_exporter.dart';

/// The capture half of the exporter, on the live binding.
///
/// [renderRunCardPng] waits on real frames and real image decoding, and the
/// default test binding gives it neither: its clock is fake, so `endOfFrame`
/// never completes unless the tester pumps, and `toImage` never returns unless
/// the work is inside `runAsync` — which cannot pump. The live binding drives
/// its own frames and lets real async finish, so the pipeline runs here exactly
/// as it does on a device.
///
/// The cheap assertions about what the card *builds* stay under the default
/// binding in run_card_export_test.dart.

const _route = [
  RoutePoint(latitude: -26.20, longitude: 28.00),
  RoutePoint(latitude: -26.21, longitude: 28.02),
  RoutePoint(latitude: -26.22, longitude: 28.01),
];

/// Short labels on purpose. `flutter_test` substitutes Ahem, whose every glyph
/// is a full em square, so the stat row runs about 30% wider here than it does
/// in the shipping font — "5.20 km" alongside "28:14" overflows the card in the
/// test and nowhere else. These assertions are about the ground and the
/// dimensions, so the fixture stays inside the test font's width.
const _spec = RunCardExport(
  route: _route,
  distanceLabel: '5.2 km',
  durationLabel: '28:14',
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
  RunCardExport spec = _spec,
}) async {
  final context = await hostContext(tester, dark: dark);
  final bytes = await renderRunCardPng(context, spec);
  final image = await decodeImageFromList(bytes);
  addTearDown(image.dispose);
  final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return (image, raw);
}

/// A one-colour PNG, for standing in for a backdrop photo without a network.
Future<Uint8List> solidPng(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 8, 8),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(8, 8);
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

  testWidgets('comes out 1080 by 1920 with no photo to take a shape from',
      (tester) async {
    final (image, _) = await capture(tester);

    expect(image.width, 1080);
    expect(image.height, 1920); // no background: the app's 9:16
  });

  testWidgets('takes the photo\'s own shape instead of a forced crop',
      (tester) async {
    // 8x8 painted as 4 wide, 2 tall: an unambiguous 2:1 photo. A forced 4:3
    // card would come out wrong in either dimension.
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 16, 8),
      Paint()..color = const Color(0xFF00AA44),
    );
    final picture = recorder.endRecording();
    final photoImage = await picture.toImage(16, 8);
    final data =
        (await photoImage.toByteData(format: ui.ImageByteFormat.png))!;
    picture.dispose();
    photoImage.dispose();
    final photo = MemoryImage(data.buffer.asUint8List());

    final (image, _) = await capture(tester, spec: _spec.withBackground(photo));

    expect(image.width, 1080);
    expect(image.height, 540); // 2:1, the photo's own ratio
  });

  testWidgets('is opaque and dark on the dark theme', (tester) async {
    final (image, raw) = await capture(tester);

    // Top edge, mid-width: clear of the wordmark, the line and the numbers.
    final pixel = pixelAt(raw, image.width, 540, 24);
    expect(pixel.a, 255, reason: 'a file has nothing to be transparent over');
    expect(lumaOf(pixel), lessThan(40));
  });

  testWidgets('has no transparent corner for Instagram to fill in black',
      (tester) async {
    final (image, raw) = await capture(tester);

    // Outside the card's 20px corner radius, where the app's page would show
    // through on screen. Every corner, because only one of them is drawn by
    // the ColoredBox's own edge.
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

    final pixel = pixelAt(raw, image.width, 540, 24);
    expect(pixel.a, 255);
    expect(lumaOf(pixel), greaterThan(200));
  });

  testWidgets('draws the photo when there is one', (tester) async {
    final photo = MemoryImage(await solidPng(const Color(0xFF00AA44)));
    final (image, raw) = await capture(
      tester,
      spec: _spec.withBackground(photo),
    );

    // Mid-height, near the right edge: the scrim is at its lightest across the
    // middle band and the route line never reaches the margin.
    final pixel = pixelAt(raw, image.width, 1050, 405);
    expect(pixel.g, greaterThan(pixel.r));
    expect(pixel.g, greaterThan(pixel.b));
  });

  testWidgets('says so when the photo will not load', (tester) async {
    final context = await hostContext(tester);

    await expectLater(
      renderRunCardPng(
        context,
        const RunCardExport(route: _route).withBackground(
          const NetworkImage('https://example.invalid/missing.jpg'),
        ),
      ),
      throwsA(isA<RunCardExportException>()),
    );
  });
}

extension on RunCardExport {
  RunCardExport withBackground(ImageProvider background) => RunCardExport(
        route: route,
        distanceLabel: distanceLabel,
        durationLabel: durationLabel,
        background: background,
      );
}
