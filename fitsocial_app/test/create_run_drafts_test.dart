import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/core/connectivity/backend_reachability.dart';
import 'package:fitsocial_app/features/main/application/create_flow_controller.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/presentation/create_screen.dart';
import 'package:fitsocial_app/features/tracking/application/run_draft_providers.dart';
import 'package:fitsocial_app/features/tracking/data/run_draft_store.dart';
import 'package:fitsocial_app/features/tracking/data/run_import_ledger.dart';
import 'package:fitsocial_app/features/tracking/domain/run_draft.dart';

// Two different things are called a draft on this page, and they have to
// coexist: a run that is finished and waiting on a connection, and a form
// somebody stopped filling in.

class _FakeRunDraftStore implements RunDraftStore {
  _FakeRunDraftStore(this._drafts);

  final List<RunDraft> _drafts;

  @override
  Future<List<RunDraft>> list() async => _drafts;

  @override
  Future<RunDraft> save(RunDraft draft, {String? sourcePhotoPath}) async =>
      draft;

  @override
  Future<void> markPublishAttempted(RunDraft draft) async {}

  @override
  Future<void> delete(String id) async => _drafts.removeWhere(
        (draft) => draft.id == id,
      );

  @override
  Future<void> clearAll() async => _drafts.clear();
}

void main() {
  RunDraft runDraft() => RunDraft(
        id: 'run-1',
        savedAt: DateTime.now().subtract(const Duration(minutes: 20)),
        distanceKm: 5.2,
        elapsed: const Duration(minutes: 28),
        averagePace: '5:26 /km',
        shareToFeed: true,
      );

  Future<void> pumpCreate(
    WidgetTester tester, {
    required List<RunDraft> runDrafts,
    MealDraftState? mealDraft,
  }) async {
    final router = GoRouter(
      initialLocation: '/create',
      routes: [
        GoRoute(path: '/create', builder: (_, __) => const CreateScreen()),
        GoRoute(
          path: '/meal-review',
          builder: (_, __) => const Scaffold(body: Text('REVIEW SCREEN')),
        ),
      ],
    );

    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isOfflineProvider.overrideWithValue(false),
          runDraftsProvider.overrideWith(
            (ref) => RunDraftController(
              store: _FakeRunDraftStore([...runDrafts]),
              ledger: const NoopRunImportLedger(),
              publish: (_) async =>
                  const ActivitySaveResult(message: 'Run saved and shared.'),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    if (mealDraft != null) {
      final context = tester.element(find.byType(CreateScreen));
      ProviderScope.containerOf(context)
          .read(createFlowControllerProvider.notifier)
          .updateMeal(mealDraft);
      await tester.pumpAndSettle();
    }
  }

  const analyzedMeal = MealDraftState(
    name: 'Pap and boerewors',
    calories: '750',
    protein: '26',
    carbs: '82',
    fat: '36',
    imageUrl: 'https://example.test/meal.jpg',
  );

  testWidgets('a saved run shows up on the Create page', (tester) async {
    await pumpCreate(tester, runDrafts: [runDraft()]);

    expect(find.text('Saved run'), findsOneWidget);
    expect(find.text('Post'), findsOneWidget);
  });

  testWidgets('the page is unchanged when there are none', (tester) async {
    await pumpCreate(tester, runDrafts: const []);

    expect(find.text('Saved run'), findsNothing);
    expect(find.text('Track an Activity'), findsOneWidget);
  });

  // Neither suppresses the other: they are different kinds of unfinished
  // business and both need to be reachable.
  testWidgets('a saved run and a form draft coexist', (tester) async {
    await pumpCreate(tester, runDrafts: [runDraft()], mealDraft: analyzedMeal);

    expect(find.text('Saved run'), findsOneWidget);
    expect(find.text('Resume where you left off or clear the canvas.'),
        findsOneWidget);
  });

  // The finished run leads: it is only waiting on a connection, whereas the
  // form is waiting on the person.
  testWidgets('the saved run sits above the resume card', (tester) async {
    await pumpCreate(tester, runDrafts: [runDraft()], mealDraft: analyzedMeal);

    final runTop = tester.getTopLeft(find.text('Saved run')).dy;
    final resumeTop = tester
        .getTopLeft(
          find.text('Resume where you left off or clear the canvas.'),
        )
        .dy;

    expect(runTop, lessThan(resumeTop));
  });

  testWidgets('the create actions are still all there', (tester) async {
    await pumpCreate(tester, runDrafts: [runDraft()]);

    for (final title in [
      'Log a Workout',
      'Track an Activity',
      'Log a Meal',
      'Share a Post',
      'Enter a Challenge',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });
}
