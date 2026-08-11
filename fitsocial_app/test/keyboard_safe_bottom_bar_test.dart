import 'package:fitsocial_app/shared/widgets/keyboard_safe_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Scaffold with [bar] in the slot that composers live in, under a
/// MediaQuery describing a phone with the keyboard either up or down.
Widget scaffoldWithBar({
  required Widget bar,
  double keyboardHeight = 0,
  double gestureBarHeight = 34,
}) {
  return MediaQuery(
    data: MediaQueryData(
      viewInsets: EdgeInsets.only(bottom: keyboardHeight),
      // viewPadding keeps the gesture bar's height whether or not the keyboard
      // covers it, which is exactly why it is the right field to read.
      viewPadding: EdgeInsets.only(bottom: gestureBarHeight),
      padding: EdgeInsets.only(
        bottom: keyboardHeight > 0 ? 0 : gestureBarHeight,
      ),
    ),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: bar,
      ),
    ),
  );
}

const _barKey = Key('bar');
final _bar = Container(key: _barKey, height: 60, color: const Color(0xFF000000));

/// The bottom of the screen the Scaffold was given, so the assertions below
/// don't depend on the test surface's default size.
double screenBottom(WidgetTester tester) =>
    tester.getRect(find.byType(Scaffold)).bottom;

double barBottom(WidgetTester tester) => tester.getRect(find.byKey(_barKey)).bottom;

void main() {
  group('keyboardSafeBottomInset', () {
    test('clears the keyboard when it is up', () {
      const media = MediaQueryData(
        viewInsets: EdgeInsets.only(bottom: 300),
        viewPadding: EdgeInsets.only(bottom: 34),
      );
      expect(keyboardSafeBottomInset(media), 300);
    });

    test('clears the gesture bar when the keyboard is down', () {
      const media = MediaQueryData(
        viewPadding: EdgeInsets.only(bottom: 34),
      );
      expect(keyboardSafeBottomInset(media), 34);
    });

    test('is nothing at all on a device with neither', () {
      expect(keyboardSafeBottomInset(const MediaQueryData()), 0);
    });
  });

  group('KeyboardSafeBottomBar in a Scaffold', () {
    // The bug this exists for: a Scaffold pins bottomNavigationBar to its own
    // bottom edge and hands the keyboard inset only to `body`, so a comment
    // box in that slot is covered by the keyboard being typed on.
    testWidgets('an unwrapped bar is left underneath the keyboard',
        (tester) async {
      await tester.pumpWidget(scaffoldWithBar(bar: _bar, keyboardHeight: 300));

      expect(
        barBottom(tester),
        screenBottom(tester),
        reason: 'Scaffold does not lift the bar itself',
      );
    });

    testWidgets('a wrapped bar sits above the keyboard', (tester) async {
      await tester.pumpWidget(
        scaffoldWithBar(
          bar: KeyboardSafeBottomBar(child: _bar),
          keyboardHeight: 300,
        ),
      );

      expect(barBottom(tester), screenBottom(tester) - 300);
    });

    testWidgets('with the keyboard down it clears the gesture bar instead',
        (tester) async {
      await tester.pumpWidget(
        scaffoldWithBar(bar: KeyboardSafeBottomBar(child: _bar)),
      );

      expect(barBottom(tester), screenBottom(tester) - 34);
    });

    testWidgets('the bar keeps its full height — it is lifted, not squashed',
        (tester) async {
      await tester.pumpWidget(
        scaffoldWithBar(
          bar: KeyboardSafeBottomBar(child: _bar),
          keyboardHeight: 300,
        ),
      );

      expect(tester.getSize(find.byKey(_barKey)).height, 60);
    });
  });
}
