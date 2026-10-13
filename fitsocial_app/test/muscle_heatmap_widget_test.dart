import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_palette.dart';
import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/domain/muscle_heat.dart';
import 'package:fitsocial_app/shared/widgets/muscle_heatmap.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The middle of the first shape drawn for [muscle].
Offset _centreOf(List<BodyRegion> regions, String muscle) =>
    regions.firstWhere((r) => r.muscle == muscle).path.getBounds().center;

const _pushDay = {
  'chest': 6.0,
  'shoulders': 9.0,
  'triceps': 7.5,
  'core': 1.0,
};

Future<void> _pump(WidgetTester tester, Widget child, {bool dark = true}) =>
    tester.pumpWidget(MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(key: const ValueKey('map'), child: child),
        ),
      ),
    ));

void main() {
  group('geometry', () {
    test('the middle of each region is that region', () {
      for (final (regions, side) in [
        (BodyMapGeometry.front, 'front'),
        (BodyMapGeometry.back, 'back'),
      ]) {
        for (final muscle in {
          for (final r in regions)
            if (r.muscle != null) r.muscle!,
        }) {
          expect(
            BodyMapGeometry.hitTest(regions, _centreOf(regions, muscle)),
            muscle,
            reason: '$muscle on the $side',
          );
        }
      }
    });

    test('empty space and the head are nothing', () {
      expect(
          BodyMapGeometry.hitTest(BodyMapGeometry.front, Offset.zero), isNull);
      expect(
        BodyMapGeometry.hitTest(BodyMapGeometry.front, const Offset(80, 22)),
        isNull,
      );
    });

    test('every painted muscle is on at least one side', () {
      final drawn = {
        for (final r in [...BodyMapGeometry.front, ...BodyMapGeometry.back])
          if (r.muscle != null) r.muscle!,
      };
      expect(drawn, paintedMuscles.toSet());
    });
  });

  test('the two strongest shades stand out from the surface', () {
    for (final palette in [AppPalette.dark, AppPalette.light]) {
      for (final level in [3, 4]) {
        expect(
          _contrast(heatColor(level, palette), palette.surface),
          greaterThanOrEqualTo(3),
          reason: 'level $level, ${palette.isDark ? 'dark' : 'light'}',
        );
      }
    }
  });

  testWidgets('a tap on a muscle names it; the head does nothing',
      (tester) async {
    final taps = <String>[];
    await _pump(
      tester,
      MuscleHeatmap(
        sets: _pushDay,
        scale: HeatScale.weekly,
        sides: BodySides.front,
        onTap: taps.add,
      ),
    );
    final origin = tester.getTopLeft(
      find.descendant(
        of: find.byType(MuscleHeatmap),
        matching: find.byType(CustomPaint),
      ),
    );

    await tester.tapAt(origin + _centreOf(BodyMapGeometry.front, 'chest'));
    await tester.tapAt(origin + const Offset(80, 22));

    expect(taps, ['chest']);
  });

  testWidgets('each muscle reads out its sets', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const MuscleHeatmap(sets: {'chest': 14}, scale: HeatScale.weekly),
    );

    expect(find.semantics.byLabel('Chest, 14 sets this week, in target'),
        findsOne);
    expect(find.semantics.byLabel('Quads, 0 sets this week'), findsOne);
    expect(find.bySemanticsLabel(RegExp(r'^Body map\. Most trained: chest')),
        findsOneWidget);
    handle.dispose();
  });

  testWidgets('a session map has no target in its labels', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const MuscleHeatmap(sets: {'triceps': 7.5}, scale: HeatScale.session),
    );

    expect(find.semantics.byLabel('Triceps, 7.5 sets this workout'), findsOne);
    handle.dispose();
  });

  testWidgets('new numbers fade in, and land', (tester) async {
    Widget map(Map<String, double> sets) =>
        MuscleHeatmap(sets: sets, scale: HeatScale.session);
    await _pump(tester, map(const {}));
    await _pump(tester, map(_pushDay));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('goldens', () {
    for (final dark in [true, false]) {
      final theme = dark ? 'dark' : 'light';
      for (final sides in BodySides.values) {
        testWidgets('${sides.name}, $theme', (tester) async {
          await _pump(
            tester,
            MuscleHeatmap(
              sets: _pushDay,
              scale: HeatScale.session,
              sides: sides,
              height: 220,
            ),
            dark: dark,
          );
          await expectLater(
            find.byKey(const ValueKey('map')),
            matchesGoldenFile(
                'goldens/muscle_heatmap_${sides.name}_$theme.png'),
          );
        });
      }

      testWidgets('selected, $theme', (tester) async {
        await _pump(
          tester,
          MuscleHeatmap(
            sets: _pushDay,
            scale: HeatScale.session,
            selected: 'shoulders',
            onTap: (_) {},
            height: 220,
          ),
          dark: dark,
        );
        await expectLater(
          find.byKey(const ValueKey('map')),
          matchesGoldenFile('goldens/muscle_heatmap_selected_$theme.png'),
        );
      });
    }
  });
}
