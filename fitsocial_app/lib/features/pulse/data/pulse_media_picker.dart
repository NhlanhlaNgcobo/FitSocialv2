import 'package:image_picker/image_picker.dart';

import '../domain/pulse_models.dart';

/// Picks and prepares media for a Pulse.
///
/// Photos keep the shape they were taken in. A Pulse plays full-screen and
/// portrait, but forcing every photo into 9:16 cuts the picture down to
/// whatever happens to sit in the middle of it — so nothing is cropped here,
/// and the viewer fills the leftover screen with a blurred copy of the photo
/// instead.
///
/// Only the resolution is capped: the longest side comes down to 1920px and
/// the file is re-encoded, so what leaves the phone is no larger than it can
/// ever be shown at.
abstract final class PulseMediaPicker {
  static const double _maxSide = 1920;
  static const int _quality = 82;

  /// Returns the prepared photo's path, or null if the user backed out of the
  /// picker.
  static Future<String?> pickPhoto({required ImageSource source}) async {
    // image_picker keeps the aspect ratio when it applies these: they bound a
    // box the photo is fitted into, they are not a target shape. A photo
    // already inside the box is left untouched.
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: _maxSide,
      maxHeight: _maxSide,
      imageQuality: _quality,
    );
    return picked?.path;
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
