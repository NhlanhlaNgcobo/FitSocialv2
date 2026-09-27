import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/presentation/workout_log_screen.dart';

import 'shot_fakes.dart';
import 'shot_harness.dart';

Finder sheetFields() => find.descendant(
    of: find.byType(BottomSheet), matching: find.byType(TextField));

/// The log being built, one step per frame index.
Future<void> buildLog(WidgetTester t, int i) async {
  const lifts = [
    ('Back Squat', '5', '5', '90'),
    ('Romanian Deadlift', '4', '8', '70'),
    ('Walking Lunges', '3', '12', '16'),
  ];
  if (i == 6) await t.enterText(find.byType(TextField).at(0), 'Leg Day');
  if (i == 10) await t.enterText(find.byType(TextField).at(1), '65');
  if (i == 13) await t.enterText(find.byType(TextField).at(2), '480');
  for (var k = 0; k < lifts.length; k++) {
    final base = 18 + k * 34;
    final (name, sets, reps, kg) = lifts[k];
    if (i == base) {
      await t.ensureVisible(find.text('Add exercise').last);
      await t.tap(find.text('Add exercise').last);
    }
    if (i == base + 10) await t.enterText(sheetFields().at(0), name);
    if (i == base + 15) await t.enterText(sheetFields().at(1), sets);
    if (i == base + 18) await t.enterText(sheetFields().at(2), reps);
    if (i == base + 21) await t.enterText(sheetFields().at(3), kg);
    if (i == base + 26) {
      await t.tap(find.descendant(
          of: find.byType(BottomSheet),
          matching: find.widgetWithText(FilledButton, 'Add exercise')));
    }
  }
}

void main() {
  testWidgets('workout log', (tester) async {
    await shoot(tester, 'workout_log',
        shotApp(const WorkoutLogScreen(), pushed: true, overrides: signedIn()));
  });

  testWidgets('workout build clip', (tester) async {
    await shootFrames(tester, 'clip_workout_build',
        shotApp(const WorkoutLogScreen(), pushed: true, overrides: signedIn()),
        count: 130, step: (t, i, _) async {
      await buildLog(t, i);
      await t.pump(const Duration(microseconds: 33333));
    });
  });

  testWidgets('repeat clip', (tester) async {
    await shootFrames(tester, 'clip_workout_repeat',
        shotApp(const WorkoutLogScreen(), pushed: true, overrides: signedIn()),
        count: 60, step: (t, i, _) async {
      if (i == 12) await t.tap(find.text('Leg Day'));
      await t.pump(const Duration(microseconds: 33333));
    });
  });
}
