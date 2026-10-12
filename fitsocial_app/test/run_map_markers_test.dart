import 'dart:io';
import 'dart:typed_data';

import 'package:fitsocial_app/shared/widgets/run_map_markers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  group('run map markers', () {
    testWidgets('each pin is a round bitmap sized in logical pixels',
        (tester) async {
      await tester.runAsync(() async {
        final sizes = <RunMapMarker, double>{};
        for (final marker in RunMapMarker.values) {
          final icon = await runMapMarkerIcon(marker, 3) as BytesMapBitmap;
          expect(icon.width, icon.height);
          sizes[marker] = icon.width!;

          final dump = Platform.environment['RUN_MAP_MARKER_DUMP'];
          if (dump != null) {
            File('$dump/${marker.name}.png')
                .writeAsBytesSync(Uint8List.fromList(icon.byteData));
          }
        }
        // The runner's dot carries a halo, so it is the widest pin even though
        // the finish flag's disc is larger.
        expect(sizes[RunMapMarker.current]!,
            greaterThan(sizes[RunMapMarker.finish]!));
        expect(sizes[RunMapMarker.finish]!,
            greaterThan(sizes[RunMapMarker.start]!));
      });
    });

    testWidgets('a pin is drawn once per pixel ratio and reused',
        (tester) async {
      await tester.runAsync(() async {
        final first = await runMapMarkerIcon(RunMapMarker.start, 2);
        final again = await runMapMarkerIcon(RunMapMarker.start, 2);
        expect(identical(first, again), isTrue);
      });
    });
  });
}
