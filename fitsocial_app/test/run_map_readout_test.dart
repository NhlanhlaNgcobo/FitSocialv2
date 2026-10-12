import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/tracking/presentation/run_map_readout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The full-screen map on a 360-wide phone: the screen less its gutters, the
  // close button and the gap beside it.
  const narrowWidth = 360.0 - 16 * 2 - 48 - 8;

  Future<void> pumpReadout(WidgetTester tester, {String? climb}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: narrowWidth,
              child: RunMapReadout(
                statusLabel: 'LIVE',
                statusAccent: true,
                distanceKm: 12.34,
                elapsedLabel: '1:23:45',
                paceLabel: 'PACE /KM',
                paceValue: '18:48',
                climbMeters: climb,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('four figures fit a narrow full-screen map without overflowing',
      (tester) async {
    await pumpReadout(tester, climb: '1234');
    expect(tester.takeException(), isNull);
    expect(find.text('CLIMB M'), findsOneWidget);
    expect(find.text('12.34'), findsOneWidget);
  });

  testWidgets('three figures still fit', (tester) async {
    await pumpReadout(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('CLIMB M'), findsNothing);
  });
}
