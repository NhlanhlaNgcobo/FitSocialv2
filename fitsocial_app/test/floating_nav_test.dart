import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitsocial_app/shared/widgets/bottom_nav.dart';

/// Hosts the bar the way AppShell does, over scrollable content.
Widget host({
  required int currentIndex,
  required ValueChanged<int> onTap,
  double bottomInset = 0,
  bool hidden = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(padding: EdgeInsets.only(bottom: bottomInset)),
      child: Scaffold(
        extendBody: true,
        body: const SizedBox.expand(),
        bottomNavigationBar: FitSocialBottomNav(
          currentIndex: currentIndex,
          onTap: onTap,
          hidden: hidden,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders a backdrop blur so content shows through the glass',
      (tester) async {
    await tester.pumpWidget(host(currentIndex: 0, onTap: (_) {}));

    // Without a BackdropFilter the bar would be a flat translucent fill —
    // this is the whole difference between "glass" and "grey rectangle".
    expect(find.byType(BackdropFilter), findsOneWidget);

    final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(filter.filter, isA<ImageFilter>());
  });

  testWidgets('floats inset from the screen edges rather than spanning them',
      (tester) async {
    await tester.pumpWidget(host(currentIndex: 0, onTap: (_) {}));

    final screen = tester.getSize(find.byType(MaterialApp));
    final bar = tester.getRect(find.byType(BackdropFilter));

    expect(bar.left, greaterThan(0));
    expect(bar.right, lessThan(screen.width));
    // A gap below it too, otherwise it is docked, not hovering.
    expect(bar.bottom, lessThan(screen.height));
  });

  testWidgets('reports clearance that covers the bar and the safe area',
      (tester) async {
    late double flat;
    late double inset;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(),
          child: Builder(
            builder: (context) {
              flat = FitSocialBottomNav.clearance(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(bottom: 34),
          ),
          child: Builder(
            builder: (context) {
              inset = FitSocialBottomNav.clearance(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(flat, greaterThan(0));
    // A home-indicator inset pushes the bar up, so content must clear further.
    expect(inset, flat + 34);
  });

  testWidgets('taps report the destination index', (tester) async {
    final tapped = <int>[];
    await tester.pumpWidget(
      host(currentIndex: 0, onTap: tapped.add),
    );

    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pump();

    expect(tapped, [4]);
  });

  testWidgets('the selected destination takes the filled glyph',
      (tester) async {
    await tester.pumpWidget(host(currentIndex: 0, onTap: (_) {}));
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsNothing);

    await tester.pumpWidget(host(currentIndex: 3, onTap: (_) {}));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('hiding drops the capsule clear of the bottom edge',
      (tester) async {
    await tester.pumpWidget(host(currentIndex: 0, onTap: (_) {}));
    await tester.pumpAndSettle();
    final screen = tester.getSize(find.byType(MaterialApp));
    final resting = tester.getRect(find.byType(BackdropFilter));

    await tester.pumpWidget(
      host(currentIndex: 0, onTap: (_) {}, hidden: true),
    );
    await tester.pumpAndSettle();
    final gone = tester.getRect(find.byType(BackdropFilter));

    expect(gone.top, greaterThanOrEqualTo(screen.height));
    // Straight down, not off to one side.
    expect(gone.center.dx, closeTo(resting.center.dx, 0.5));
  });

  testWidgets('it shrinks as it goes, so it reads as being drawn through '
      'the edge', (tester) async {
    await tester.pumpWidget(host(currentIndex: 0, onTap: (_) {}));
    await tester.pumpAndSettle();
    final resting = tester.getRect(find.byType(BackdropFilter)).width;

    await tester.pumpWidget(
      host(currentIndex: 0, onTap: (_) {}, hidden: true),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(tester.getRect(find.byType(BackdropFilter)).width,
        lessThan(resting));
  });

  testWidgets('the transition is animated, not a jump', (tester) async {
    await tester.pumpWidget(host(currentIndex: 0, onTap: (_) {}));
    await tester.pumpAndSettle();
    final resting = tester.getRect(find.byType(BackdropFilter)).top;

    await tester.pumpWidget(
      host(currentIndex: 0, onTap: (_) {}, hidden: true),
    );
    // Part-way through the 220ms departure it should be mid-flight, i.e.
    // neither still at rest nor already gone.
    await tester.pump(const Duration(milliseconds: 90));
    final midFlight = tester.getRect(find.byType(BackdropFilter)).top;

    await tester.pumpAndSettle();
    final settled = tester.getRect(find.byType(BackdropFilter)).top;

    expect(midFlight, greaterThan(resting));
    expect(midFlight, lessThan(settled));
  });

  // The pop that makes it read as surfacing rather than appearing: on the way
  // back it passes slightly above where it comes to rest.
  testWidgets('returning overshoots its resting place before settling',
      (tester) async {
    await tester.pumpWidget(host(currentIndex: 0, onTap: (_) {}, hidden: true));
    await tester.pumpAndSettle();

    await tester.pumpWidget(host(currentIndex: 0, onTap: (_) {}));

    var highest = double.infinity;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      final top = tester.getRect(find.byType(BackdropFilter)).top;
      if (top < highest) highest = top;
    }

    await tester.pumpAndSettle();
    final resting = tester.getRect(find.byType(BackdropFilter)).top;

    expect(highest, lessThan(resting));
  });

  testWidgets('draws a gradient rim rather than a flat border',
      (tester) async {
    await tester.pumpWidget(host(currentIndex: 0, onTap: (_) {}));

    // The rim is a shader-stroked RRect; a plain Border could not fade from a
    // lit top edge to a transparent bottom one.
    final painters = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    expect(
      painters.any((p) => p.foregroundPainter != null),
      isTrue,
    );
  });
}
