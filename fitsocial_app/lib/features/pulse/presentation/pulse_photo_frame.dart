import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

/// The provider a photo picked on this device is drawn from.
///
/// On the web the picker hands back a blob URL rather than a file path, so the
/// two platforms need different providers for the same photo.
ImageProvider pulseLocalPhoto(String path) {
  if (kIsWeb) return NetworkImage(path);
  return FileImage(File(path));
}

/// A photo shown whole, on a blurred copy of itself.
///
/// A Pulse plays full-screen and portrait, but photos arrive in every shape a
/// camera can produce. Cropping them to fit throws away whatever the person
/// framed outside 9:16 — so the photo is drawn [BoxFit.contain], at its own
/// ratio, and the leftover screen is filled with a blurred, dimmed copy of the
/// same photo instead of a black bar. A photo already the shape of the screen
/// covers it completely and the backdrop never shows.
class PulsePhotoFrame extends StatelessWidget {
  const PulsePhotoFrame({
    required this.image,
    this.errorBuilder,
    this.loadingBuilder,
    super.key,
  });

  final ImageProvider image;

  /// Drawn in place of the photo when it fails to decode. The backdrop is
  /// dropped too, so a broken photo shows one message rather than a blurred
  /// wash with a message on top.
  final ImageErrorWidgetBuilder? errorBuilder;

  final ImageLoadingBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.mediaBackdrop,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PulseBlurredBackdrop(image: image),
          Image(
            image: image,
            fit: BoxFit.contain,
            errorBuilder: errorBuilder,
            loadingBuilder: loadingBuilder,
          ),
        ],
      ),
    );
  }
}

/// A blurred, dimmed copy of [image], stretched to fill whatever it is given.
///
/// What a Pulse falls back to instead of a black bar: the photo behind the
/// photo, or the album art behind a music sticker.
class PulseBlurredBackdrop extends StatelessWidget {
  const PulseBlurredBackdrop({required this.image, super.key});

  final ImageProvider image;

  /// Blurring a full-resolution image across the whole screen is a real cost
  /// for a layer nobody is meant to read. Decoding the copy tiny and letting
  /// it stretch gets the same wash for a fraction of the work.
  static const int _width = 64;
  static const double _sigma = 24;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: _sigma,
            sigmaY: _sigma,
            tileMode: TileMode.clamp,
          ),
          child: Image(
            image: ResizeImage(image, width: _width, allowUpscaling: false),
            fit: BoxFit.cover,
            // Scenery: it appears when it is ready and is simply absent if the
            // decode fails, since whatever sits in front reports that for both.
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
        // Holds the blur back from competing with what is drawn on it.
        const ColoredBox(color: Color(0x59000000)),
      ],
    );
  }
}
