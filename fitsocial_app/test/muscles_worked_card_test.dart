import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/presentation/muscles_worked_card.dart';
import 'package:fitsocial_app/shared/widgets/muscle_heatmap.dart';

const _pushDay = {
  'chest': 6.0,
  'shoulders': 9.0,
  'triceps': 7.5,
  'core': 1.0,
  'forearms': 0.5,
};

Future<void> _pump(
  WidgetTester tester,
  Map<String, double> sets, {
  VoidCallback? onThisWeek,
}) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(
      body: SingleChildScrollView(
        child: MusclesWorkedCard(sets: sets, onThisWeek: onThisWeek),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('bars the top four muscles, most first', (tester) async {
    await _pump(tester, _pushDay);

    expect(find.text('Muscles worked'), findsOneWidget);
    for (final name in ['Shoulders', 'Triceps', 'Chest', 'Core']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('Forearms'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Shoulders')).dy,
      lessThan(tester.getTopLeft(find.text('Core')).dy),
    );
    expect(find.text('Sets this workout · primary 1, secondary 0.5'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a muscle tapped on the body is selected and gets a bar',
      (tester) async {
    await _pump(tester, _pushDay);
    final paint = find
        .descendant(
          of: find.byType(MuscleHeatmap),
          matching: find.byType(CustomPaint),
        )
        .first;
    final scale = 198 / BodyMapGeometry.box.height;
    final forearm = BodyMapGeometry.front
        .firstWhere((r) => r.muscle == 'forearms')
        .path
        .getBounds()
        .center;

    await tester.tapAt(tester.getTopLeft(paint) + forearm * scale);
    await tester.pumpAndSettle();

    expect(
      tester.widget<MuscleHeatmap>(find.byType(MuscleHeatmap)).selected,
      'forearms',
    );
    expect(find.text('Forearms'), findsOneWidget);
    expect(find.text('0.5'), findsOneWidget);
  });

  testWidgets('the This week link shows only when it goes somewhere',
      (tester) async {
    await _pump(tester, _pushDay);
    expect(find.text('This week'), findsNothing);

    var opened = false;
    await _pump(tester, _pushDay, onThisWeek: () => opened = true);
    await tester.tap(find.text('This week'));
    expect(opened, isTrue);
  });

  testWidgets('full body work gets a line, not a region', (tester) async {
    await _pump(tester, const {'full body': 5});
    expect(find.text('Full body · 5 sets'), findsOneWidget);
  });
}
