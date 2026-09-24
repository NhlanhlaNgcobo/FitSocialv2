import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../widgets/crop_photo_screen.dart';
import 'photo_crop.dart';

/// The device refused to store a cropped photo where the app can keep it.
///
/// In practice this means the phone is out of storage; the message is written
/// for the user, not the developer.
class PhotoStorageException implements Exception {
  const PhotoStorageException(this.cause);

  final FileSystemException cause;

  @override
  String toString() =>
      "Couldn't save the photo on this device. Free up some storage and "
      'try again.';
}

/// Picks a photo and lets the user frame it on FitSocial's own crop screen,
/// 9:16 portrait by default.
///
/// The crop step also does the downscaling and JPEG encoding, so the file that
/// comes back is already upload-ready: at most 1080 wide and 1920 tall,
/// quality 80.
abstract final class InstagramPhotoPicker {
  /// Returns the cropped file's path, or null if the user backed out of either
  /// the picker or the crop screen.
  ///
  /// [otherShapes] offers the three feed shapes beside 9:16. Every upload in
  /// the app passes it; without it the screen is 9:16 only.
  static Future<String?> pickAndCrop({
    required BuildContext context,
    required ImageSource source,
    bool otherShapes = false,
  }) async {
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null || !context.mounted) return null;
    return crop(
      context: context,
      file: picked,
      shapes: otherShapes ? CropShape.all : CropShape.storyOnly,
    );
  }

  /// Opens the crop screen on a photo that is already in hand — one the
  /// picker just returned, or one Android handed back after closing the app
  /// mid-pick — and returns the stored result's path, or null if the user
  /// backed out.
  ///
  /// Every photo the app uploads comes through here, so every one is framed
  /// on the same screen and stored the same way.
  static Future<String?> crop({
    required BuildContext context,
    required XFile file,
    List<CropShape> shapes = CropShape.storyOnly,
    String title = 'Crop photo',
    int quality = 80,
  }) async {
    final bytes = await file.readAsBytes();
    if (!context.mounted) return null;

    final cropped = await CropPhotoScreen.open(
      context,
      bytes,
      shapes: shapes,
      title: title,
      quality: quality,
    );
    if (cropped == null) return null;
    return _store(cropped);
  }

  /// Writes the cropped photo into app storage and returns its path.
  ///
  /// App support storage, not the cache: Android may clear the cache at any
  /// moment — including while the user is still writing their caption or
  /// tagging people — while this is only cleared with the app itself, so the
  /// photo survives until the upload reads it, even across an app restart for
  /// the flows that upload in the background.
  ///
  /// On web there is no file system, so the photo is handed back as a blob URL,
  /// which is what every caller already reads on web.
  static Future<String> _store(Uint8List jpeg) async {
    if (kIsWeb) {
      return XFile.fromData(jpeg, mimeType: 'image/jpeg').path;
    }
    final Directory dir;
    final String target;
    try {
      final support = await getApplicationSupportDirectory();
      dir = Directory('${support.path}/pending_photos');
      await dir.create(recursive: true);
      target = '${dir.path}/photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(target).writeAsBytes(jpeg, flush: true);
    } on FileSystemException catch (error) {
      throw PhotoStorageException(error);
    }
    // Housekeeping only; never lets a failure here cost the photo.
    unawaited(_sweepStale(dir, keep: target));
    return target;
  }

  /// Nothing else deletes stored photos (an upload may be retried), so drop
  /// anything old enough that no compose flow could still be holding it.
  static Future<void> _sweepStale(Directory dir, {required String keep}) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    await for (final entity in dir.list()) {
      if (entity is! File || entity.path == keep) continue;
      try {
        if ((await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
        }
      } catch (_) {
        // Best-effort housekeeping; a stuck file costs kilobytes, not a post.
      }
    }
  }
}
