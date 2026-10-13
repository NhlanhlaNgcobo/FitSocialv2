import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/application/active_workout_controller.dart';
import 'package:fitsocial_app/features/main/application/activity_actions.dart';
import 'package:fitsocial_app/features/main/application/workout_background_notice.dart';
import 'package:fitsocial_app/features/main/application/workout_log_form_controller.dart';
import 'package:fitsocial_app/features/main/data/active_workout_store.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/data/workout_log_form_store.dart';
import 'package:fitsocial_app/features/main/domain/active_workout.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/workout_log_form.dart';
import 'package:fitsocial_app/features/main/presentation/workout_log_screen.dart';
import 'package:fitsocial_app/features/main/presentation/workout_resume_pill.dart';

class _MemoryFormStore implements WorkoutLogFormStore {
  _MemoryFormStore([this.saved]);

  WorkoutLogForm? saved;
  int writes = 0;

  @override
  Future<WorkoutLogForm?> read() async => saved;

  @override
  Future<void> write(WorkoutLogForm form) async {
    writes++;
    saved = form;
  }

  @override
  Future<void> clear() async => saved = null;
}

class _MemorySessionStore implements ActiveWorkoutStore {
  _MemorySessionStore([this.saved]);

  ActiveWorkout? saved;

  @override
  Future<ActiveWorkout?> read() async => saved;

  @override
  Future<void> write(ActiveWorkout workout) async => saved = workout;

  @override
  Future<void> clear() async => saved = null;
}

class _StubRepository extends UnconfiguredContentRepository {
  const _StubRepository();

  @override
  Future<List<RecentWorkout>> getRecentWorkouts({int limit = 6}) async =>
      const [];

  @override
  Future<List<List<ExerciseEntry>>> getWorkoutHistory(
          {int limit = 200}) async =>
      const [];
}

class _RecordingActions implements ActivityActions {
  final List<WorkoutLogDraft> saved = [];

