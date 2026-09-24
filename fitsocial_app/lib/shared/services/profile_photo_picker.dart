import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'instagram_photo_picker.dart';
import 'photo_crop.dart';

/// Picks a profile photo and lets the user frame it inside a circle.
///
/// The crop window is the circle the photo will actually appear in, locked to
/// 1:1 so there is no way to choose a shape that then gets centre-cropped by
/// every avatar on screen. What comes back is already square and upload-ready.
abstract final class ProfilePhotoPicker {
  /// Returns the cropped file's path, or null if the user backed out of the
  /// picker or the crop screen.
  ///
  /// The stored image is at most 1080 square: room for larger displays and
  /// future crops without a re-upload, at a few dozen KB.
  static Future<String?> pick({
    required BuildContext context,
    ImageSource source = ImageSource.gallery,
  }) async {
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null || !context.mounted) return null;
    return InstagramPhotoPicker.crop(
      context: context,
      file: picked,
      shapes: const [CropShape.avatar],
      // Instagram's own wording for this step.
      title: 'Move and scale',
      quality: 85,
    );
  }
}
