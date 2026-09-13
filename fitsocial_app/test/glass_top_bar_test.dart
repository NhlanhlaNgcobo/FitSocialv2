import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/shared/layout/nav_visibility.dart';
import 'package:fitsocial_app/shared/widgets/bottom_nav.dart';
import 'package:fitsocial_app/shared/widgets/glass_top_bar.dart';
import 'package:fitsocial_app/shared/widgets/liquid_glass.dart';

/// Hosts both bars the way the shell does: the top one over a body that runs
/// up behind it, the nav floating at the other end.
Widget host({
  ValueListenable<bool>? hidden,
  double topInset = 0,
}) {
  // The nav is handed the value directly and the top bar reads the notifier,
  // exactly as the shell wires them, so a test drives both from one switch.
  final Widget nav = hidden == null
      ? FitSocialBottomNav(currentIndex: 0, onTap: (_) {})
      : ValueListenableBuilder<bool>(
          valueListenable: hidden,
          builder: (context, value, _) => FitSocialBottomNav(
            currentIndex: 0,
            onTap: (_) {},
            hidden: value,
          ),
        );

  final Widget scaffold = Scaffold(
    extendBody: true,
    extendBodyBehindAppBar: true,
    appBar: const GlassTopBar(title: Text('FitSocial')),
    body: const SizedBox.expand(),
    bottomNavigationBar: nav,
  );

  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: MediaQuery(
      data: MediaQueryData(padding: EdgeInsets.only(top: topInset)),
      child: hidden == null
          ? scaffold
          : NavVisibilityScope(hidden: hidden, child: scaffold),
    ),
  );
}

/// The bar's own pane, told apart from the nav's by being the higher of the two
/// on screen.
LiquidGlass topGlass(WidgetTester tester) {
  final panes = tester.widgetList<LiquidGlass>(find.byType(LiquidGlass));
  return panes.first;
}

Finder topPane() => find.byType(LiquidGlass).first;
Finder navPane() => find.byType(LiquidGlass).last;

void main() {
  testWidgets('is the same material as the nav, not a lookalike',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final panes = tester.widgetList<LiquidGlass>(find.byType(LiquidGlass));
    expect(panes, hasLength(2));

    final top = panes.first;
    final nav = panes.last;

    // Every uniform the shader takes. The point of the change is that these
    // two panes are cut from one material: if the nav's finish is ever tuned
    // and the bar's is not, the app has two glasses again.
    expect(top.refraction, nav.refraction);
    expect(top.edge, nav.edge);
    expect(top.aberration, nav.aberration);
    expect(top.reflect, nav.reflect);
    expect(top.lens, isTrue);
    expect(nav.lens, isTrue);
  });

  testWidgets('reads the backdrop rather than painting a translucent fill',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // Two lenses on screen, so two backdrop passes — the top bar's and the
    // nav's. A flat fill would show up here as one, or none.
    expect(find.byType(BackdropFilter), findsNWidgets(2));
  });

  testWidgets('spans the screen and reaches up behind the status bar',
      (tester) async {
    await tester.pumpWidget(host(topInset: 40));
    await tester.pumpAndSettle();

    final screen = tester.getSize(find.byType(MaterialApp));
    final bar = tester.getRect(topPane());

    // Edge to edge, unlike the nav: the row is too wide to inset on a phone
    // once the music island opens.
    expect(bar.left, 0);
    expect(bar.right, screen.width);
    // Up to the very top, so content passing under the clock is refracted
    // rather than sliding past it bare.
    expect(bar.top, 0);
    expect(bar.height, kToolbarHeight + 40);
  });

  testWidgets('leaves through the top edge when the nav leaves through the '
      'bottom', (tester) async {
    final hidden = ValueNotifier<bool>(false);
    addTearDown(hidden.dispose);

    await tester.pumpWidget(host(hidden: hidden, topInset: 40));
    await tester.pumpAndSettle();

    final restingTop = tester.getRect(topPane());
    final restingNav = tester.getRect(navPane());

    hidden.value = true;
    await tester.pumpAndSettle();

    final goneTop = tester.getRect(topPane());
    final goneNav = tester.getRect(navPane());

    // The bar clears the screen entirely rather than parking a sliver on the
    // edge, and it goes *up* while the capsule goes *down*.
    expect(goneTop.bottom, lessThanOrEqualTo(0));
    expect(goneNav.top, greaterThanOrEqualTo(restingNav.bottom));

    hidden.value = false;
    await tester.pumpAndSettle();

    expect(tester.getRect(topPane()), restingTop);
    expect(tester.getRect(navPane()), restingNav);
    expect(goneTop.top, lessThan(restingTop.top));
  });

  testWidgets('opens already away on a screen entered mid-scroll',
      (tester) async {
    final hidden = ValueNotifier<bool>(true);
    addTearDown(hidden.dispose);

    await tester.pumpWidget(host(hidden: hidden, topInset: 40));
    // One frame only: arriving on a scrolled branch is a starting position, so
    // there should be nothing left to settle.
    await tester.pump();

    expect(tester.getRect(topPane()).bottom, lessThanOrEqualTo(0));
  });

  testWidgets('stays put on a screen with no shell above it', (tester) async {
    // A pushed route hears no scroll from the shell. A bar that hid itself
    // there could never be brought back, so the default has to be visible.
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(tester.getRect(topPane()).top, 0);
    expect(topGlass(tester).lens, isTrue);
  });

  testWidgets('leaves room for its own height plus the status bar',
      (tester) async {
    late double clearance;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 40)),
          child: Builder(
            builder: (context) {
              clearance = GlassTopBar.clearance(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    // The feed pads itself by this, so getting it wrong hides the first post
    // behind the glass rather than under it.
    expect(clearance, kToolbarHeight + 40);
  });
}
