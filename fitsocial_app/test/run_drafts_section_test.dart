import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/core/connectivity/backend_reachability.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/tracking/application/run_draft_providers.dart';
import 'package:fitsocial_app/features/tracking/data/run_draft_store.dart';
import 'package:fitsocial_app/features/tracking/domain/run_draft.dart';
import 'package:fitsocial_app/features/tracking/presentation/run_drafts_section.dart';

/// An in-memory stand-in, so these tests never touch a disk.
class _FakeRunDraftStore implements RunDraftStore {
  _FakeRunDraftStore(List<RunDraft> initial) : _drafts = [...initial];

  final List<RunDraft> _drafts;
  final List<String> deleted = [];
  final List<String> stamped = [];

  @override
  Future<List<RunDraft>> list() async =>
      [..._drafts]..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  @override
  Future<RunDraft> save(RunDraft draft, {String? sourcePhotoPath}) async {
    _drafts.add(draft);
    return draft;
  }

  @override
  Future<void> markPublishAttempted(RunDraft draft) async =>
      stamped.add(draft.id);

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    _drafts.removeWhere((d) => d.id == id);
  }

  @override
  Future<void> clearAll() async => _drafts.clear();
}

void main() {
  RunDraft draft({
    String id = 'a',
    bool shareToFeed = true,
    DateTime? savedAt,
    DateTime? publishAttemptedAt,
    List<RoutePoint> route = const [],
  }) {
    return RunDraft(
      id: id,
      savedAt: savedAt ?? DateTime.now().subtract(const Duration(hours: 2)),
      distanceKm: 5.2,
      elapsed: const Duration(minutes: 28, seconds: 14),
      averagePace: '5:26 /km',
      shareToFeed: shareToFeed,
      routePoints: route,
      publishAttemptedAt: publishAttemptedAt,
    );
  }

  /// Pumps the section with a fake store and a recording publish stub.
  Future<
      ({
        _FakeRunDraftStore store,
        List<RunLogDraft> published,
      })> pumpSection(
    WidgetTester tester, {
    required List<RunDraft> drafts,
    bool isOffline = false,
    Future<ActivitySaveResult> Function(RunLogDraft)? publish,
  }) async {
    final store = _FakeRunDraftStore(drafts);
    final published = <RunLogDraft>[];

    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isOfflineProvider.overrideWithValue(isOffline),
          // The controller is built directly rather than through the store
          // provider, so the publish call can be a stub. ContentRepository is
          // a forty-method contract and none of it is what these tests are
          // about.
          runDraftsProvider.overrideWith(
            (ref) => RunDraftController(
              store: store,
              publish: publish ??
                  (log) async {
                    published.add(log);
                    return const ActivitySaveResult(
                      message: 'Run saved and shared.',
                    );
                  },
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: RunDraftsSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return (store: store, published: published);
  }

  Future<void> tapIn(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  group('what a row shows', () {
    testWidgets('the numbers the run is judged by', (tester) async {
      await pumpSection(tester, drafts: [draft()]);

      // findRichText, because the metric line is one RichText rather than
      // three Texts — the distance is bold and the rest is not.
      expect(find.textContaining('5.20 km', findRichText: true), findsWidgets);
      expect(find.textContaining('28:14', findRichText: true), findsWidgets);
      expect(
        find.textContaining('5:26 /km', findRichText: true),
        findsWidgets,
      );
      expect(find.textContaining('Saved 2 h ago'), findsOneWidget);
    });

    testWidgets('whether it is going to the feed', (tester) async {
      await pumpSection(tester, drafts: [draft()]);
      expect(find.textContaining('Will post to feed'), findsOneWidget);
    });

    testWidgets('or that it is private', (tester) async {
      await pumpSection(tester, drafts: [draft(shareToFeed: false)]);
      expect(find.textContaining('Private'), findsOneWidget);
      expect(find.text('Upload'), findsOneWidget);
    });

    testWidgets('counts them in the header', (tester) async {
      await pumpSection(tester, drafts: [draft(id: 'a'), draft(id: 'b')]);
      expect(find.text('Saved runs · 2'), findsOneWidget);
    });

    // A file read of a couple of milliseconds does not deserve a spinner in
    // the middle of the Create page.
    testWidgets('nothing at all when there are none', (tester) async {
      await pumpSection(tester, drafts: const []);

      expect(find.textContaining('Saved run'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('offline', () {
    testWidgets('cannot post, and says why', (tester) async {
      await pumpSection(tester, drafts: [draft()], isOffline: true);

      expect(find.textContaining('Offline — reconnect to post'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('can post once the connection is back', (tester) async {
      await pumpSection(tester, drafts: [draft()]);

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });
  });

  group('posting', () {
    testWidgets('sends the run up and drops the row', (tester) async {
      final harness = await pumpSection(tester, drafts: [draft()]);

      await tapIn(tester, find.text('Post'));

      expect(harness.published, hasLength(1));
      expect(harness.published.single.distanceKm, 5.2);
      expect(harness.published.single.shareToFeed, isTrue);
      expect(harness.store.deleted, ['a']);
      expect(find.text('Post'), findsNothing);
    });

    // Stamped before the call goes out, so a process that dies mid-publish
    // leaves evidence rather than a silent duplicate.
    testWidgets('records the attempt before sending', (tester) async {
      final harness = await pumpSection(tester, drafts: [draft()]);

      await tapIn(tester, find.text('Post'));

      expect(harness.store.stamped, ['a']);
    });

    testWidgets('a failure keeps the run', (tester) async {
      final harness = await pumpSection(
        tester,
        drafts: [draft()],
        publish: (_) async => throw Exception('rules rejected it'),
      );

      await tapIn(tester, find.text('Post'));

      expect(harness.store.deleted, isEmpty);
      expect(find.text('Post'), findsOneWidget);
      expect(find.textContaining('Could not post this run'), findsOneWidget);
    });

    // saveRun mints a fresh post every call, so a double tap must not reach it
    // twice.
    testWidgets('a double tap posts once', (tester) async {
      final published = <RunLogDraft>[];
      final store = _FakeRunDraftStore([draft()]);

      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isOfflineProvider.overrideWithValue(false),
            runDraftsProvider.overrideWith(
              (ref) => RunDraftController(
                store: store,
                publish: (log) async {
                  published.add(log);
                  // Slow enough that a second tap lands while the first is
                  // still in flight.
                  await Future<void>.delayed(const Duration(milliseconds: 100));
                  return const ActivitySaveResult(message: 'Run saved.');
                },
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: RunDraftsSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Post'));
      await tester.pump();
      await tester.tap(find.text('Post'));
      await tester.pump();
      // The button disables itself the moment the first tap lands, so this
      // second one has nothing to hit — which is the first line of defence.
      await tester.tap(find.text('Post'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(published, hasLength(1));
    });
  });

  group('a draft that may already be out', () {
    testWidgets('warns instead of offering Post', (tester) async {
      await pumpSection(
        tester,
        drafts: [draft(publishAttemptedAt: DateTime.now())],
      );

      expect(
        find.textContaining('This may already have posted'),
        findsOneWidget,
      );
      // Discard leads; posting again is demoted to the overflow menu.
      expect(find.widgetWithText(FilledButton, 'Post'), findsNothing);
      expect(find.text('Discard'), findsOneWidget);
    });
  });

  group('discarding', () {
    testWidgets('asks first, and keeps the run if the answer is no',
        (tester) async {
      final harness = await pumpSection(tester, drafts: [draft()]);

      await tapIn(tester, find.byIcon(Icons.more_horiz_rounded));
      await tapIn(tester, find.text('Discard').last);

      expect(find.textContaining('Discard this run?'), findsOneWidget);
      expect(harness.store.deleted, isEmpty);
    });
  });
}
