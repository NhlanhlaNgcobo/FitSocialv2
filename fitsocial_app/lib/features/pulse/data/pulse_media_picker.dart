import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../domain/pulse_models.dart';

/// The single shape a Pulse can be: 9:16, the full-screen portrait every
/// story format on every platform uses.
class _PulseCropRatio implements CropAspectRatioPresetData {
  const _PulseCropRatio();

  @override
  String get name => '9:16';

  @override
  (int, int)? get data => (9, 16);
}

/// Picks and prepares media for a Pulse.
///
/// Photos are cropped to 9:16 and re-encoded on the device, so what leaves the
/// phone is already the size it will be shown at — 1080x1920, the same spec
/// Instagram uses for stories.
abstract final class PulseMediaPicker {
  static const int _maxWidth = 1080;
  static const int _maxHeight = 1920;
  static const int _quality = 82;

  /// 9:16 as a number, for laying out the preview canvas.
  static const double aspectRatio = 9 / 16;

  /// Returns the prepared photo's path, or null if the user backed out of
  /// either the picker or the cropper.
  static Future<String?> pickPhoto({
    required BuildContext context,
    required ImageSource source,
  }) async {
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return null;
    if (!context.mounted) return null;

    const preset = _PulseCropRatio();
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      maxWidth: _maxWidth,
      maxHeight: _maxHeight,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: _quality,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Frame your Pulse',
          toolbarColor: AppColors.mediaBackdrop,
          toolbarWidgetColor: AppColors.onMedia,
          backgroundColor: AppColors.mediaBackdrop,
          activeControlsWidgetColor: AppColors.orangeBright,
          cropFrameColor: AppColors.orangeBright,
          cropGridColor: AppColors.cropGrid,
          statusBarLight: false,
          navBarLight: false,
          initAspectRatio: preset,
          // Locked: a Pulse plays full-screen, so any other shape would be
          // letterboxed or cropped by the player anyway.
          lockAspectRatio: true,
          hideBottomControls: true,
          aspectRatioPresets: const [preset],
        ),
        IOSUiSettings(
          title: 'Frame your Pulse',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
          aspectRatioPresets: const [preset],
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

  /// Returns the picked video's path, or null if the user backed out.
  ///
  /// [maxDuration] caps recording when the camera is the source. A clip chosen
  /// from the gallery is not trimmed by the picker, so the composer measures
  /// it afterwards and rejects anything over the limit.
  static Future<String?> pickVideo({required ImageSource source}) async {
    final picked = await ImagePicker().pickVideo(
      source: source,
      maxDuration: PulseTiming.maxVideoDuration,
    );
    return picked?.path;
  }
}
