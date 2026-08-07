import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/features/main/application/create_flow_controller.dart';
import 'package:fitsocial_app/features/main/presentation/create_screen.dart';

/// Drives the real CreateScreen through a router that mirrors the app's
/// meal routes, so the resume card's callbacks are exercised end to end.
///
/// Assertions check the rendered screen rather than the router's
/// `currentConfiguration.uri` — that field does not reflect an imperative
/// `push`, so asserting on it reports a navigation failure that never
/// happened.
Future<GoRouter> pumpCreateScreen(
  WidgetTester tester, {
  required MealDraftState mealDraft,
  CreateCanvasDestination? activeDestination,
}) async {
  final router = GoRouter(
    initialLocation: '/create',
    routes: [
      GoRoute(path: '/create', builder: (_, __) => const CreateScreen()),
      GoRoute(
        path: '/meal-upload',
        builder: (_, __) => const Scaffold(body: Text('UPLOAD SCREEN')),
      ),
      GoRoute(
        path: '/meal-review',
        builder: (_, __) => const Scaffold(body: Text('REVIEW SCREEN')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  // Seed the draft the way the analyzer does, then let the screen rebuild.
  final context = tester.element(find.byType(CreateScreen));
  final container = ProviderScope.containerOf(context);
  final controller = container.read(createFlowControllerProvider.notifier);
  if (activeDestination != null) controller.begin(activeDestination);
  controller.updateMeal(mealDraft);
  await tester.pumpAndSettle();

  return router;
}

const _analyzedMeal = MealDraftState(
  name: 'Pap and boerewors',
  calories: '750',
  protein: '26',
  carbs: '82',
  fat: '36',
  imageUrl: 'https://example.test/meal.jpg',
);

void main() {
  group('draft resume card', () {
    testWidgets('appears once a meal has been analyzed', (tester) async {
      await pumpCreateScreen(
        tester,
        mealDraft: _analyzedMeal,
        activeDestination: CreateCanvasDestination.photo,
      );

      expect(find.text('Photo meal draft'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
    });

    testWidgets('the arrow resumes an analyzed meal at the review screen',
        (tester) async {
      await pumpCreateScreen(
        tester,
        mealDraft: _analyzedMeal,
        activeDestination: CreateCanvasDestination.photo,
      );

      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pumpAndSettle();

      // Sending an analyzed meal back to the picker would throw away the
      // analysis and cost another vision call to recreate it.
      expect(find.text('REVIEW SCREEN'), findsOneWidget);
      expect(find.text('UPLOAD SCREEN'), findsNothing);
    });

    testWidgets('an un-analyzed photo draft resumes at the picker',
        (tester) async {
      await pumpCreateScreen(
        tester,
        // Name only, no macros and no uploaded photo: nothing to review yet.
        mealDraft: const MealDraftState(name: 'Lunch'),
        activeDestination: CreateCanvasDestination.photo,
      );

      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pumpAndSettle();

      expect(find.text('UPLOAD SCREEN'), findsOneWidget);
      expect(find.text('REVIEW SCREEN'), findsNothing);
    });

    testWidgets('Clear removes the card and the draft', (tester) async {
      await pumpCreateScreen(
        tester,
        mealDraft: _analyzedMeal,
        activeDestination: CreateCanvasDestination.photo,
      );

      expect(find.text('Photo meal draft'), findsOneWidget);

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(find.text('Photo meal draft'), findsNothing);
      expect(find.text('Clear'), findsNothing);

      final context = tester.element(find.byType(CreateScreen));
      final container = ProviderScope.containerOf(context);
      final state = container.read(createFlowControllerProvider);
      expect(state.hasDraft, isFalse);
      expect(state.mealDraft.name, isEmpty);
    });
  });
}
