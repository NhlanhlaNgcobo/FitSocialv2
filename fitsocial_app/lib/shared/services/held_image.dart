import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// A decoded image, kept in the cache until [release].
///
/// Shared by the run, meal and workout card exporters, which all have the same
/// problem: the card is about to be built off-screen and captured on its
/// second frame, and an [Image] whose provider has not resolved by then paints
/// nothing. Holding a listener open is what stops the cache evicting the
/// decoded frame in between.
class HeldImage {
  HeldImage(this.stream, this.listener, {this.image});

  final ImageStream stream;
  final ImageStreamListener listener;

  /// The decoded frame, so a caller can measure it without resolving the same
  /// provider a second time. Null only if the stream completed with no frame,
  /// which [holdImage] would already have thrown on.
  final ui.Image? image;

  void release() => stream.removeListener(listener);
}

/// Decodes [provider] and holds the listener open, so the cache entry cannot
/// be evicted between here and the capture frame.
///
/// Deliberately not [precacheImage], which swallows failures — a photo that
/// quietly failed would export as the flat fallback, which looks like a bug in
/// the card rather than a failure to save.
Future<HeldImage> holdImage(
  ImageProvider provider,
  ImageConfiguration configuration,
) async {
  final stream = provider.resolve(configuration);
  final ready = Completer<void>();
  ui.Image? decoded;
  final listener = ImageStreamListener(
    (info, _) {
      decoded = info.image;
      if (!ready.isCompleted) ready.complete();
    },
    onError: (error, stack) {
      if (!ready.isCompleted) ready.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  try {
    await ready.future;
    return HeldImage(stream, listener, image: decoded);
  } on Object {
    stream.removeListener(listener);
    rethrow;
  }
}
