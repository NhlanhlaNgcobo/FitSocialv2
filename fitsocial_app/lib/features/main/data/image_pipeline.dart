import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

/// Instagram's published feed-image constraints.
///
/// Instagram downsizes every upload to 1080px wide and refuses to display a
/// feed image taller than 4:5, so anything taller is cropped rather than
/// letterboxed. Matching these numbers means the app ships the same pixels the
/// feed will actually render — no server-side surprise re-encode.
abstract final class InstagramImageSpec {
  /// Standard feed display width.
  static const int maxWidth = 1080;

  /// Tallest feed image (4:5 portrait) at [maxWidth].
  static const int maxPortraitHeight = 1350;

  /// Portrait limit as a ratio, so narrower sources are capped proportionally
  /// instead of being upscaled to 1080 just to be cropped.
  static const double maxAspectRatio = maxPortraitHeight / maxWidth; // 1.25

  /// JPEG quality for the final encode.
  static const int jpegQuality = 80;

  /// Guardrail. Compression should land orders of magnitude below this — if it
  /// doesn't, something is wrong and we refuse the upload rather than push a
  /// huge object into Storage.
  static const int maxBytes = 10 * 1024 * 1024;
}

/// A processed, upload-ready image and the facts about it.
class ProcessedImage {
  const ProcessedImage({
    required this.optimizedFile,
    required this.width,
    required this.height,
    required this.sizeInBytes,
  });

  final File optimizedFile;
  final int width;
  final int height;
  final int sizeInBytes;

  double get sizeInMb => sizeInBytes / (1024 * 1024);

  @override
  String toString() =>
      'ProcessedImage(${width}x$height, ${sizeInMb.toStringAsFixed(2)} MB)';
}

/// Thrown when the pipeline cannot produce a valid upload-ready image.
class ImageProcessingException implements Exception {
  const ImageProcessingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when the compressed result still exceeds [InstagramImageSpec.maxBytes].
class ImageTooLargeException extends ImageProcessingException {
  const ImageTooLargeException(this.sizeInBytes)
      : super('Processed image is too large to upload.');

  final int sizeInBytes;

  @override
  String toString() =>
      'Processed image is ${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB, '
      'above the ${InstagramImageSpec.maxBytes ~/ (1024 * 1024)} MB limit.';
}

/// The output dimensions [processImageForUpload] will produce for a given
/// source, and whether reaching them needs a centre-crop.
///
/// Split out from the pixel work so the rules can be verified with plain
/// integer arithmetic, no image decoding required.
class FeedGeometry {
  const FeedGeometry({
    required this.width,
    required this.height,
    required this.scaledHeight,
    required this.cropRequired,
  });

  factory FeedGeometry.forSource(int sourceWidth, int sourceHeight) {
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      throw const ImageProcessingException('Image has invalid dimensions.');
    }

    // Never upscale: a 600px-wide source stays 600px rather than being blown
    // up to 1080 and losing sharpness.
    final width = math.min(sourceWidth, InstagramImageSpec.maxWidth);
    final scaledHeight = (sourceHeight * width / sourceWidth).round();

    // 4:5 ceiling expressed relative to the actual width, so a narrow source
    // is held to the same shape rather than the literal 1350px.
    final maxHeight = (width * InstagramImageSpec.maxAspectRatio).round();
    final cropRequired = scaledHeight > maxHeight;

    return FeedGeometry(
      width: width,
      height: cropRequired ? maxHeight : scaledHeight,
      scaledHeight: scaledHeight,
      cropRequired: cropRequired,
    );
  }

  /// Final width — at most [InstagramImageSpec.maxWidth], never upscaled.
  final int width;

  /// Final height after any crop.
  final int height;

  /// Height after scaling but before cropping. Equals [height] when no crop
  /// is needed.
  final int scaledHeight;

  /// True when the source is taller than 4:5 and must be cropped.
  final bool cropRequired;

  /// Row offset that centres the crop window.
  int get cropTop => cropRequired ? ((scaledHeight - height) / 2).round() : 0;
}

