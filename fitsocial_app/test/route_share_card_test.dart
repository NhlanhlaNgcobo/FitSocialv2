import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/shared/services/run_card_exporter.dart';
import 'package:fitsocial_app/shared/widgets/route_smoothing.dart';
import 'package:fitsocial_app/shared/widgets/route_sparkline.dart';
import 'package:fitsocial_app/shared/widgets/run_summary_card.dart';

const _route = [
  RoutePoint(latitude: -26.20, longitude: 28.00, seconds: 0),
  RoutePoint(latitude: -26.21, longitude: 28.02, seconds: 300),
  RoutePoint(latitude: -26.22, longitude: 28.01, seconds: 540),
  RoutePoint(latitude: -26.23, longitude: 28.03, seconds: 900),
];

void main() {
  group('RoutePlacement', () {
    test('the default is centred and is not written to the post', () {
      expect(RoutePlacement.centred.isCentred, isTrue);
      expect(RoutePlacement.centred.toMap(), isNull);
      // Dragged back to the middle by hand counts as the default too.
      expect(
        const RoutePlacement(dx: 0.001, dy: -0.002, scale: 1.004).toMap(),
        isNull,
      );
    });

    test('round-trips through its Firestore map', () {
      const placement = RoutePlacement(dx: 0.2, dy: -0.15, scale: 1.4);
      final stored = placement.toMap();
      expect(stored, {'x': 0.2, 'y': -0.15, 's': 1.4});
      expect(RoutePlacement.fromMap(stored), placement);
    });

    test('anything missing or malformed reads as centred', () {
      expect(RoutePlacement.fromMap(null), RoutePlacement.centred);
      expect(RoutePlacement.fromMap('nonsense'), RoutePlacement.centred);
      expect(
        RoutePlacement.fromMap({'x': 'left', 'y': null, 's': double.nan}),
        RoutePlacement.centred,
      );
    });

    test('a stored value out of range is held inside the limits', () {
      final read = RoutePlacement.fromMap({'x': 4.0, 'y': -9.0, 's': 40.0});
      expect(read.dx, RoutePlacement.maxOffset);
      expect(read.dy, -RoutePlacement.maxOffset);
      expect(read.scale, RoutePlacement.maxScale);
    });
  });

  group('route smoothing', () {
    test('drops jitter along a straight road, keeps both ends', () {
      final jittery = [
        for (var i = 0; i <= 20; i++) Offset(i * 10.0, i.isEven ? 0.3 : -0.3),
      ];
      final kept = simplifyIndices(jittery, 1);
      expect(kept, [0, 20]);
    });

    test('keeps a real corner', () {
      const corner = [Offset(0, 0), Offset(50, 0), Offset(100, 0),
        Offset(100, 50), Offset(100, 100)];
      expect(simplifyIndices(corner, 1), [0, 2, 4]);
    });

    test('the smoothed path still starts and ends on the route', () {
      const points = [Offset(0, 0), Offset(40, 10), Offset(80, 0),
        Offset(120, 30)];
      final metrics = smoothPath(points).computeMetrics().toList();
      expect(metrics, hasLength(1));
      final metric = metrics.single;
      final start = metric.getTangentForOffset(0)!.position;
      final end = metric.getTangentForOffset(metric.length)!.position;
      expect(start, points.first);
      expect((end - points.last).distance, lessThan(0.01));
    });

    test('a long trace simplifies without recursing', () {
      final long = [
        for (var i = 0; i < 20000; i++) Offset(i.toDouble(), (i % 7) * 0.1),
      ];
      expect(simplifyIndices(long, 1), [0, 19999]);
    });
  });

  group('RunSummaryCard', () {
    Future<void> pump(WidgetTester tester, Widget card) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(body: Center(child: SizedBox(width: 360, child: card))),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('passes its placement down to the line', (tester) async {
      const placement = RoutePlacement(dx: 0.1, dy: 0.2, scale: 0.8);
      await pump(
        tester,
        const RunSummaryCard(
          route: _route,
          distanceLabel: '5.20 km',
          routePlacement: placement,
        ),
      );
      final line = tester.widget<RouteSparkline>(find.byType(RouteSparkline));
      expect(line.placement, placement);
    });

    testWidgets('dragging moves the line while adjusting', (tester) async {
      var placement = RoutePlacement.centred;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: StatefulBuilder(
                  builder: (context, setState) => RunSummaryCard(
                    route: _route,
                    distanceLabel: '5.20 km',
                    routePlacement: placement,
                    onRoutePlacementChanged: (next) =>
                        setState(() => placement = next),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(RunSummaryCard), const Offset(60, 0));
      await tester.pumpAndSettle();

      expect(placement.dx, greaterThan(0.05));
      expect(placement.dy.abs(), lessThan(0.01));
      expect(placement.scale, 1);
    });

    testWidgets('a sticker draws no photo and no frame', (tester) async {
      await pump(
        tester,
        RunSummaryCard(
          route: _route,
          distanceLabel: '5.20 km',
          background: MemoryImage(_onePixelPng),
          frame: RunCardFrame.sticker,
        ),
      );
      // The wordmark is an image too, so look for the photo specifically.
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is MemoryImage,
        ),
        findsNothing,
      );
      expect(find.byType(RouteSparkline), findsOneWidget);
    });
  });

  group('RunCardExport', () {
    test('a sticker needs a line or a number of its own', () {
      final photoOnly = RunCardExport(background: MemoryImage(_onePixelPng));
      expect(photoOnly.hasContentFor(RunCardFormat.post), isTrue);
      expect(photoOnly.hasContentFor(RunCardFormat.sticker), isFalse);
      expect(
        const RunCardExport(route: _route)
            .hasContentFor(RunCardFormat.sticker),
        isTrue,
      );
    });
  });
}

/// A 1 × 1 transparent PNG.
final _onePixelPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
