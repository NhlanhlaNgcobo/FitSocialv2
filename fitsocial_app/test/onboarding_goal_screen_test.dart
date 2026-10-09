import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/features/onboarding/application/onboarding_draft_providers.dart';
import 'package:fitsocial_app/features/onboarding/data/onboarding_draft_store.dart';
import 'package:fitsocial_app/features/onboarding/domain/fitness_profile.dart';
import 'package:fitsocial_app/features/onboarding/presentation/goal_screen.dart';

/// Onboarding Step 1. Tapping a card selects it; Continue moves on; nothing
/// moves on without a goal; and the choice is written to the draft so it
/// survives the app being killed.
void main() {
  late MemoryOnboardingDraftStore store;

  setUp(() => store = MemoryOnboardingDraftStore());

  Future<void> pump(WidgetTester tester) async {
    // A tall phone, so the whole grid and the button fit without scrolling.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/onboarding/goal',
      routes: [
        GoRoute(
          path: '/onboarding/goal',
          builder: (context, state) => const GoalScreen(),
        ),
        GoRoute(
          path: '/onboarding/shape',
          builder: (context, state) => const Text('shape screen'),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) =>
              Text('login ${state.uri.queryParameters['mode']}'),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [onboardingDraftStoreProvider.overrideWithValue(store)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapGoal(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  FilledButton continueButton(WidgetTester tester) => tester.widget(
        find.widgetWithText(FilledButton, 'Continue'),
      );

  testWidgets('shows all eight goals', (tester) async {
    await pump(tester);
    for (final goal in TrainingGoal.values) {
      expect(find.text(goal.label), findsOneWidget);
      expect(find.text(goal.subtitle), findsOneWidget);
    }
    expect(find.text('YOUR TRAINING STARTS HERE'), findsOneWidget);
  });

  testWidgets('Continue is disabled until a goal is picked', (tester) async {
    await pump(tester);
    expect(continueButton(tester).onPressed, isNull);

    await tapGoal(tester, 'Build Muscle');
    expect(continueButton(tester).onPressed, isNotNull);
  });

  testWidgets('tapping a card selects it without moving on', (tester) async {
    await pump(tester);
    await tapGoal(tester, 'Lose Fat');

    expect(find.text('shape screen'), findsNothing);
    expect((await store.read())?.primaryGoal, TrainingGoal.loseFat);

    // A second tap changes the answer.
    await tapGoal(tester, 'Get Lean');
    expect((await store.read())?.primaryGoal, TrainingGoal.getLean);
  });

  testWidgets('Continue goes to Step 2', (tester) async {
    await pump(tester);
    await tapGoal(tester, 'Build Muscle');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('shape screen'), findsOneWidget);
  });

  testWidgets('a saved goal is restored and Continue is ready', (tester) async {
    await store.save(
      const OnboardingDraft(primaryGoal: TrainingGoal.improveEndurance),
    );
    await pump(tester);

    expect(continueButton(tester).onPressed, isNotNull);
    final selectedCard = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.selected == true,
    );
    expect(
      find.descendant(
        of: selectedCard,
        matching: find.text('Improve Endurance'),
      ),
      findsOneWidget,
    );
    expect(selectedCard, findsOneWidget);
  });

  testWidgets('Log in opens the login screen and keeps the answers',
      (tester) async {
    await pump(tester);
    await tapGoal(tester, 'Build Core');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.text('login login'), findsOneWidget);
    expect((await store.read())?.primaryGoal, TrainingGoal.buildCore);
  });
}
