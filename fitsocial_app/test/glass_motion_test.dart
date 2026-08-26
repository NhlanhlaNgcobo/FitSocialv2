import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/shared/widgets/glass.dart';
import 'package:fitsocial_app/shared/widgets/glass_motion.dart';
import 'package:fitsocial_app/shared/widgets/liquid_glass.dart';

Future<void> pumpGlass(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: const Scaffold(
        body: LiquidGlass(child: SizedBox(width: 200, height: 80)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // The flag is app-wide, so a test that left it down would take the next one
  // with it.
  setUp(GlassMotion.resetForTest);
  tearDown(GlassMotion.resetForTest);

  group('GlassMotion', () {
    test('is settled until something says otherwise', () {
      expect(GlassMotion.settled.value, isTrue);
    });

    test('stays down until the last transition has finished', () {
      // A push landing on a shell whose branch is still cross-fading. Letting
      // the first one to finish switch the lens back on would put the filter
      // in the middle of the other one's fade, which is the case this whole
      // mechanism exists to avoid.
      GlassMotion.begin();
      GlassMotion.begin();
      expect(GlassMotion.settled.value, isFalse);

      GlassMotion.end();
      expect(GlassMotion.settled.value, isFalse);

      GlassMotion.end();
      expect(GlassMotion.settled.value, isTrue);
    });

    test('an unmatched end cannot drive the count negative', () {
      // A route disposed mid-flight releases its hold in dispose, and the
      // bookkeeping has to survive that arriving twice.
      GlassMotion.end();
      GlassMotion.begin();
      expect(GlassMotion.settled.value, isFalse);
      GlassMotion.end();
      expect(GlassMotion.settled.value, isTrue);
    });
  });

  group('a pane of glass in motion', () {
    testWidgets('drops its filter while a screen change runs', (tester) async {
      await pumpGlass(tester);
      expect(find.byType(BackdropFilter), findsOneWidget);

      GlassMotion.begin();
      await tester.pump();

      // The whole point: a BackdropFilter inside a transition's opacity buffer
      // has no backdrop to read, so it renders the pane as a hole and then
      // snaps. Nothing to read means nothing worth paying for either.
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('still looks like the same material while it holds', (
      tester,
    ) async {
      await pumpGlass(tester);

      GlassMotion.begin();
      await tester.pump();

      // Tint and rim are the pane itself; only the part that reads the screen
      // behind it is missing. Dropping the surface as well is what would make
      // the change visible.
      expect(find.byType(GlassPane), findsOneWidget);
      final rim = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.foregroundPainter)
          .whereType<GlassRim>();
      expect(rim, isNotEmpty);
    });

    testWidgets('hands its content the same constraints while it holds', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 100,
                child: LiquidGlass(child: Text('body')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester.getRect(find.text('body'));

      GlassMotion.begin();
      await tester.pump();

      // Standing in for the filter means standing in for its layout too. A
      // pane that loosened what it passed down would relay out its contents
      // the instant a screen change began, which is a far worse jump than the
      // one this whole mechanism was written to remove.
      expect(tester.getRect(find.text('body')), before);
    });

    testWidgets('takes the filter back once the app stands still', (
      tester,
    ) async {
      await pumpGlass(tester);

      GlassMotion.begin();
      await tester.pump();
      GlassMotion.end();
      await tester.pump();

      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });
}
