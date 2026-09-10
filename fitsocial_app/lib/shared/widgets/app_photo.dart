import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

/// The one way to load a remote photo.
///
/// Everything remote goes through here for two reasons. The first is the disk
/// cache: Flutter's own image cache is memory-only and dies with the process,
/// so a plain `Image.network` re-downloads every photo on every cold start.
///
/// The second is identity. [precacheImage] warms whatever key the provider it
/// is handed hashes to, and a widget built from a *differently constructed*
/// provider reads a different key — the warm copy is never found and the photo
/// is fetched twice. One constructor keeps the warmed image and the drawn one
/// the same entry.
ImageProvider appPhoto(String url) => CachedNetworkImageProvider(url);

/// [appPhoto] decoded no larger than the slot it is drawn into.
///
/// Feed photos are stored at 1080px, which decodes to roughly 5.6MB of pixels
/// — about seventeen of them fill Flutter's whole decoded-image budget. An
/// avatar or a grid tile has no use for that resolution, and paying it evicts
/// the photos actually on screen.
///
/// [logicalWidth] is the width in Flutter's logical pixels; the device's ratio
/// is applied here. Never upscales, so a photo smaller than its slot is left
/// alone.
ImageProvider appPhotoSized(
  BuildContext context,
  String url,
  double logicalWidth,
) {
  // Callers pass a layout constraint, which is unbounded often enough to be
  // worth handling here rather than at each one. There is no budget to compute
  // from an infinite slot, so fall back to the photo at its stored size.
  if (!logicalWidth.isFinite || logicalWidth <= 0) return appPhoto(url);

  return ResizeImage(
    CachedNetworkImageProvider(url),
    width: (logicalWidth * MediaQuery.devicePixelRatioOf(context)).round(),
    allowUpscaling: false,
  );
}
