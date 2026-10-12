import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/shared/widgets/run_summary_card.dart';

/// The stat row is the one part of the card whose width is driven by data
/// rather than by design: a run that crosses the hour turns "28:14" into
/// "1:11:52", and a long distance widens the number beside it. The row is only
/// as wide as the card, so both numbers have to be able to give ground.
void main() {
  /// Pumps a card at [width] and returns any overflow the layout reported.
  ///
  /// Overflow is an assertion thrown during layout rather than a test failure,
  /// so it has to be caught off [FlutterError.onError] to be asserted on.
  Future<List<String>> pumpCard(
    WidgetTester tester, {
    required double width,
    String? distance,
    String? duration,
  }) async {
    final overflows = <String>[];
    final priorOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('overflowed')) {
        overflows.add(message);
      } else {
        priorOnError?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = priorOnError);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: RunSummaryCard(
                distanceLabel: distance,
                durationLabel: duration,
              ),
            ),
          ),
        ),
      ),
    );

    FlutterError.onError = priorOnError;
    return overflows;
  }

  /// How far the stat sits in from the card's own left edge.
  double leftInset(WidgetTester tester, String label) =>
      tester.getTopLeft(find.text(label)).dx -
      tester.getTopLeft(find.byType(RunSummaryCard)).dx;

  testWidgets('a run past the hour does not run off the card', (tester) async {
    // The pair that overflowed on a 720px phone: a long duration beside a
    // distance, on a card no wider than the feed.
    for (final width in [400.0, 360.0, 320.0, 280.0, 240.0, 200.0]) {
      final overflows = await pumpCard(
        tester,
        width: width,
        distance: '2.37 km',
        duration: '1:11:52',
      );
      expect(
        overflows,
        isEmpty,
        reason: 'the stat row overflowed on a ${width}px card',
      );
    }
  });

  testWidgets('both stats keep sharing a bottom edge', (tester) async {
    await pumpCard(
      tester,
      width: 360,
      distance: '2.37 km',
      duration: '1:11:52',
    );

    // The label hangs off the bottom of its number, and the two columns are
    // hung from the same line — shrinking a number must not lift its caption.
    expect(
      tester.getBottomLeft(find.text('DISTANCE')).dy,
      moreOrLessEquals(tester.getBottomLeft(find.text('TIME')).dy, epsilon: 0.5),
    );
  });

  testWidgets('a card carrying one stat still starts hard left', (
    tester,
  ) async {
    await pumpCard(tester, width: 360, distance: '2.37 km');
    final distanceOnly = leftInset(tester, 'DISTANCE');

    await pumpCard(tester, width: 360, duration: '1:11:52');
    final durationOnly = leftInset(tester, 'TIME');

    await pumpCard(
      tester,
      width: 360,
      distance: '2.37 km',
      duration: '1:11:52',
    );

    // A lone stat sits where the first of a pair sits: the row starts at the
    // padding, and a single child neither centres nor spreads.
    expect(durationOnly, moreOrLessEquals(distanceOnly, epsilon: 0.5));
    expect(distanceOnly, moreOrLessEquals(leftInset(tester, 'DISTANCE'), epsilon: 0.5));
  });

  testWidgets('a blank distance leaves no gap behind it', (tester) async {
    // The gap used to hang off the labels being non-null rather than on there
    // being two stats, so a blank distance pushed the time in by a gap's width.
    await pumpCard(tester, width: 360, distance: '   ', duration: '1:11:52');
    final afterBlank = leftInset(tester, 'TIME');

    await pumpCard(tester, width: 360, duration: '1:11:52');
    expect(afterBlank, moreOrLessEquals(leftInset(tester, 'TIME'), epsilon: 0.5));
  });
}
