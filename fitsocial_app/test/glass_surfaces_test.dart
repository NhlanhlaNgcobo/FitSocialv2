import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_palette.dart';
import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/shared/widgets/dark_card.dart';
import 'package:fitsocial_app/shared/widgets/glass.dart';
import 'package:fitsocial_app/shared/widgets/glass_motion.dart';
import 'package:fitsocial_app/shared/widgets/liquid_backdrop.dart';
import 'package:fitsocial_app/shared/widgets/liquid_glass.dart';

Future<void> pumpCard(
  WidgetTester tester, {
  Widget? backdrop,
  bool dark = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Scaffold(
        body: DarkCard(backdrop: backdrop, child: const Text('body')),
      ),
    ),
  );
  // MaterialApp cross-fades theme changes, so a bare pump would read the
  // previous theme's colours back when a test pumps twice.
  await tester.pumpAndSettle();
}

void main() {
  // Widget tests run on Skia, where ImageFilter.shader throws, so everything
  // below exercises the fallback. That is the half worth pinning: the lens is
  // only reachable on a real Impeller device, but the fallback is what every
  // other device actually gets.
  test('the lens is understood to be unavailable under test', () {
    expect(ui.ImageFilter.isShaderFilterSupported, isFalse);
    expect(LiquidGlassProgram.supported, isFalse);
  });

  group('dark card', () {
    testWidgets('carries no opaque fill of its own', (tester) async {
      await pumpCard(tester);

      // The whole point of the material: an opaque surface here is the one
      // thing that would stand between the glass and anything worth bending.
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.color, Colors.transparent);
      expect(card.clipBehavior, Clip.antiAlias);
    });

    testWidgets('is a pane of glass, and does not clip twice', (tester) async {
      await pumpCard(tester);

      final glass = tester.widget<LiquidGlass>(find.byType(LiquidGlass));
      expect(glass.borderRadius, BorderRadius.circular(DarkCard.radius));
      // The Card already clips to this shape; a second rounded clip would be a
      // saveLayer for nothing.
      expect(glass.clip, isFalse);
    });

    testWidgets('paints a backdrop below the glass, not above it', (
      tester,
    ) async {
      await pumpCard(tester, backdrop: const GlassBloom(colors: [Colors.red]));

      // Order is what makes the card's own colour arrive bent rather than
      // sitting on top of the pane unrefracted.
      final stack = tester.widget<Stack>(
        find
            .descendant(of: find.byType(Card), matching: find.byType(Stack))
            .first,
      );
      final kinds = stack.children.map((child) => child.runtimeType).toList();
      expect(kinds.first, Positioned);
      expect(kinds.last, LiquidGlass);
    });
  });

  group('liquid glass fallback', () {
    testWidgets('is frosted, not merely tinted', (tester) async {
      // Asked for explicitly: a lens is what has a fallback. An ordinary card
      // is painted either way and has nothing to fall back from.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: LiquidGlass(lens: true, child: Text('body')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A flat tinted capsule is not a second material. Where the lens cannot
      // run the glass still has to blur what is behind it.
      final blur = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(blur.filter, same(LiquidGlass.fallbackBlur));
      expect(find.byType(GlassPane), findsOneWidget);
    });

    testWidgets('is not what an ordinary card gets', (tester) async {
      await pumpCard(tester);

      // A card sits on [LiquidBackdrop], and blurring three soft radial pools
      // returns three soft radial pools. It paid a full render pass for a
      // difference nobody could see; now it paints the material instead.
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(GlassPane), findsNothing);
    });

    testWidgets('draws the rim the shader would have drawn', (tester) async {
      for (final dark in [true, false]) {
        await pumpCard(tester, dark: dark);

        final rim = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((paint) => paint.foregroundPainter)
            .whereType<GlassRim>()
            .single;
        expect(rim.radius, DarkCard.radius);
      }
    });
  });

  group('glass bloom', () {
    testWidgets('paints nothing at zero intensity', (tester) async {
      await pumpCard(
        tester,
        backdrop: const GlassBloom(colors: [Colors.red], intensity: 0),
      );

      expect(find.byType(ImageFiltered), findsNothing);
    });

    testWidgets('never places more blobs than it has positions for', (
      tester,
    ) async {
      await pumpCard(
        tester,
        backdrop: const GlassBloom(
          colors: [Colors.red, Colors.green, Colors.blue, Colors.yellow],
        ),
      );

      // A fourth colour has nowhere to sit; dropping it beats reusing a
      // placement and stacking two blobs in the same corner.
      final blobs = tester.widget<Stack>(
        find.descendant(
          of: find.byType(ImageFiltered),
          matching: find.byType(Stack),
        ),
      );
      expect(blobs.children, hasLength(3));
    });
  });

  group('the app-wide ground', () {
    // The backdrop is still unless a screen change has just landed, and the
    // move it makes then does finish -- so unlike the old 72-second loop, these
    // are safe to pumpAndSettle.
    testWidgets('keeps its painting off everything above it', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LiquidBackdrop())),
      );
      await tester.pump();

      // Its own layer, or a repaint on the backdrop's clock drags the feed
      // above it into repainting too.
      expect(
        find.descendant(
          of: find.byType(RepaintBoundary),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );
    });

    testWidgets('costs nothing until a screen change asks it to move', (
      tester,
    ) async {
      addTearDown(GlassMotion.resetForTest);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LiquidBackdrop())),
      );
      await tester.pump();

      CustomPainter ground() {
        return tester
            .widget<CustomPaint>(
              find
                  .descendant(
                    of: find.byType(LiquidBackdrop),
                    matching: find.byType(CustomPaint),
                  )
                  .first,
            )
            .painter!;
      }

      final before = ground();

      // Three full-screen radial gradients sit under every other pixel in the
      // app, and an app left open on one screen has no reason to pay for them
      // twice. Sitting there is free.
      await tester.pump(const Duration(seconds: 2));
      expect(ground().shouldRepaint(before), isFalse);

      // A screen change, and the ground is somewhere new by the end of it.
      GlassMotion.begin();
      await tester.pump();
      GlassMotion.end();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(ground().shouldRepaint(before), isTrue);
    });

    testWidgets('holds still when the system asks for less motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(home: Scaffold(body: LiquidBackdrop())),
        ),
      );
      await tester.pump();

      // If the drift were still running this would time out rather than
      // reporting a clean frame.
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('moves after a screen change, never during one', (
      tester,
    ) async {
      addTearDown(GlassMotion.resetForTest);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LiquidBackdrop())),
      );
      await tester.pump();

      // At rest the ground is genuinely at rest -- this is an app that stays
      // open for the length of a run.
      expect(tester.hasRunningAnimations, isFalse);

      GlassMotion.begin();
      await tester.pump();

      // The widest surface in the app, under every other one. A tick of it is a
      // full-screen repaint that the nav's lens then has to re-read -- and a
      // screen change is the worst frame in the app to spend that on.
      expect(tester.hasRunningAnimations, isFalse);

      // The far side of the transition is where it is free.
      GlassMotion.end();
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);

      // And it arrives, rather than running on.
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    test('no theme paints a ground that would cover it', () {
      // Every pane of glass in the app bends this one backdrop. A Scaffold
      // that painted its own opaque surface would cover it, and that screen's
      // glass would have nothing behind it to bend.
      for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
        expect(theme.scaffoldBackgroundColor, Colors.transparent);
      }
    });

    test('a dialog is a solid card, not a see-through one', () {
      // A dialog paints only its card, so a solid one covers nothing the
      // glass needs -- and a transparent one floats its text over the page.
      expect(
        AppTheme.darkTheme.dialogTheme.backgroundColor,
        AppPalette.dark.surface,
      );
      expect(
        AppTheme.lightTheme.dialogTheme.backgroundColor,
        AppPalette.light.surface,
      );
    });
  });

  group('the material reads in both themes', () {
    // Each of these is a bug the light theme actually shipped with. The
    // material's mechanics all assume a dark ground, and on a pale one they do
    // nothing or work backwards -- which is invisible to every other test here,
    // because widget tests assert structure and this is entirely about value.

    test('a light pane has a surface of its own', () {
      // At 14% white on cream a card had no surface at all: only its hairline
      // was left, which is the flat-sheet-of-cream failure the light palette
      // was tuned against in the first place.
      expect(AppPalette.light.liquidTint.a, greaterThan(0.5));
      // Dark is the opposite case and must stay thin, or the lens fogs over.
      expect(AppPalette.dark.liquidTint.a, lessThan(0.2));
    });

    test('the rim runs the right way in each theme', () {
      // The shader mixes its rim and specular toward this colour. Toward white
      // on near-black it reads as a lit edge; toward white on cream it reads as
      // nothing, because there is no brighter left to go.
      // computeLuminance reads only r, g and b, so the rim's own alpha -- which
      // is its strength, not its colour -- does not muddy the comparison.
      expect(
        AppPalette.dark.glassRimHigh.computeLuminance(),
        greaterThan(AppPalette.dark.surface.computeLuminance()),
        reason: 'a dark theme separates a pane by lighting its rim',
      );
      expect(
        AppPalette.light.glassRimHigh.computeLuminance(),
        lessThan(AppPalette.light.surface.computeLuminance()),
        reason: 'a light theme has no brighter to go, so its rim must darken',
      );
    });

    test('only the theme that needs a shadow pays for one', () {
      // On near-black a pane lifts off the page by being brighter at the rim,
      // so a shadow would be fill rate spent on nothing.
      expect(AppPalette.dark.paneShadow.a, 0);
      expect(AppPalette.light.paneShadow.a, greaterThan(0));
    });
  });
}
