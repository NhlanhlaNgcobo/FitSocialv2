import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/shared/widgets/form_section_header.dart';
import 'package:fitsocial_app/shared/widgets/glass_well.dart';
import 'package:fitsocial_app/shared/widgets/liquid_glass.dart';

Future<void> pumpField(WidgetTester tester, {required bool inWell}) async {
  const field = TextField(
    decoration: InputDecoration(hintText: 'e.g. Upper Body Power'),
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: inWell ? const GlassWell(child: field) : field,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// What the field will actually paint, after the theme has been folded in.
InputDecoration resolved(WidgetTester tester) =>
    tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;

void main() {
  group('a field in a glass well', () {
    testWidgets('paints no surface of its own', (tester) async {
      await pumpField(tester, inWell: true);

      // The defect this exists to stop: `InputBorder.none` takes a field's
      // outline away but not its fill, so an opaque slab went on being painted
      // in the middle of the pane and the form read as a box inside a box.
      expect(resolved(tester).filled, isFalse);
      expect(resolved(tester).border, InputBorder.none);
    });

    testWidgets('leaves a field outside a well alone', (tester) async {
      await pumpField(tester, inWell: false);

      // A bare field still needs a surface — the override is the well's doing
      // and must not leak out of it.
      expect(resolved(tester).filled, isTrue);
      expect(resolved(tester).border, isNot(InputBorder.none));
    });
  });

  group('a field in a plain pane', () {
    testWidgets('loses its opaque fill but keeps its outline', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LiquidGlass(
              child: TextField(
                decoration: InputDecoration(hintText: 'Search'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The pane drops the fill for everything under it, so a search bar or a
      // comment box inside a glass sheet stops painting a slab.
      expect(resolved(tester).filled, isFalse);

      // But it keeps the shape that says it is a field -- only a GlassWell,
      // which draws that outline itself, takes this away too.
      expect(resolved(tester).border, isNot(InputBorder.none));
      expect(resolved(tester).enabledBorder, isNot(InputBorder.none));
    });
  });

  group('the form section header', () {
    testWidgets('keeps its label beside its icon, not across the screen',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: FormSectionHeader(
              icon: Icons.fitness_center_rounded,
              label: 'Workout title',
              hint: 'Optional',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final icon = tester.getRect(find.byType(Icon));
      final label = tester.getRect(find.text('Workout title'));
      final hint = tester.getRect(find.text('Optional'));

      // Log Workout used to centre the label over the field below, which left
      // the icon stranded at the far edge from the words it belongs to.
      expect(
        label.left - icon.right,
        lessThan(24),
        reason: 'the label reads as part of the chip it sits next to',
      );
      expect(hint.left, greaterThan(label.left));
    });
  });
}
