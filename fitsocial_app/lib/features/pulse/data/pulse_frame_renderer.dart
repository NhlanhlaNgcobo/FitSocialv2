import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// A framing that could not be rendered, carrying the line to show the user.
class PulseFrameRenderException implements Exception {
  const PulseFrameRenderException(this.message);

  /// Written for the toast, not for a log.
  final String message;

  @override
  String toString() => 'PulseFrameRenderException: $message';
}

/// The framed photo, as it will be published.
class PulseFrameFile {
  const PulseFrameFile({required this.path, required this.aspectRatio});

  final String path;

  /// The frame's own shape, which is now the photo's shape.
  final double aspectRatio;
}

/// The width every framed Pulse comes out at. Instagram's story spec, and wide
/// enough that a phone screen never has to upscale it.
const int kPulseFrameWidth = 1080;

/// Rasterises what the composer is showing and writes it out as a JPEG.
///
/// The framing someone chose with their fingers only survives if it is baked
/// in. Storing the pinch as numbers and replaying it would re-derive the crop
/// against whatever shape the *viewer's* screen happens to be, and the picture
/// would land somewhere its author never put it. What is captured here is the
/// canvas itself — blurred backdrop, photo, and the exact placement — so every
/// viewer sees the frame that was composed.
///
/// [boundaryKey] must be on a [RepaintBoundary] that is currently on screen and
/// painted; the composer's canvas is one.
Future<PulseFrameFile> renderPulseFrame(GlobalKey boundaryKey) async {
  if (kIsWeb) {
    throw const PulseFrameRenderException('Framing a photo needs the app.');
  }

  // The share button's own setState has just marked the tree dirty. Letting
  // that frame finish first means the layer being rasterised is the one the
  // person was looking at when they pressed it.
  await WidgetsBinding.instance.endOfFrame;

  final boundary =
      boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) {
    throw const PulseFrameRenderException("Couldn't frame that photo.");
  }

  final size = boundary.size;
  if (size.isEmpty) {
    throw const PulseFrameRenderException("Couldn't frame that photo.");
  }

  ui.Image? captured;
  try {
    captured = await boundary.toImage(pixelRatio: kPulseFrameWidth / size.width);
    final raw = await captured.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) {
      throw const PulseFrameRenderException("Couldn't frame that photo.");
    }

    // Off the UI thread: encoding a full-screen frame in pure Dart takes long
    // enough to drop frames, and the composer is still on screen behind the
    // spinner.
    final jpeg = await compute(
      _encodeJpeg,
      _RawFrame(
        bytes: raw.buffer.asUint8List(),
        width: captured.width,
        height: captured.height,
      ),
    );

    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/pulse_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(jpeg, flush: true);

    return PulseFrameFile(
      path: file.path,
      aspectRatio: captured.width / captured.height,
    );
  } on PulseFrameRenderException {
    rethrow;
  } catch (error, stack) {
    // Reported rather than rethrown raw: the user gets a line they can read,
    // and the real failure still reaches Crashlytics.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'fitsocial',
        context: ErrorDescription('rendering a framed Pulse photo'),
      ),
    );
    throw const PulseFrameRenderException("Couldn't frame that photo.");
  } finally {
    captured?.dispose();
  }
}

/// Raw pixels on their way to an isolate.
class _RawFrame {
  const _RawFrame({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// The quality the picker used to encode at, kept so a Pulse looks the same
/// weight as it always did.
const int _quality = 82;

Uint8List _encodeJpeg(_RawFrame frame) {
  final image = img.Image.fromBytes(
    width: frame.width,
    height: frame.height,
    bytes: frame.bytes.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: _quality);
}
