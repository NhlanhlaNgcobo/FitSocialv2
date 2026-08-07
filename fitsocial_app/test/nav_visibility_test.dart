import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitsocial_app/shared/layout/nav_visibility.dart';
import 'package:fitsocial_app/shared/widgets/bottom_nav.dart';

/// Pumps a throwaway tree just to get a BuildContext, which every
/// ScrollNotification requires.
Future<BuildContext> pumpContext(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

FixedScrollMetrics _metrics(double pixels, AxisDirection direction) {
  return FixedScrollMetrics(
    pixels: pixels,
    minScrollExtent: 0,
    maxScrollExtent: 4000,
    viewportDimension: 800,
    axisDirection: direction,
    devicePixelRatio: 1,
  );
}

/// A vertical scroll of [delta] pixels, [pixels] into the list.
ScrollUpdateNotification update(
  BuildContext context,
  double delta, {
  double pixels = 500,
}) {
  return ScrollUpdateNotification(
    metrics: _metrics(pixels, AxisDirection.down),
    context: context,
    scrollDelta: delta,
  );
}

ScrollEndNotification end(BuildContext context) {
  return ScrollEndNotification(
    metrics: _metrics(500, AxisDirection.down),
    context: context,
  );
}

/// A horizontal strip's scroll — the Pulse tray, the badge row.
ScrollUpdateNotification horizontalUpdate(BuildContext context, double delta) {
  return ScrollUpdateNotification(
    metrics: _metrics(100, AxisDirection.right),
    context: context,
    scrollDelta: delta,
  );
}

/// Hosts the bar the way AppShell does, driven by [visibility].
Widget shell(NavVisibility visibility) {
  return MaterialApp(
    home: Scaffold(
      extendBody: true,
      body: NotificationListener<ScrollNotification>(
        onNotification: visibility.handle,
        child: ListView.builder(
          itemCount: 60,
          itemBuilder: (_, i) => SizedBox(height: 80, child: Text('row $i')),
        ),
      ),
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: visibility.hidden,
        builder: (context, hidden, _) => FitSocialBottomNav(
          currentIndex: 0,
          onTap: (_) {},
          hidden: hidden,
        ),
      ),
    ),
  );
}

