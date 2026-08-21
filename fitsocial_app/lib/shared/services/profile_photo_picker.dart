import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_colors.dart';

/// Picks a profile photo and lets the user frame it inside a circle.
///
/// Mirrors how Instagram handles a profile picture: the crop window is the
/// circle the photo will actually appear in, locked to 1:1 so there is no way
/// to choose a shape that then gets centre-cropped by every avatar on screen.
/// What comes back is already square and upload-ready.
abstract final class ProfilePhotoPicker {
  /// Square edge of the stored image. Instagram serves profile photos at
  /// 320px; storing 1080 leaves room for larger displays and future crops
  /// without a re-upload, at a few dozen KB.
  static const int _edge = 1080;

  static const int _quality = 85;

  static const CropAspectRatio _square = CropAspectRatio(ratioX: 1, ratioY: 1);

  /// Returns the cropped file's path, or null if the user backed out of the
  /// picker or the cropper.
  ///
  /// [context] is required by the web cropper, which renders a Flutter dialog
  /// rather than a native screen.
  static Future<String?> pick({
    required BuildContext context,
    ImageSource source = ImageSource.gallery,
  }) async {
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return null;
    if (!context.mounted) return null;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: _square,
      maxWidth: _edge,
      maxHeight: _edge,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: _quality,
      uiSettings: [
        AndroidUiSettings(
          // Instagram's own wording for this step.
          toolbarTitle: 'Move and scale',
          toolbarColor: AppColors.mediaBackdrop,
          toolbarWidgetColor: AppColors.onMedia,
          backgroundColor: AppColors.mediaBackdrop,
          activeControlsWidgetColor: AppColors.orangeBright,
          cropFrameColor: AppColors.orangeBright,
          cropGridColor: AppColors.cropGrid,
          statusBarLight: false,
          navBarLight: false,
          // The crop window is drawn as the circle the photo ends up in, so
          // what the user frames is exactly what everyone sees.
          cropStyle: CropStyle.circle,
          lockAspectRatio: true,
          // A rule-of-thirds grid over a circular mask reads as clutter, and
          // the ratio tabs are pointless when the ratio is fixed.
          showCropGrid: false,
          hideBottomControls: true,
          initAspectRatio: CropAspectRatioPreset.square,
          aspectRatioPresets: const [CropAspectRatioPreset.square],
        ),
        IOSUiSettings(
          title: 'Move and scale',
          cropStyle: CropStyle.circle,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
          aspectRatioPresets: const [CropAspectRatioPreset.square],
        ),
        if (kIsWeb)
          WebUiSettings(
            context: context,
            presentStyle: WebPresentStyle.dialog,
          ),
      ],
    );

    return cropped?.path;
  }
}
