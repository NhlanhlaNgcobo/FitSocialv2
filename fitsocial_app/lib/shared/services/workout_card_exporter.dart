import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/theme/app_palette.dart';
import '../widgets/fit_social_logo.dart';
import '../widgets/picture_ratio.dart';
import '../widgets/run_summary_card.dart' show runCardExportGround;
import '../widgets/workout_summary_card.dart';
import 'held_image.dart';

/// Everything the workout card needs to draw itself into a file.
///
/// [background] is an [ImageProvider] for the same reason `RunCardExport`'s
/// is: the log screen holds a picked file and the feed holds a URL, and the
/// card is about to be rasterised off-screen from whichever one it is given.
@immutable
class WorkoutCardExport {
  const WorkoutCardExport({
    required this.activity,
    this.workoutData,
    this.background,
  });

  /// Fallback title when the log never carried one.
  final String activity;

  /// The post's `workoutData` map — the same document `WorkoutSummaryCard`
  /// reads in the feed, so the file is the card and not a re-drawing of it.
  final Map<String, dynamic>? workoutData;
  final ImageProvider? background;

  /// Whether there is anything worth drawing. Unlike a meal, a workout needs
  /// no photo — the ruled sheet is the card — but a sheet with no exercises,
  /// no photo and no numbers is just a title on a rectangle.
  bool get hasContent {
    if (background != null) return true;
    final data = workoutData;
    if (data == null) return false;
    final exercises = data['exercises'];
    if (exercises is List && exercises.isNotEmpty) return true;
    bool present(Object? value) =>
        value != null && value.toString().trim().isNotEmpty;
    return present(data['duration']) || present(data['calories']);
  }
}

/// A capture that could not be made, carrying the line to show the user.
class WorkoutCardExportException implements Exception {
  const WorkoutCardExportException(this.message);

  /// Written for the toast, not for a log.
  final String message;

  @override
  String toString() => 'WorkoutCardExportException: $message';
}

/// The width every exported card comes out at, on every device.
const int kWorkoutCardExportWidth = 1080;

/// The width the card is laid out at before it is scaled up.
///
/// Same reasoning as the run card: the sheet's rules, type sizes and column
/// widths were tuned against a phone-width card, so it is laid out at phone
/// width and rasterised at 3x rather than laid out at 1080 and rasterised at
/// 1x — same pixels out, but the proportions stay the ones that were designed.
const double _logicalWidth = 360;

/// Only one capture at a time. Two overlapping ones would fight over the image
/// cache entries they are each holding open.
bool _capturing = false;

/// Draws [spec] as a PNG, off screen, at [width] pixels wide.
///
/// The height is whatever the sheet needs: a workout card is not a fixed
/// shape the way a run or meal card is. With a photo it is at least the
/// photo's own ratio and grows past it for a long session, exactly as it does
/// in the feed.
///
/// Returns the encoded bytes. Throws [WorkoutCardExportException] with a line
/// the caller can show as-is: when there is nothing to draw, when the backdrop
/// photo will not load, or when the engine refuses the capture.
Future<Uint8List> renderWorkoutCardPng(
  BuildContext context,
  WorkoutCardExport spec, {
  int width = kWorkoutCardExportWidth,
}) async {
  if (kIsWeb) {
    throw const WorkoutCardExportException('Saving the card needs the app.');
  }
  if (!spec.hasContent) {
    throw const WorkoutCardExportException("There's nothing on this card yet.");
  }
  if (_capturing) {
    throw const WorkoutCardExportException('Still saving the last one.');
  }

  // Read the ambient tree before the first await: the screen this was tapped
  // on may be gone by the time the photo has decoded.
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    throw const WorkoutCardExportException("Couldn't draw the card.");
  }
  final theme = Theme.of(context);
  final ground = runCardExportGround(context.palette);
  final media = MediaQuery.of(context);
  final configuration = createLocalImageConfiguration(context);

  _capturing = true;
  final held = <HeldImage>[];
  OverlayEntry? entry;
  ui.Image? image;
  try {
    // Both images have to be decoded *before* the card is built: an unresolved
    // Image paints nothing on its first frame, and the capture would take a
    // card with a hole where the photo and the wordmark belong. Decoding the
    // background here also measures it, and the ratio is pinned onto the card
    // so it does not have to resolve the same photo a second time inside the
    // overlay — which it could not do in the two frames it gets anyway.
    final background = spec.background;
    double? ratio;
    if (background != null) {
      try {
        final backgroundHeld = await holdImage(background, configuration);
        held.add(backgroundHeld);
        final decoded = backgroundHeld.image;
        // Clamped to the same range the feed uses, so the file has the shape
        // the post does.
        ratio = decoded == null || decoded.height == 0
            ? kPictureAspectRatio
            : (decoded.width / decoded.height)
                .clamp(kPictureAspectRatio, kWidestPictureRatio);
      } on Object {
        throw const WorkoutCardExportException(
          "Couldn't load your photo — try again in a moment.",
        );
      }
    }
    try {
      held.add(
        await holdImage(const AssetImage(kFitSocialMarkAsset), configuration),
      );
    } on WorkoutCardExportException {
      rethrow;
    } on Object {
      // The wordmark is usually already cached by the app bar. If it somehow
      // is not, a card signed with nothing is still a card.
    }

    final boundaryKey = GlobalKey();

    entry = OverlayEntry(
      builder: (_) => Positioned(
        // Off the visible surface but still painted. Offstage and Opacity(0)
        // both skip painting entirely, which leaves the boundary with no layer
        // to rasterise.
        left: -_logicalWidth - 64,
        top: 0,
        child: IgnorePointer(
          child: MediaQuery(
            // The file is a fixed-size artifact, so it must not reflow with the
            // reader's text settings. devicePixelRatio is deliberately left
            // alone: it is part of AssetImage's cache key, and changing it
            // here would miss the wordmark that was just held open above.
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
                    // otherwise be transparent. Instagram flattens alpha to
                    // black, which would put black notches on a light card.
                    child: ColoredBox(
                      color: ground,
                      // Width only. The sheet takes the height its rows need,
                      // and a Positioned child with no bottom is free to.
                      child: SizedBox(
                        width: _logicalWidth,
                        child: WorkoutSummaryCard(
                          workoutData: spec.workoutData,
                          activity: spec.activity,
                          backgroundImage: spec.background,
                          aspectRatio: ratio,
                          forExport: true,
                          // Edge to edge: the file is the card, with no page
                          // around it to be inset from.
                          margin: EdgeInsets.zero,
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
      throw const WorkoutCardExportException("Couldn't draw the card.");
    }
    // No `debugNeedsPaint` probe, for the reason given in the run exporter:
    // it throws in a release build. The two frames above are the guarantee.

    final captured = image = await boundary.toImage(
      pixelRatio: width / _logicalWidth,
    );
    final data = await captured.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw const WorkoutCardExportException("Couldn't draw the card.");
    }
    return data.buffer.asUint8List();
  } on WorkoutCardExportException {
    rethrow;
  } catch (error, stack) {
    // Reported rather than rethrown raw: the user gets a line they can read,
    // and the real failure still reaches Crashlytics.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'fitsocial',
        context: ErrorDescription('drawing the workout card to a file'),
      ),
    );
    throw const WorkoutCardExportException("Couldn't draw the card.");
  } finally {
    image?.dispose();
    entry?.remove();
    for (final image in held) {
      image.release();
    }
    _capturing = false;
  }
}
