import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/pulse/presentation/pulse_composer_screen.dart';

/// Brings up the composer and lets it settle.
///
/// Never `pumpAndSettle`: the shutter's halo animation repeats forever, so
/// waiting for the tree to go quiet would hang. A plain pump is enough — the
/// composer opens on the capture screen and asks the device for nothing until
/// the shutter is pressed, so there is no failing picker or expiring toast to
/// wait out before the controls can be tapped.
Future<void> pumpComposer(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(
        home: PulseComposerScreen(),
      ),
    ),
  );
  await tester.pump();
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
  // The composer opens on photo, so that is the mode that works by default —
  // a mode switch that does not respond leaves video and text unreachable
  // without anything looking broken on screen.
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
    testWidgets('stays away until there is something to share', (tester) async {
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

  // The composer used to throw the OS camera up from its own first frame.
  // Landing on the capture screen instead only means anything if nothing
  // reaches for the device until the shutter is pressed — and that is
  // invisible in the widget tree, so it is watched at the picker's channel.
  //
  // The second test is what gives the first one teeth: without a case that
  // does trip the channel, a wrong channel name would leave 'never opens it'
  // passing for the wrong reason.
  group('the camera', () {
    const picker = MethodChannel('plugins.flutter.io/image_picker');
    late List<String> calls;

    setUp(() {
      calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(picker, (call) async {
        calls.add(call.method);
        // Null is what the picker returns when someone backs out of it, which
        // leaves the composer sitting on the capture screen.
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(picker, null);
    });

    testWidgets('stays shut until the shutter is pressed', (tester) async {
      await pumpComposer(tester);

      expect(calls, isEmpty);
      expect(find.text('Capture a Pulse'), findsOneWidget);
    });

    testWidgets('opens when the shutter is pressed', (tester) async {
      await pumpComposer(tester);
      // By size, not by icon alone: the Photo tab in the mode switch carries
      // the same glyph at 17. The disc is the big one.
      await tester.tap(find.byWidgetPredicate(
        (widget) =>
            widget is Icon &&
            widget.icon == Icons.photo_camera_rounded &&
            widget.size == 34,
      ));
      await tester.pump();

      expect(calls, isNotEmpty);
    });
  });
}
