import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/features/onboarding/application/onboarding_draft_providers.dart';
import 'package:fitsocial_app/features/onboarding/data/onboarding_draft_store.dart';
import 'package:fitsocial_app/features/onboarding/domain/fitness_profile.dart';
import 'package:fitsocial_app/features/onboarding/presentation/shape_screen.dart';

/// Onboarding Step 2. Focus is optional; experience, equipment and days must
/// all be answered before Continue; every tap reaches the draft; and Back
/// returns to Step 1.
void main() {
  late MemoryOnboardingDraftStore store;

  setUp(() => store = MemoryOnboardingDraftStore());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/onboarding/goal',
      routes: [
        GoRoute(
          path: '/onboarding/goal',
          builder: (context, state) => const Text('goal screen'),
        ),
        GoRoute(
          path: '/onboarding/shape',
          builder: (context, state) => const ShapeScreen(),
        ),
        GoRoute(
          path: '/onboarding/plan',
          builder: (context, state) => const Text('plan screen'),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [onboardingDraftStoreProvider.overrideWithValue(store)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push('/onboarding/shape');
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  FilledButton continueButton(WidgetTester tester) =>
      tester.widget(find.widgetWithText(FilledButton, 'Continue'));

  testWidgets('Continue waits for experience, equipment and days',
      (tester) async {
    await pump(tester);
    expect(continueButton(tester).onPressed, isNull);

    await tap(tester, 'A year or so');
    await tap(tester, 'Dumbbells');
    expect(continueButton(tester).onPressed, isNull);

    await tap(tester, '4');
    expect(continueButton(tester).onPressed, isNotNull);
  });

  testWidgets('every answer reaches the draft', (tester) async {
    await pump(tester);
    await tap(tester, 'Chest');
    await tap(tester, 'Years');
    await tap(tester, 'Home gym');
    await tap(tester, '6');

    final draft = await store.read();
    expect(draft?.secondaryFocus, SecondaryFocus.chest);
    expect(draft?.secondaryFocusAnswered, isTrue);
    expect(draft?.fitnessLevel, Difficulty.advanced);
    expect(draft?.equipment, {Equipment.homeGym});
    expect(draft?.weeklyGoalDays, 6);
  });

  testWidgets('Performance is the HYROX focus', (tester) async {
    await pump(tester);
    await tap(tester, 'Performance ›');
    expect((await store.read())?.secondaryFocus, SecondaryFocus.hyrox);
  });

  testWidgets('tapping the chosen focus again takes it off', (tester) async {
    await pump(tester);
    await tap(tester, 'Glutes');
    await tap(tester, 'Glutes');

    final draft = await store.read();
    expect(draft?.secondaryFocus, isNull);
    expect(draft?.secondaryFocusAnswered, isFalse);
  });

  testWidgets('Skip clears the focus and counts as an answer', (tester) async {
    await pump(tester);
    await tap(tester, 'Arms');
    await tap(tester, 'Skip');

    final draft = await store.read();
    expect(draft?.secondaryFocus, isNull);
    expect(draft?.secondaryFocusAnswered, isTrue);
    expect(find.text('Skipped'), findsOneWidget);
  });

  testWidgets('Continue with no focus picked records it as skipped',
      (tester) async {
    await pump(tester);
    await tap(tester, 'New to this');
    await tap(tester, 'Nothing but me');
    await tap(tester, '3');
    await tap(tester, 'Continue');

    expect(find.text('plan screen'), findsOneWidget);
    final draft = await store.read();
    expect(draft?.secondaryFocusAnswered, isTrue);
    expect(draft?.isComplete, isFalse, reason: 'no goal was picked here');
  });

  testWidgets('the summary card reflects the answers', (tester) async {
    await store.save(const OnboardingDraft(
      primaryGoal: TrainingGoal.athleticPerformance,
    ));
    await pump(tester);
    await tap(tester, 'Dumbbells');
    await tap(tester, '4');

    expect(find.text('Dumbbells · 4 days · athletic focus'), findsOneWidget);
  });

  testWidgets('saved answers come back', (tester) async {
    await store.save(const OnboardingDraft(
      fitnessLevel: Difficulty.intermediate,
      equipment: {Equipment.dumbbells},
      weeklyGoalDays: 4,
    ));
    await pump(tester);
    expect(continueButton(tester).onPressed, isNotNull);
  });

  testWidgets('Back returns to Step 1', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('goal screen'), findsOneWidget);
  });

  test('the summary is built from whatever is answered', () {
    expect(ShapeScreen.summaryFor(const OnboardingDraft()), isNull);
    expect(
      ShapeScreen.summaryFor(const OnboardingDraft(weeklyGoalDays: 3)),
      '3 days',
    );
    expect(
      ShapeScreen.summaryFor(const OnboardingDraft(
        primaryGoal: TrainingGoal.loseFat,
        equipment: {Equipment.none},
        weeklyGoalDays: 5,
      )),
      'Nothing but me · 5 days · fat-loss focus',
    );
  });
}
