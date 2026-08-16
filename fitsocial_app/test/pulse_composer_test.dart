import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/pulse/presentation/pulse_composer_screen.dart';

/// Brings up the composer and lets it settle.
///
/// Never `pumpAndSettle`: the shutter's halo animation repeats forever, so
/// waiting for the tree to go quiet would hang. The long first pump is there to
/// let the camera the composer opens on fail and its snackbar expire — nothing
/// can pick media in a test, and a snackbar left on screen sits over the very
/// controls these tests tap.
Future<void> pumpComposer(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(
        home: PulseComposerScreen(),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 5));
  await tester.pump(const Duration(seconds: 1));
}

/// Taps [tab] below its label, near the bottom edge of the switch.
///
/// Tapping the words themselves would pass against a row of labels floating in
/// dead space. The whole segment is the button, so the test presses where a
/// thumb actually lands.
Future<void> tapModeBelowLabel(WidgetTester tester, String tab) async {
  final label = tester.getRect(find.text(tab));
  await tester.tapAt(Offset(label.center.dx, label.bottom + 8));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  // The composer opens on the camera, so photo mode is the one that works by
  // default — a mode switch that does not respond leaves video and text
  // unreachable without anything looking broken on screen.
  group('switching what kind of Pulse to make', () {
    testWidgets('opens on photo', (tester) async {
      await pumpComposer(tester);

      expect(find.text('Capture a Pulse'), findsOneWidget);
      expect(find.text('Photo'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
      expect(find.text('Text'), findsOneWidget);
    });

    testWidgets('reaches video from a tap anywhere in its segment',
        (tester) async {
      await pumpComposer(tester);
      await tapModeBelowLabel(tester, 'Video');

      expect(find.text('Record a Pulse'), findsOneWidget);
      expect(find.text('Capture a Pulse'), findsNothing);
    });

    testWidgets('reaches text from a tap anywhere in its segment',
        (tester) async {
      await pumpComposer(tester);
      await tapModeBelowLabel(tester, 'Text');

      expect(find.text('Say something'), findsOneWidget);
      expect(find.text('Capture a Pulse'), findsNothing);
    });

    testWidgets('goes back to photo again', (tester) async {
      await pumpComposer(tester);
      await tapModeBelowLabel(tester, 'Text');
      expect(find.text('Say something'), findsOneWidget);

      await tapModeBelowLabel(tester, 'Photo');
      expect(find.text('Capture a Pulse'), findsOneWidget);
    });
  });

  group('the share button', () {
    // Nothing to send from an empty camera screen, and a dead grey button
    // under the shutter is just noise.
    testWidgets('stays away until there is something to share',
        (tester) async {
      await pumpComposer(tester);

      expect(find.text('Share Pulse'), findsNothing);
    });

    // A text Pulse can be shared the moment it is written, so the button is
    // there from the start — disabled until the first character.
    testWidgets('arrives with text mode, above the switch', (tester) async {
      await pumpComposer(tester);
      await tapModeBelowLabel(tester, 'Text');

      expect(find.text('Share Pulse'), findsOneWidget);
      expect(
        tester.getCenter(find.text('Share Pulse')).dy,
        lessThan(tester.getCenter(find.text('Photo')).dy),
      );
    });
  });
}
