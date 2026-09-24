import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

import '../widgets/picture_ratio.dart';

/// A shape the crop screen can frame a photo to.
@immutable
class CropShape {
  const CropShape(this.label, this.ratio, {this.circular = false});

  /// "9:16", as printed on the chip.
  final String label;

  /// width / height.
  final double ratio;

  /// Framed as the circle the photo will be shown in, rather than as a
  /// rounded card. The saved image is still the square around it.
  final bool circular;

  /// 1080x1920 — the app's picture shape, and the default everywhere.
  static const story = CropShape('9:16', kPictureAspectRatio);

  /// 1080x1350.
  static const portrait = CropShape('4:5', 4 / 5);

  /// 1080x1080.
  static const square = CropShape('1:1', 1);

  /// 1080x566.
  static const landscape = CropShape('1.91:1', kWidestPictureRatio);

  /// Everything a card's background photo may take, 9:16 first.
  static const all = <CropShape>[story, portrait, square, landscape];

  /// A photo post: only the app's own shape.
  static const storyOnly = <CropShape>[story];

  /// A profile photo: the circle every avatar is drawn in.
  static const avatar = CropShape('1:1', 1, circular: true);
}

/// The crop screen's arithmetic, kept apart from the widgets so it can be
/// tested on its own.
///
/// Everything is in screen pixels except where it says otherwise. The photo is
/// placed by a [scale] (screen pixels per photo pixel) and an [offset] — how
/// far the photo's centre sits from the frame's centre.
abstract final class CropGeometry {
  /// The largest [ratio]-shaped frame that fits in [area].
  static Size fitFrame(Size area, double ratio) {
    if (area.isEmpty) return Size.zero;
    if (area.width / area.height > ratio) {
      return Size(area.height * ratio, area.height);
    }
    return Size(area.width, area.width / ratio);
  }

  /// The photo's size once turned [quarterTurns] times clockwise.
  static Size turned(Size photo, int quarterTurns) =>
      quarterTurns.isOdd ? photo.flipped : photo;

  /// The smallest scale at which [photo] still covers [frame] — the crop can
  /// never reach past the edge of the picture.
  static double coverScale(Size photo, Size frame) => math.max(
        frame.width / photo.width,
        frame.height / photo.height,
      );

  /// [offset] pulled back so the photo still covers the frame at [scale].
  static Offset clampOffset(
    Offset offset,
    Size photo,
    double scale,
    Size frame,
  ) {
    final slackX = math.max(0.0, (photo.width * scale - frame.width) / 2);
    final slackY = math.max(0.0, (photo.height * scale - frame.height) / 2);
    return Offset(
      offset.dx.clamp(-slackX, slackX),
      offset.dy.clamp(-slackY, slackY),
    );
  }

  /// The part of the photo inside the frame, as fractions of the photo's own
  /// width and height, so it applies at whatever resolution the photo is
  /// decoded at for the final image.
  static Rect cropFraction({
    required Size photo,
    required double scale,
    required Offset offset,
    required Size frame,
  }) {
    final shownWidth = photo.width * scale;
    final shownHeight = photo.height * scale;
    final left = (shownWidth - frame.width) / 2 - offset.dx;
    final top = (shownHeight - frame.height) / 2 - offset.dy;
    return Rect.fromLTWH(
      left / shownWidth,
      top / shownHeight,
      frame.width / shownWidth,
      frame.height / shownHeight,
    );
  }

  /// The pixel size of the final image: the crop at full resolution, brought
  /// down to fit [maxWidth] by [maxHeight] and never scaled up.
  static (int, int) outputSize(Size crop,
      {int maxWidth = 1080, int maxHeight = 1920}) {
    final scale = math.min(
      1.0,
      math.min(maxWidth / crop.width, maxHeight / crop.height),
    );
    return (
      math.max(1, (crop.width * scale).round()),
      math.max(1, (crop.height * scale).round()),
    );
  }
}

/// Longest side a photo is decoded at for the final crop. The output is at
/// most 1920 tall, so this leaves room to zoom in without going soft, while
/// a 50-megapixel original never has to be held in memory whole.
const int _maxDecodeSide = 4096;

/// Decodes [bytes] with its longest side at most [maxSide].
///
/// The engine applies the photo's EXIF orientation here, so what comes back
/// is upright — the same picture the crop screen shows.
Future<ui.Image> decodePhoto(Uint8List bytes,
    {int maxSide = _maxDecodeSide}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (width, height) {
      final longest = math.max(width, height);
      if (longest <= maxSide) {
        return ui.TargetImageSize(width: width, height: height);
      }
      final scale = maxSide / longest;
      return ui.TargetImageSize(
        width: (width * scale).round(),
        height: (height * scale).round(),
      );
    },
  );
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// Cuts [fraction] out of [source] turned [quarterTurns] times clockwise, and
/// returns it as an upload-ready JPEG: at most 1080 wide and 1920 tall.
///
/// The crop is drawn by the engine straight into an image of the final size,
/// so only the JPEG encode runs in Dart, and that runs off the UI thread.
Future<Uint8List> renderCrop(
  Uint8List source, {
  required int quarterTurns,
  required Rect fraction,
  int quality = 80,
}) async {
  final photo = await decodePhoto(source);
  ui.Image? output;
  try {
    final width = photo.width.toDouble();
    final height = photo.height.toDouble();
    final turned = CropGeometry.turned(Size(width, height), quarterTurns);
    final crop = Rect.fromLTWH(
      fraction.left * turned.width,
      fraction.top * turned.height,
      fraction.width * turned.width,
      fraction.height * turned.height,
    );
    final (outWidth, outHeight) = CropGeometry.outputSize(crop.size);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(outWidth / crop.width, outHeight / crop.height)
      ..translate(-crop.left, -crop.top);
    // Turn the photo clockwise about its own corner, then slide it back into
    // view — the same turn RotatedBox shows on screen.
    switch (quarterTurns % 4) {
      case 1:
        canvas
          ..translate(height, 0)
          ..rotate(math.pi / 2);
      case 2:
        canvas
          ..translate(width, height)
          ..rotate(math.pi);
      case 3:
        canvas
          ..translate(0, width)
          ..rotate(3 * math.pi / 2);
    }
    canvas.drawImage(
      photo,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    output = await picture.toImage(outWidth, outHeight);
    picture.dispose();

    final raw = await output.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) throw StateError('The crop could not be read back.');
    return compute(
      _encodeJpeg,
      _RawCrop(
        bytes: raw.buffer.asUint8List(),
        width: outWidth,
        height: outHeight,
        quality: quality,
      ),
    );
  } finally {
    photo.dispose();
    output?.dispose();
  }
}

/// Raw pixels on their way to an isolate.
class _RawCrop {
  const _RawCrop({
    required this.bytes,
    required this.width,
    required this.height,
    required this.quality,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int quality;
}

Uint8List _encodeJpeg(_RawCrop crop) {
  final image = img.Image.fromBytes(
    width: crop.width,
    height: crop.height,
    bytes: crop.bytes.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: crop.quality);
}