/// Geometry result handed back from the background isolate.
class _ResizedImage {
  const _ResizedImage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Resizes [rawImage] to Instagram's feed constraints and compresses it to JPEG.
///
/// Steps, in order:
///   1. Scale down so width is at most 1080px (never upscales a smaller image).
///   2. If the scaled height still exceeds 4:5, centre-crop to that ratio.
///   3. Encode to JPEG at quality 80 via the platform's native compressor.
///
/// Decoding and resizing run on a background isolate — a modern phone photo can
/// be 50+ megapixels, and doing that work on the UI isolate janks the frame for
/// seconds.
///
/// Throws [ImageProcessingException] if the file cannot be decoded, and
/// [ImageTooLargeException] if the compressed result is still oversized.
Future<ProcessedImage> processImageForUpload(File rawImage) async {
  if (!rawImage.existsSync()) {
    throw const ImageProcessingException('Image file no longer exists.');
  }

  final Uint8List rawBytes;
  try {
    rawBytes = await rawImage.readAsBytes();
  } on FileSystemException catch (error) {
    throw ImageProcessingException('Could not read image: ${error.message}');
  }

  if (rawBytes.isEmpty) {
    throw const ImageProcessingException('Image file is empty.');
  }

  final resized = await compute(_resizeToFeedBounds, rawBytes);

  // Work inside a private temp directory so concurrent uploads can't collide
  // on a shared filename.
  final workingDir = await Directory.systemTemp.createTemp('fitsocial_upload_');
  final sourcePath = '${workingDir.path}/source.jpg';
  final targetPath = '${workingDir.path}/optimized.jpg';

  try {
    await File(sourcePath).writeAsBytes(resized.bytes, flush: true);

    // The geometry pass above already produced JPEG bytes; this second pass is
    // the platform's native encoder applying the final quality setting, which
    // compresses noticeably better than the pure-Dart encoder.
    final compressed = await FlutterImageCompress.compressAndGetFile(
      sourcePath,
      targetPath,
      quality: InstagramImageSpec.jpegQuality,
      format: CompressFormat.jpeg,
      // Geometry is already final — passing the exact dimensions stops the
      // compressor from applying a second, unwanted resize.
      minWidth: resized.width,
      minHeight: resized.height,
    );

    if (compressed == null) {
      throw const ImageProcessingException('Image compression failed.');
    }

    final optimizedFile = File(compressed.path);
    final sizeInBytes = optimizedFile.lengthSync();

    if (sizeInBytes > InstagramImageSpec.maxBytes) {
      throw ImageTooLargeException(sizeInBytes);
    }

    return ProcessedImage(
      optimizedFile: optimizedFile,
      width: resized.width,
      height: resized.height,
      sizeInBytes: sizeInBytes,
    );
  } finally {
    // The intermediate is dead weight either way; the optimized file lives on
    // in the same directory until the OS reclaims temp storage.
    final source = File(sourcePath);
    if (source.existsSync()) {
      await source.delete();
    }
  }
}

/// Pure-Dart geometry, run via [compute] on a background isolate.
///
/// Top-level and self-contained because isolate entry points cannot close over
/// surrounding state.
_ResizedImage _resizeToFeedBounds(Uint8List rawBytes) {
  final decoded = img.decodeImage(rawBytes);
  if (decoded == null) {
    throw const ImageProcessingException(
      'Unsupported or corrupted image format.',
    );
  }

  final geometry = FeedGeometry.forSource(decoded.width, decoded.height);

  img.Image output;
  if (geometry.cropRequired) {
    final scaled = img.copyResize(
      decoded,
      width: geometry.width,
      height: geometry.scaledHeight,
      interpolation: img.Interpolation.cubic,
    );
    // Centre-crop: keeps the middle of the frame, which is where the subject
    // of a portrait photo almost always sits.
    output = img.copyCrop(
      scaled,
      x: 0,
      y: geometry.cropTop,
      width: geometry.width,
      height: geometry.height,
    );
  } else if (geometry.width == decoded.width) {
    // Already within bounds — don't burn cycles resampling it.
    output = decoded;
  } else {
    output = img.copyResize(
      decoded,
      width: geometry.width,
      height: geometry.height,
      interpolation: img.Interpolation.cubic,
    );
  }

  return _ResizedImage(
    bytes: Uint8List.fromList(img.encodeJpg(output, quality: 95)),
    width: output.width,
    height: output.height,
  );
}
