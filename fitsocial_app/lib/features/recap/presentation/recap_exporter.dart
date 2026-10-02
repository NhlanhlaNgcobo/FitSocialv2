import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/services/held_image.dart';
import '../../../shared/widgets/fit_social_logo.dart';
import '../../../shared/widgets/share_sheet.dart' show shareOriginOf;
import '../domain/recap.dart';
import 'recap_card.dart';

/// A recap that could not be drawn, with the line to show the user.
class RecapExportException implements Exception {
  const RecapExportException(this.message);

  final String message;

  @override
  String toString() => 'RecapExportException: $message';
}

/// The width every recap file comes out at: 1080 x 1920.
const int kRecapExportWidth = 1080;

bool _capturing = false;

/// Draws [data] as [options] allow, off screen, as a PNG.
///
/// The same technique as the workout card exporter: the wordmark is decoded
/// before the card is built, the card is painted in an overlay just off the
/// visible surface, and two frames later the boundary is rasterised.
Future<Uint8List> renderRecapPng(
  BuildContext context,
  RecapCardData data,
  RecapOptions options,
) async {
  if (kIsWeb) throw const RecapExportException('Sharing needs the app.');
  if (_capturing) {
    throw const RecapExportException('Still making the last one.');
  }

  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    throw const RecapExportException("Couldn't draw the card.");
  }
  final theme = Theme.of(context);
  final media = MediaQuery.of(context);
  final configuration = createLocalImageConfiguration(context);

  _capturing = true;
  final held = <HeldImage>[];
  OverlayEntry? entry;
  ui.Image? image;
  try {
    try {
      held.add(
        await holdImage(const AssetImage(kFitSocialMarkAsset), configuration),
      );
    } on Object {
      // A card without the mark is still a card.
    }

    final boundaryKey = GlobalKey();
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -kRecapCardWidth - 64,
        top: 0,
        child: IgnorePointer(
          child: MediaQuery(
            data: media.copyWith(
              textScaler: TextScaler.noScaling,
              boldText: false,
            ),
            child: Theme(
              data: theme,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Material(
                  type: MaterialType.transparency,
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: RecapCard(data: data, options: options),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);

    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;

    final boundary = boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) {
      throw const RecapExportException("Couldn't draw the card.");
    }
    final captured = image = await boundary.toImage(
      pixelRatio: kRecapExportWidth / kRecapCardWidth,
    );
    final bytes = await captured.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw const RecapExportException("Couldn't draw the card.");
    }
    return bytes.buffer.asUint8List();
  } on RecapExportException {
    rethrow;
  } catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'fitsocial',
        context: ErrorDescription('drawing a recap card to a file'),
      ),
    );
    throw const RecapExportException("Couldn't draw the card.");
  } finally {
    image?.dispose();
    entry?.remove();
    for (final h in held) {
      h.release();
    }
    _capturing = false;
  }
}

/// Hands [bytes] to the system share sheet as a PNG. Returns the share result,
/// whose `raw` names the app picked where the platform says.
Future<ShareResult> shareRecapFile(
  BuildContext context,
  Uint8List bytes,
  RecapKind kind,
) async {
  final origin = shareOriginOf(context);
  final directory = await getTemporaryDirectory();
  final name =
      'fitsocial-${kind.key}-recap-${DateTime.now().millisecondsSinceEpoch}';
  final file = File('${directory.path}/$name.png');
  await file.writeAsBytes(bytes, flush: true);
  return SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'image/png', name: '$name.png')],
      subject: 'My ${kind == RecapKind.week ? 'week' : kind.key} on FitSocial',
      sharePositionOrigin: origin,
    ),
  );
}
