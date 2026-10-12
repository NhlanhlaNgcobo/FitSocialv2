import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/data/content_repository_contract.dart';
import 'package:fitsocial_app/features/main/domain/meal_tracking.dart';
import 'package:fitsocial_app/features/main/presentation/macro_goals_sheet.dart';

/// Records which of the two writes the sheet asked for.
class _FakeContent implements ContentRepository {
  MacroGoals? set;
  bool? clearedWithStepBonus;

  @override
  Future<void> setMacroGoals(MacroGoals goals) async => set = goals;

  @override
  Future<void> clearCustomMacroGoals({required bool stepBonus}) async =>
      clearedWithStepBonus = stepBonus;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _calculated = MacroGoals(
  calories: 2150,
  protein: 140,
  carbs: 240,
  fat: 70,
  isDerived: true,
);

void main() {
  Future<_FakeContent> openSheet(
    WidgetTester tester, {
    required MacroGoals current,
    MacroGoals? calculated = _calculated,
  }) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final content = _FakeContent();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentRepositoryProvider.overrideWithValue(content),
          macroGoalsProvider.overrideWith((ref) async => current),
          calculatedMacroGoalsProvider.overrideWith((ref) async => calculated),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => showMacroGoalsSheet(context, ref),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return content;
  }

  testWidgets('own targets can go back to the calculated ones', (
    tester,
  ) async {
    final content = await openSheet(
      tester,
      current: const MacroGoals(calories: 3000, isCustom: true),
    );

    expect(find.textContaining('${formatMacroValue(2150)} kcal'), findsOneWidget);
    await tester.tap(find.text('Use calculated target'));
    await tester.pumpAndSettle();

    expect(content.clearedWithStepBonus, isTrue);
    expect(content.set, isNull);
  });

  testWidgets('no way back is offered when the targets are calculated', (
    tester,
  ) async {
    await openSheet(tester, current: _calculated);
    expect(find.text('Use calculated target'), findsNothing);
  });

  testWidgets('no way back is offered when nothing can be calculated', (
    tester,
  ) async {
    await openSheet(
      tester,
      current: const MacroGoals(calories: 3000, isCustom: true),
      calculated: null,
    );
    expect(find.text('Use calculated target'), findsNothing);
  });

  testWidgets('saving calculated targets untouched keeps them calculated', (
    tester,
  ) async {
    final content = await openSheet(tester, current: _calculated);

    // Only the step switch changes — the reason most people open the sheet.
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('Save targets'));
    await tester.pumpAndSettle();

    expect(content.set, isNull);
    expect(content.clearedWithStepBonus, isFalse);
  });

  testWidgets('an edited target is saved as the user\'s own', (tester) async {
    final content = await openSheet(tester, current: _calculated);

    await tester.enterText(find.byType(TextField).first, '2500');
    await tester.tap(find.text('Save targets'));
    await tester.pumpAndSettle();

    expect(content.set?.calories, 2500);
    expect(content.clearedWithStepBonus, isNull);
  });
}
