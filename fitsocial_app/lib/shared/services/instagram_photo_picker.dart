import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme/app_colors.dart';

/// Instagram's three supported feed-photo shapes.
///
/// Instagram accepts feed photos only between 1.91:1 (landscape) and 4:5
/// (portrait); anything outside that range gets cropped on their side. Offering
/// exactly these presets means what the user frames is what everyone sees.
class InstagramCropRatio implements CropAspectRatioPresetData {
  const InstagramCropRatio._(this.name, this.data);

  @override
  final String name;

  @override
  final (int, int)? data;

  /// 1080x1350 — the default, and the shape that claims the most feed space.
  static const portrait = InstagramCropRatio._('4:5', (4, 5));

  /// 1080x1080.
  static const square = InstagramCropRatio._('1:1', (1, 1));

  /// 1080x566. Expressed as 191:100 because the preset takes integers.
  static const landscape = InstagramCropRatio._('1.91:1', (191, 100));

  /// Order matters — it's the order of the tabs in the crop UI.
  static const all = <CropAspectRatioPresetData>[portrait, square, landscape];
}

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

/// Picks a photo and lets the user frame it to an Instagram feed ratio.
///
/// The crop step also does the downscaling and JPEG encoding, so the file that
/// comes back is already upload-ready at Instagram's spec: 1080px wide, quality
/// 80, never taller than 4:5.
abstract final class InstagramPhotoPicker {
  /// Instagram's standard feed width.
  static const int _maxWidth = 1080;

  /// Tallest legal feed image (4:5 at [_maxWidth]).
  static const int _maxHeight = 1350;

  /// Matches InstagramImageSpec.jpegQuality.
  static const int _quality = 80;

  /// Returns the cropped file's path, or null if the user backed out of either
  /// the picker or the cropper.
  ///
  /// [context] is required by the web cropper implementation, which renders a
  /// Flutter dialog rather than a native screen.
  static Future<String?> pickAndCrop({
    required BuildContext context,
    required ImageSource source,
  }) async {
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return null;
    if (!context.mounted) return null;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      // Bounds and encoding applied by the platform's native cropper, which
      // keeps this working identically on Android, iOS and web.
      maxWidth: _maxWidth,
      maxHeight: _maxHeight,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: _quality,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop photo',
          toolbarColor: AppColors.mediaBackdrop,
          toolbarWidgetColor: AppColors.onMedia,
          backgroundColor: AppColors.mediaBackdrop,
          activeControlsWidgetColor: AppColors.orangeBright,
          cropFrameColor: AppColors.orangeBright,
          cropGridColor: AppColors.cropGrid,
          statusBarLight: false,
          navBarLight: false,
          initAspectRatio: InstagramCropRatio.portrait,
          // Users pick a shape from the presets; free-form would let them
          // produce a ratio Instagram-style feeds can't display consistently.
          lockAspectRatio: true,
          hideBottomControls: false,
          aspectRatioPresets: InstagramCropRatio.all,
        ),
        IOSUiSettings(
          title: 'Crop photo',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: false,
          aspectRatioPresets: InstagramCropRatio.all,
        ),
        if (kIsWeb)
          WebUiSettings(
            context: context,
            presentStyle: WebPresentStyle.dialog,
          ),
      ],
    );

    if (cropped == null) return null;
    return _moveOutOfCache(cropped.path);
  }

  /// Moves a freshly cropped file from the platform cache into app storage.
  ///
  /// The cropper writes into the cache directory, which Android may clear at
  /// any moment — including while the user is still writing their caption or
  /// tagging people. App support storage is only cleared with the app itself,
  /// so a photo moved there survives until the upload reads it, even across an
  /// app restart for the flows that upload in the background.
  ///
  /// On web the path is a blob URL, not a file, so it is returned untouched.
  /// A cache path is never handed back: if the photo cannot be secured the
  /// caller gets a [PhotoStorageException] now, not a vanished file later.
  static Future<String> _moveOutOfCache(String croppedPath) async {
    if (kIsWeb) return croppedPath;
    final Directory dir;
    final String target;
    try {
      final support = await getApplicationSupportDirectory();
      dir = Directory('${support.path}/pending_photos');
      await dir.create(recursive: true);
      target = '${dir.path}/photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final source = File(croppedPath);
      try {
        await source.rename(target);
      } on FileSystemException {
        // rename fails across filesystems; fall back to copy + delete.
        await source.copy(target);
        await source.delete();
      }
    } on FileSystemException catch (error) {
      throw PhotoStorageException(error);
    }
    // Housekeeping only; never lets a failure here cost the photo.
    unawaited(_sweepStale(dir, keep: target));
    return target;
  }

  /// Nothing else deletes moved photos (an upload may be retried), so drop
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
