import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/theme/app_palette.dart';
import '../../features/main/domain/app_models.dart';
import '../widgets/fit_social_logo.dart';
import '../widgets/route_sparkline.dart';
import '../widgets/run_summary_card.dart';

/// Everything the run card needs to draw itself into a file.
///
/// [background] is an [ImageProvider] rather than a path or a URL because the
/// three callers hold three different things — a picked file, a Firebase URL,
/// and in tests a [MemoryImage] — and the card takes a provider anyway.
@immutable
class RunCardExport {
  const RunCardExport({
    this.route = const [],
    this.distanceLabel,
    this.durationLabel,
    this.background,
    this.aspectRatio = 4 / 3,
  });

  final List<RoutePoint> route;
  final String? distanceLabel;
  final String? durationLabel;
  final ImageProvider? background;

  /// Match whatever the user is looking at, so the file crops the photo exactly
  /// the way the preview did.
  final double aspectRatio;

  /// Whether there is anything worth drawing. A run with no line is fine — a
  /// treadmill run is nothing but numbers — but a card with no line, no photo
  /// and no numbers is an empty rectangle.
  bool get hasContent =>
      RouteSparkline.canDraw(route) ||
      background != null ||
      (distanceLabel?.trim().isNotEmpty ?? false) ||
      (durationLabel?.trim().isNotEmpty ?? false);
}

/// A capture that could not be made, carrying the line to show the user.
class RunCardExportException implements Exception {
  const RunCardExportException(this.message);

  /// Written for the toast, not for a log.
  final String message;

  @override
  String toString() => 'RunCardExportException: $message';
}

/// The width every exported card comes out at, on every device.
const int kRunCardExportWidth = 1080;

/// The width the card is laid out at before it is scaled up.
///
/// The card's spacing, type sizes and stroke widths were all tuned against a
/// phone-width card, so it is laid out at phone width and rasterised at 3x
/// rather than laid out at 1080 and rasterised at 1x — same pixels out, but the
/// proportions stay the ones that were designed.
const double _logicalWidth = 360;

/// Only one capture at a time. Two overlapping ones would fight over the image
/// cache entries they are each holding open.
bool _capturing = false;

/// Draws [spec] as a PNG, off screen, at [width] pixels wide.
///
/// Returns the encoded bytes. Throws [RunCardExportException] with a line the
/// caller can show as-is: when there is nothing to draw, when the backdrop
/// photo will not load, or when the engine refuses the capture.
Future<Uint8List> renderRunCardPng(
  BuildContext context,
  RunCardExport spec, {
  int width = kRunCardExportWidth,
}) async {
  if (kIsWeb) {
    throw const RunCardExportException('Saving the card needs the app.');
  }
  if (!spec.hasContent) {
    throw const RunCardExportException("There's nothing on this card yet.");
  }
  if (_capturing) {
    throw const RunCardExportException('Still saving the last one.');
  }

  // Read the ambient tree before the first await: the finish sheet is a modal
  // route and may well be gone by the time the photo has decoded.
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    throw const RunCardExportException("Couldn't draw the card.");
  }
  final theme = Theme.of(context);
  final ground = runCardExportGround(context.palette);
  final media = MediaQuery.of(context);
  final configuration = createLocalImageConfiguration(context);

  _capturing = true;
  final held = <_HeldImage>[];
  OverlayEntry? entry;
  ui.Image? image;
  try {
    // Both images have to be decoded *before* the card is built: an unresolved
    // Image paints nothing on its first frame, and the capture would take a
    // card with a hole where the photo and the wordmark belong.
    final background = spec.background;
    if (background != null) {
      try {
        held.add(await _hold(background, configuration));
      } on Object {
        throw const RunCardExportException(
          "Couldn't load your photo — try again in a moment.",
        );
      }
    }
    try {
      held.add(
        await _hold(const AssetImage(kFitSocialMarkAsset), configuration),
      );
    } on RunCardExportException {
      rethrow;
    } on Object {
      // The wordmark is usually already cached by the app bar. If it somehow
      // is not, a card signed with nothing is still a card.
    }

    final size = Size(_logicalWidth, _logicalWidth / spec.aspectRatio);
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
            // The file is a fixed-size artifact, so it must not reflow with the
            // reader's text settings — the card's numbers are single-line and
            // would clip. devicePixelRatio is deliberately left alone: it is
            // part of AssetImage's cache key, and changing it here would miss
            // the wordmark that was just held open above.
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
                      child: SizedBox.fromSize(
                        size: size,
                          child: RunSummaryCard(
                          route: spec.route,
                          distanceLabel: spec.distanceLabel,
                          durationLabel: spec.durationLabel,
                          background: spec.background,
                          aspectRatio: spec.aspectRatio,
                          forExport: true,
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
      throw const RunCardExportException("Couldn't draw the card.");
    }
    // No `debugNeedsPaint` probe here. It reads a `late` field that is only
    // assigned inside an assert, so in a release build — where asserts are
    // stripped — merely reading it throws LateInitializationError, and this
    // whole export fails every time. The two frames above are what actually
    // guarantees the layer: the first builds the entry, the second paints it.

    final captured = image = await boundary.toImage(
      pixelRatio: width / size.width,
    );
    final data = await captured.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw const RunCardExportException("Couldn't draw the card.");
    }
    return data.buffer.asUint8List();
  } on RunCardExportException {
    rethrow;
  } catch (error, stack) {
    // Reported rather than rethrown raw: the user gets a line they can read,
    // and the real failure still reaches Crashlytics.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'fitsocial',
        context: ErrorDescription('drawing the run card to a file'),
      ),
    );
    throw const RunCardExportException("Couldn't draw the card.");
  } finally {
    image?.dispose();
    entry?.remove();
    for (final image in held) {
      image.release();
    }
    _capturing = false;
  }
}

/// A decoded image, kept in the cache until [release].
class _HeldImage {
  _HeldImage(this.stream, this.listener);

  final ImageStream stream;
  final ImageStreamListener listener;

  void release() => stream.removeListener(listener);
}

/// Decodes [provider] and holds the listener open, so the cache entry cannot be
/// evicted between here and the capture frame.
///
/// Deliberately not [precacheImage], which swallows failures — a photo that
/// quietly failed would export as the grey fallback, which looks like a bug in
/// the card rather than a failure to save.
Future<_HeldImage> _hold(
  ImageProvider provider,
  ImageConfiguration configuration,
) async {
  final stream = provider.resolve(configuration);
  final ready = Completer<void>();
  final listener = ImageStreamListener(
    (_, __) {
      if (!ready.isCompleted) ready.complete();
    },
    onError: (error, stack) {
      if (!ready.isCompleted) ready.completeError(error, stack);
    },
  );
  final held = _HeldImage(stream, listener);
  stream.addListener(listener);
  try {
    await ready.future;
    return held;
  } on Object {
    held.release();
    rethrow;
  }
}