void main() {
  group('NavVisibility', () {
    testWidgets('starts on screen', (tester) async {
      await pumpContext(tester);
      final visibility = NavVisibility();
      addTearDown(visibility.dispose);

      expect(visibility.hidden.value, isFalse);
    });

    testWidgets('a short scroll down is not enough to hide it', (tester) async {
      final context = await pumpContext(tester);
      final visibility = NavVisibility();
      addTearDown(visibility.dispose);

      visibility.handle(update(context, 10));
      expect(visibility.hidden.value, isFalse);
    });

    testWidgets('sustained downward travel hides it', (tester) async {
      final context = await pumpContext(tester);
      final visibility = NavVisibility();
      addTearDown(visibility.dispose);

      for (var i = 0; i < 5; i++) {
        visibility.handle(update(context, 10));
      }
      expect(visibility.hidden.value, isTrue);
    });

    testWidgets('scrolling back up brings it straight back', (tester) async {
      final context = await pumpContext(tester);
      final visibility = NavVisibility();
      addTearDown(visibility.dispose);

      for (var i = 0; i < 5; i++) {
        visibility.handle(update(context, 10));
      }
      expect(visibility.hidden.value, isTrue);

      for (var i = 0; i < 5; i++) {
        visibility.handle(update(context, -10));
      }
      expect(visibility.hidden.value, isFalse);
    });

    // The bar is dismissed by scrolling down and recalled by scrolling up.
    // Letting go part-way down the feed is neither, so it must stay gone.
    testWidgets('lifting off mid-feed leaves it hidden', (tester) async {
      final context = await pumpContext(tester);
      final visibility = NavVisibility();
      addTearDown(visibility.dispose);

      for (var i = 0; i < 5; i++) {
        visibility.handle(update(context, 10));
      }
      visibility.handle(end(context));

      expect(visibility.hidden.value, isTrue);
    });

    testWidgets('the run resets between gestures', (tester) async {
      final context = await pumpContext(tester);
      final visibility = NavVisibility();
      addTearDown(visibility.dispose);

      // 20px down, finger up, then 20px more on a fresh gesture. Neither run
      // reaches the threshold on its own, and the reset stops them adding up.
      visibility.handle(update(context, 20));
      visibility.handle(end(context));
      visibility.handle(update(context, 20));

      expect(visibility.hidden.value, isFalse);
    });

    // The regression that made scrolling feel laggy: a drag emits deltas that
    // flip sign constantly, and a per-event rule toggled the bar on each one,
    // restarting the transition mid-flight several times a second.
    testWidgets('jitter around a direction does not thrash the state',
        (tester) async {
      final context = await pumpContext(tester);
      final visibility = NavVisibility();
      addTearDown(visibility.dispose);

      final states = <bool>[];
      visibility.hidden
          .addListener(() => states.add(visibility.hidden.value));

      for (var i = 0; i < 20; i++) {
        visibility.handle(update(context, i.isEven ? 6 : -5));
      }

      expect(
        states,
        isEmpty,
        reason: 'noise that never travels 24px in one direction should not '
            'change state at all',
      );
    });

    testWidgets('a reversal restarts the run rather than netting off',
        (tester) async {
      final context = await pumpContext(tester);
      final visibility = NavVisibility();
      addTearDown(visibility.dispose);

      visibility.handle(update(context, 20));
      visibility.handle(update(context, -20));
      expect(visibility.hidden.value, isFalse);
    });

    testWidgets('never hides while pinned at the top', (tester) async {
      final context = await pumpContext(tester);
      final visibility = NavVisibility();
      addTearDown(visibility.dispose);

      for (var i = 0; i < 5; i++) {
        visibility.handle(update(context, 10, pixels: 0));
      }
      expect(visibility.hidden.value, isFalse);
    });

    testWidgets('horizontal strips do not drive the bar', (tester) async {
      final context = await pumpContext(tester);
      final visibility = NavVisibility();
      addTearDown(visibility.dispose);

      for (var i = 0; i < 10; i++) {
        visibility.handle(horizontalUpdate(context, 30));
      }
      expect(visibility.hidden.value, isFalse);
    });

    testWidgets('passes every notification on to other listeners',
        (tester) async {
      final context = await pumpContext(tester);
      final visibility = NavVisibility();
      addTearDown(visibility.dispose);

      expect(visibility.handle(update(context, 30)), isFalse);
      expect(visibility.handle(end(context)), isFalse);
      expect(visibility.handle(horizontalUpdate(context, 30)), isFalse);
    });
  });

  group('in the shell layout', () {
    testWidgets('dragging the feed down clears the bar off the screen',
        (tester) async {
      final visibility = NavVisibility();
      addTearDown(visibility.dispose);

      await tester.pumpWidget(shell(visibility));
      await tester.pumpAndSettle();

      final screen = tester.getSize(find.byType(MaterialApp));
      expect(
        tester.getRect(find.byType(BackdropFilter)).bottom,
        lessThan(screen.height),
      );

      // Drag upward = scroll the content down, well past the flip distance.
      final gesture = await tester.startGesture(const Offset(200, 300));
      await gesture.moveBy(const Offset(0, -150));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byType(BackdropFilter)).top,
        greaterThanOrEqualTo(screen.height),
        reason: 'the whole capsule should be past the bottom edge, not '
            'peeking over it',
      );

      // And it stays gone once the finger lifts.
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(BackdropFilter)).top,
        greaterThanOrEqualTo(screen.height),
      );
    });

    testWidgets('dragging back up floats it in again', (tester) async {
      final visibility = NavVisibility();
      addTearDown(visibility.dispose);

      await tester.pumpWidget(shell(visibility));
      await tester.pumpAndSettle();
      final resting = tester.getRect(find.byType(BackdropFilter)).top;

      final gesture = await tester.startGesture(const Offset(200, 300));
      await gesture.moveBy(const Offset(0, -150));
      await tester.pumpAndSettle();
      await gesture.moveBy(const Offset(0, 150));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byType(BackdropFilter)).top,
        closeTo(resting, 0.5),
      );
    });
  });
}