  @override
  Future<ActivitySaveResult> saveWorkout(WorkoutLogDraft draft) async {
    saved.add(draft);
    return const ActivitySaveResult(message: 'Workout saved.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingNotice implements WorkoutBackgroundNotice {
  final List<String> calls = [];

  @override
  Future<void> requestPermission() async => calls.add('permission');

  @override
  Future<void> showSession(ActiveWorkout workout) async => calls.add('session');

  @override
  Future<void> showUnsavedLog(WorkoutLogForm form) async =>
      calls.add('form:${form.title}');

  @override
  Future<void> hide() async => calls.add('hide');
}

WorkoutLogForm _form({
  String title = 'Leg day',
  DateTime? savedAt,
  List<WorkoutLogFormRow> rows = const [
    WorkoutLogFormRow(
      name: 'Back Squat (Barbell)',
      exerciseId: 'back-squat-barbell',
      sets: '5',
      reps: '5',
      weight: '102,5',
    ),
    WorkoutLogFormRow(
      name: 'Rowing Machine',
      exerciseId: 'rowing-machine',
      cardio: true,
      minutes: '12',
      distance: '2,4',
    ),
  ],
}) =>
    WorkoutLogForm(
      savedAt: savedAt ?? DateTime.now(),
      loggedAt: DateTime(2026, 10, 12, 7, 30),
      title: title,
      duration: '55',
      notes: 'Felt strong',
      rows: rows,
    );

void main() {
  group('the unsaved form', () {
    test('round-trips everything typed, exactly as typed', () {
      final back = WorkoutLogForm.fromJson(_form().toJson())!;
      expect(back.title, 'Leg day');
      expect(back.duration, '55');
      expect(back.notes, 'Felt strong');
      expect(back.loggedAt, DateTime(2026, 10, 12, 7, 30));
      final [squat, row] = back.rows;
      expect((squat.sets, squat.reps, squat.weight), ('5', '5', '102,5'));
      expect(row.cardio, isTrue);
      expect((row.minutes, row.distance), ('12', '2,4'));
    });

    test('an untouched form has nothing worth keeping', () {
      final blank = WorkoutLogForm(
        savedAt: DateTime.now(),
        loggedAt: DateTime.now(),
      );
      expect(blank.hasContent, isFalse);
      expect(_form().hasContent, isTrue);
    });

    test('a day-old form is stale', () {
      final now = DateTime(2026, 10, 12, 12);
      expect(
          _form(savedAt: now.subtract(const Duration(hours: 2))).isStale(now),
          isFalse);
      expect(
          _form(savedAt: now.subtract(const Duration(hours: 25))).isStale(now),
          isTrue);
    });

    test('the file store survives a new instance, and clears', () async {
      final dir = await Directory.systemTemp.createTemp('log_form');
      addTearDown(() => dir.delete(recursive: true));
      FileWorkoutLogFormStore store() =>
          FileWorkoutLogFormStore(rootDirectory: () async => dir, userId: 'u1');

      await store().write(_form());
      expect((await store().read())!.title, 'Leg day');
      await store().clear();
      expect(await store().read(), isNull);
    });

    test('a corrupt file costs the form, not the screen', () async {
      final dir = await Directory.systemTemp.createTemp('log_form');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/workout_log_form/u1.json');
      await file.create(recursive: true);
      await file.writeAsString('{not json');
      final store =
          FileWorkoutLogFormStore(rootDirectory: () async => dir, userId: 'u1');
      expect(await store.read(), isNull);
    });
  });

  group('the form controller', () {
    test('restores a recent form and drops a stale one', () async {
      final fresh = WorkoutLogFormController(_MemoryFormStore(_form()));
      await fresh.ready;
      expect(fresh.state?.title, 'Leg day');

      final staleStore = _MemoryFormStore(
        _form(savedAt: DateTime.now().subtract(const Duration(days: 2))),
      );
      final stale = WorkoutLogFormController(staleStore);
      await stale.ready;
      expect(stale.state, isNull);
      expect(staleStore.saved, isNull, reason: 'cleared, not read again');
    });

    test('writes after the debounce, or at once on flush', () async {
      final store = _MemoryFormStore();
      final controller = WorkoutLogFormController(
        store,
        debounce: const Duration(milliseconds: 20),
      );
      await controller.ready;

      controller.update(_form(title: 'A'));
      controller.update(_form(title: 'AB'));
      expect(controller.state?.title, 'AB', reason: 'in memory at once');
      expect(store.writes, 0);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(store.writes, 1, reason: 'one write for the burst');
      expect(store.saved?.title, 'AB');

      controller.update(_form(title: 'ABC'));
      await controller.flush();
      expect(store.saved?.title, 'ABC');
    });

    test('an emptied form leaves nothing behind', () async {
      final store = _MemoryFormStore(_form());
      final controller = WorkoutLogFormController(store);
      await controller.ready;
      controller.update(WorkoutLogForm(
        savedAt: DateTime.now(),
        loggedAt: DateTime.now(),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, isNull);
      expect(store.saved, isNull);
    });
  });

  group('Log Workout', () {
    Future<_MemoryFormStore> pump(
      WidgetTester tester, {
      WorkoutLogForm? saved,
      ActivityActions? actions,
    }) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final store = _MemoryFormStore(saved);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contentRepositoryProvider
                .overrideWithValue(const _StubRepository()),
            workoutLogFormStoreProvider.overrideWithValue(store),
            if (actions != null)
              activityActionsProvider.overrideWithValue(actions),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const WorkoutLogScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return store;
    }

    String text(WidgetTester tester, int field) => tester
        .widget<TextField>(find.byType(TextField).at(field))
        .controller!
        .text;

    testWidgets('comes back as it was left', (tester) async {
      await pump(tester, saved: _form());

      expect(find.text('Picked up where you left off'), findsOneWidget);
      expect(text(tester, 0), 'Leg day');
      expect(text(tester, 1), '55');
      expect(find.text('Back Squat (Barbell)'), findsOneWidget);
      expect(find.text('Rowing Machine'), findsOneWidget);
      // Squat: sets, reps, weight. Then the rower: minutes, distance.
      expect(text(tester, 5), '102,5');
      expect(text(tester, 6), '12');
      expect(text(tester, 7), '2,4');
    });

    testWidgets('what is typed is kept for next time', (tester) async {
      final store = await pump(tester);
      expect(find.text('Picked up where you left off'), findsNothing);

      await tester.enterText(find.byType(TextField).at(0), 'Push');
      await tester.enterText(find.byType(TextField).at(1), '40');
      await tester.pump(const Duration(seconds: 1));

      expect(store.saved?.title, 'Push');
      expect(store.saved?.duration, '40');
    });

    testWidgets('start over throws the old form away', (tester) async {
      final store = await pump(tester, saved: _form());

      await tester.tap(find.text('Start over'));
      await tester.pumpAndSettle();

      expect(text(tester, 0), isEmpty);
      expect(find.text('Back Squat (Barbell)'), findsNothing);
      expect(find.text('Picked up where you left off'), findsNothing);
      expect(store.saved, isNull);
    });

    testWidgets('saving leaves nothing to pick back up', (tester) async {
      final actions = _RecordingActions();
      final store = await pump(tester, saved: _form(), actions: actions);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      expect(actions.saved.single.title, 'Leg day');
      expect(store.saved, isNull);
    });
  });

  group('leaving the app', () {
    ProviderContainer container({
      ActiveWorkout? session,
      WorkoutLogForm? form,
      required _RecordingNotice notice,
    }) {
      final c = ProviderContainer(overrides: [
        activeWorkoutStoreProvider
            .overrideWithValue(_MemorySessionStore(session)),
        workoutLogFormStoreProvider.overrideWithValue(_MemoryFormStore(form)),
        workoutBackgroundNoticeProvider.overrideWithValue(notice),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('a live session goes in the shade, and comes out on return', () async {
      final notice = _RecordingNotice();
      final c = container(
        notice: notice,
        session: ActiveWorkout(
          id: 'w1',
          startedAt: DateTime.now(),
          exercises: const [],
        ),
        form: _form(),
      );
      await c.read(activeWorkoutProvider.notifier).ready;
      await c.read(workoutLogFormProvider.notifier).ready;

      c.read(workoutNoticeLifecycleProvider).appBackgrounded();
      c.read(workoutNoticeLifecycleProvider).appForegrounded();
      await Future<void>.delayed(Duration.zero);

      // The session wins over the form: it is the one with a clock running.
      expect(notice.calls, ['session', 'hide']);
    });

    test('an unsaved form gets a reminder', () async {
      final notice = _RecordingNotice();
      final c = container(notice: notice, form: _form());
      await c.read(activeWorkoutProvider.notifier).ready;
      await c.read(workoutLogFormProvider.notifier).ready;

      c.read(workoutNoticeLifecycleProvider).appBackgrounded();
      await Future<void>.delayed(Duration.zero);

      expect(notice.calls, ['form:Leg day']);
    });

    test('nothing open, nothing shown', () async {
      final notice = _RecordingNotice();
      final c = container(notice: notice);
      await c.read(activeWorkoutProvider.notifier).ready;
      await c.read(workoutLogFormProvider.notifier).ready;

      c.read(workoutNoticeLifecycleProvider).appBackgrounded();
      await Future<void>.delayed(Duration.zero);

      expect(notice.calls, isEmpty);
    });
  });

  group('the resume pill', () {
    Future<void> pumpPill(
      WidgetTester tester, {
      ActiveWorkout? session,
      WorkoutLogForm? form,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkoutStoreProvider
                .overrideWithValue(_MemorySessionStore(session)),
            workoutLogFormStoreProvider
                .overrideWithValue(_MemoryFormStore(form)),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const Scaffold(bottomNavigationBar: WorkoutResumePill()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('offers a live session back', (tester) async {
      await pumpPill(
        tester,
        session: ActiveWorkout(
          id: 'w1',
          startedAt: DateTime.now().subtract(const Duration(minutes: 3)),
          exercises: const [],
        ),
      );
      expect(find.text('Workout in progress'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
    });

    testWidgets('offers an unsaved log back', (tester) async {
      await pumpPill(tester, form: _form());
      expect(find.text('Leg day not saved yet'), findsOneWidget);
      expect(find.text('Finish'), findsOneWidget);
    });

    testWidgets('says nothing when nothing is open', (tester) async {
      await pumpPill(tester);
      expect(find.text('Resume'), findsNothing);
      expect(find.text('Finish'), findsNothing);
    });
  });
}
