import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../app/theme/app_colors.dart';

/// The three pins a [RunRouteMap] puts on a route, drawn by hand rather than
/// borrowed from the stock Google teardrops.
///
/// A teardrop points at its spot with its tip, so centring one on the route —
/// which the map has to, for a dot on a line — leaves the tip floating off the
/// start. These are round and sit dead on the point they mark.
enum RunMapMarker {
  /// Where the run began: a white disc with a dark core, quiet on purpose so
  /// it never competes with where the runner is now.
  start,

  /// Where a finished run ended: a chequered flag disc.
  finish,

  /// The runner right now: a brand-orange dot with a white rim and a soft
  /// halo around it.
  current,
}

/// Diameter of each marker's visible disc, in logical pixels. The current dot
/// carries a halo outside this.
const _discSize = <RunMapMarker, double>{
  RunMapMarker.start: 16,
  RunMapMarker.finish: 22,
  RunMapMarker.current: 18,
};

/// Room around the disc for the shadow and, on the current dot, the halo.
const _bleed = <RunMapMarker, double>{
  RunMapMarker.start: 4,
  RunMapMarker.finish: 4,
  RunMapMarker.current: 9,
};

final _cache = <(RunMapMarker, double), Future<BitmapDescriptor>>{};

/// The icon for [marker], drawn once per device pixel ratio and kept.
Future<BitmapDescriptor> runMapMarkerIcon(
  RunMapMarker marker,
  double devicePixelRatio,
) {
  return _cache.putIfAbsent(
    (marker, devicePixelRatio),
    () => _draw(marker, devicePixelRatio),
  );
}

Future<BitmapDescriptor> _draw(RunMapMarker marker, double dpr) async {
  final disc = _discSize[marker]!;
  final logical = disc + _bleed[marker]! * 2;
  final pixels = (logical * dpr).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(dpr);
  final centre = Offset(logical / 2, logical / 2);
  final radius = disc / 2;

  switch (marker) {
    case RunMapMarker.start:
      _shadow(canvas, centre, radius);
      canvas.drawCircle(
          centre, radius, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawCircle(
        centre,
        radius * 0.45,
        Paint()..color = const Color(0xFF1A1A1A),
      );
    case RunMapMarker.finish:
      _shadow(canvas, centre, radius);
      canvas.drawCircle(
          centre, radius, Paint()..color = const Color(0xFFFFFFFF));
      _chequers(canvas, centre, radius - 2.5);
    case RunMapMarker.current:
      canvas.drawCircle(
        centre,
        radius + _bleed[marker]!,
        Paint()..color = AppColors.orangeBright.withValues(alpha: 0.22),
      );
      _shadow(canvas, centre, radius);
      canvas.drawCircle(
          centre, radius, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawCircle(
        centre,
        radius - 3,
        Paint()..color = AppColors.orangeBright,
      );
  }

  final image = await recorder.endRecording().toImage(pixels, pixels);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();

  return BitmapDescriptor.bytes(
    png!.buffer.asUint8List(),
    width: logical,
    height: logical,
  );
}

void _shadow(Canvas canvas, Offset centre, double radius) {
  canvas.drawCircle(
    centre.translate(0, 1),
    radius,
    Paint()
      ..color = const Color(0x59000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
  );
}

/// A 4×4 chessboard clipped to a circle — the finish flag.
void _chequers(Canvas canvas, Offset centre, double radius) {
  final square = radius * 2 / 4;
  final origin = centre - Offset(radius, radius);
  canvas
    ..save()
    ..clipPath(
        Path()..addOval(Rect.fromCircle(center: centre, radius: radius)));
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 4; col++) {
      if ((row + col).isOdd) continue;
      canvas.drawRect(
        Rect.fromLTWH(
          origin.dx + col * square,
          origin.dy + row * square,
          // A hair over, so neighbouring squares never leave a seam.
          square + 0.01,
          square + 0.01,
        ),
        Paint()..color = const Color(0xFF111111),
      );
    }
  }
  canvas.restore();
}
