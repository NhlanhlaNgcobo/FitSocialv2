import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../widgets/picture_ratio.dart';
import 'run_card_exporter.dart';

/// Captures the map a runner chose to share as a finished, branded picture on
/// disk, and returns its path — or null if it could not be made.
///
/// The map is drawn once, here, on the runner's phone, then signed the way a
/// saved run card is: the wordmark and the run's numbers on frosted chips. What
/// goes out is that picture, uploaded the way a background photo is, so a feed
/// full of runs shown on the map costs what a feed full of photos does rather
/// than a live map view per card.
///
/// The shape comes from the map itself, which the finish sheet lays out at
/// [kPictureAspectRatio] while the map is on.
///
/// Null is not an error the caller has to handle: the post still records that
/// the map was chosen, and the card falls back to drawing it live.
Future<String?> captureRouteMap(
  BuildContext context,
  GoogleMapController map, {
  String? distanceLabel,
  String? durationLabel,
  String? paceLabel,
}) async {
  // The web map plugin has no snapshot, and there is no file to write to.
  if (kIsWeb) return null;

  try {
    final snapshot = await map.takeSnapshot();
    if (snapshot == null || snapshot.isEmpty || !context.mounted) return null;

    // The route and the pins are already in the snapshot, so the card is
    // given no line of its own — only the picture and the numbers to sign it.
    final branded = await renderRunCardPng(
      context,
      RunCardExport(
        background: MemoryImage(snapshot),
        distanceLabel: distanceLabel,
        durationLabel: durationLabel,
        paceLabel: paceLabel,
      ),
    );

    // Posts are stored as JPEG. A map is mostly flat colour, so it survives
    // the re-encode well and comes out a fraction of the PNG's size.
    final jpeg = await compute(_pngToJpeg, branded);
    if (jpeg == null) return null;

    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/run_map_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(jpeg, flush: true);
    return file.path;
  } catch (error, stackTrace) {
    debugPrint('Route map capture failed: $error\n$stackTrace');
    return null;
  }
}

Uint8List? _pngToJpeg(Uint8List png) {
  final image = img.decodePng(png);
  if (image == null) return null;
  return img.encodeJpg(image, quality: 88);
}
