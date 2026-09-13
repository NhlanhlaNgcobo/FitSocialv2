import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../widgets/fit_social_logo.dart';
import '../widgets/meal_summary_card.dart';
import 'held_image.dart';

/// Everything the meal card needs to draw itself into a file.
///
/// [background] is an [ImageProvider], already resolved through `appPhoto` by
/// the caller — the same reason `RunCardExport.background` takes a provider
/// rather than a URL: the card is about to be rasterised off-screen, and
/// resolving the same photo a second time inside that overlay would race the
/// capture.
@immutable
class MealCardExport {
  const MealCardExport({
    required this.activity,
    this.mealData,
    this.background,
  });

  final String activity;
  final Map<String, dynamic>? mealData;
  final ImageProvider? background;

  /// A meal is always a photo of food; there's nothing worth a file without
  /// one.
  bool get hasContent => background != null;
}

/// A capture that could not be made, carrying the line to show the user.
class MealCardExportException implements Exception {
  const MealCardExportException(this.message);

  /// Written for the toast, not for a log.
  final String message;

  @override
  String toString() => 'MealCardExportException: $message';
}

/// The width every exported card comes out at, on every device.
const int kMealCardExportWidth = 1080;

/// The width the card is laid out at before it is scaled up.
///
/// Mirrors the run card's own logical width: the card's spacing and type
/// sizes were tuned against a phone-width card, so it is laid out at phone
/// width and rasterised at 3x rather than laid out at 1080 and rasterised at
/// 1x — same pixels out, but the proportions stay the ones that were designed.
const double _logicalWidth = 360;

/// Only one capture at a time. Two overlapping ones would fight over the image
/// cache entries they are each holding open.
bool _capturing = false;

/// Draws [spec] as a PNG, off screen, at [width] pixels wide.
///
/// Returns the encoded bytes. Throws [MealCardExportException] with a line the
/// caller can show as-is: when there is nothing to draw, when the photo will
/// not load, or when the engine refuses the capture.
Future<Uint8List> renderMealCardPng(
  BuildContext context,
  MealCardExport spec, {
  int width = kMealCardExportWidth,
}) async {
  if (kIsWeb) {
    throw const MealCardExportException('Saving the card needs the app.');
  }
  if (!spec.hasContent) {
    throw const MealCardExportException("There's nothing on this card yet.");
  }
  if (_capturing) {
    throw const MealCardExportException('Still saving the last one.');
  }

  // Read the ambient tree before the first await: the review screen could in
  // principle be gone by the time the photo has decoded.
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    throw const MealCardExportException("Couldn't draw the card.");
  }
  final theme = Theme.of(context);
  final media = MediaQuery.of(context);
  final configuration = createLocalImageConfiguration(context);
  // The card's own dark fallback tint. Unlike the run card, a meal card never
  // looks through to the app's theme — it always shows a photo or this.
  const ground = Color(0xFF1E1E1E);

  _capturing = true;
  final held = <HeldImage>[];
  OverlayEntry? entry;
  ui.Image? image;
  try {
    // The photo has to be decoded *before* the card is built: an unresolved
    // Image paints nothing on its first frame, and the capture would take a
    // card with a hole where the photo belongs. Decoding it here also
    // measures it — the ratio below is the photo's own, never a forced crop —
    // and it is what gets handed to the card so it does not have to resolve
    // the same image a second time inside the overlay.
    final background = spec.background;
    var ratio = 1.0;
    if (background != null) {
      try {
        final backgroundHeld = await holdImage(background, configuration);
        held.add(backgroundHeld);
        final decoded = backgroundHeld.image;
        if (decoded != null && decoded.height != 0) {
          ratio = (decoded.width / decoded.height).clamp(0.8, 1.91);
        }
      } on Object {
        throw const MealCardExportException(
          "Couldn't load your photo — try again in a moment.",
        );
      }
    }
    try {
      held.add(
        await holdImage(const AssetImage(kFitSocialMarkAsset), configuration),
      );
    } on MealCardExportException {
      rethrow;
    } on Object {
      // The wordmark is usually already cached by the app bar. If it somehow
      // is not, a card signed with nothing is still a card.
    }

    final size = Size(_logicalWidth, _logicalWidth / ratio);
    final boundaryKey = GlobalKey();

    entry = OverlayEntry(
      builder: (_) => Positioned(
        // Off the visible surface but still painted. Offstage and Opacity(0)
        // both skip painting entirely, which leaves the boundary with no layer
        // to rasterise.
        left: -size.width - 64,
        top: 0,
        child: IgnorePointer(
          child: MediaQuery(
            // The file is a fixed-size artifact, so it must not reflow with
            // the reader's text settings. devicePixelRatio is deliberately
            // left alone: it is part of AssetImage's cache key, and changing
            // it here would miss the wordmark that was just held open above.
            data: media.copyWith(
              textScaler: TextScaler.noScaling,
              boldText: false,
            ),
            child: Theme(
              data: theme,
              child: Directionality(
                textDirection: TextDirection.ltr,
                // Not for the fill — for the DefaultTextStyle. Without it the
                // card's type falls back to a different family.
                child: Material(
                  type: MaterialType.transparency,
                  child: RepaintBoundary(
                    key: boundaryKey,
                    // Behind the whole canvas, not just the card: the card's
                    // corners are rounded, and the wedges outside them would
                    // otherwise be transparent.
                    child: ColoredBox(
                      color: ground,
                      child: SizedBox.fromSize(
                        size: size,
                        child: MealSummaryCard(
                          activity: spec.activity,
                          mealData: spec.mealData,
                          backgroundImage: spec.background,
                          aspectRatio: ratio,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);

    // One frame to build it, a second to be sure it has been laid out and
    // painted.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;

    final boundary = boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) {
      throw const MealCardExportException("Couldn't draw the card.");
    }

    final captured = image = await boundary.toImage(
      pixelRatio: width / size.width,
    );
    final data = await captured.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw const MealCardExportException("Couldn't draw the card.");
    }
    return data.buffer.asUint8List();
  } on MealCardExportException {
    rethrow;
  } catch (error, stack) {
    // Reported rather than rethrown raw: the user gets a line they can read,
    // and the real failure still reaches Crashlytics.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'fitsocial',
        context: ErrorDescription('drawing the meal card to a file'),
      ),
    );
    throw const MealCardExportException("Couldn't draw the card.");
  } finally {
    image?.dispose();
    entry?.remove();
    for (final image in held) {
      image.release();
    }
    _capturing = false;
  }
}
