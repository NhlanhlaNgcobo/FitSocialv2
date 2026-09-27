import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/activity_kind.dart';
import 'package:fitsocial_app/features/main/presentation/create_screen.dart';
import 'package:fitsocial_app/features/tracking/application/run_draft_providers.dart';
import 'package:fitsocial_app/features/tracking/application/tracking_providers.dart';
import 'package:fitsocial_app/features/tracking/data/run_draft_store.dart';
import 'package:fitsocial_app/features/tracking/data/run_import_ledger.dart';
import 'package:fitsocial_app/features/tracking/data/treadmill_run_service.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/tracking/domain/run_draft.dart';
import 'package:fitsocial_app/features/tracking/presentation/finish_run_sheet.dart';
import 'package:fitsocial_app/features/tracking/presentation/live_run_map_screen.dart';
import 'package:fitsocial_app/features/tracking/presentation/treadmill_run_screen.dart';

import 'live_run_test.dart' show liveRun;
import 'shot_data.dart';
import 'shot_fakes.dart';
import 'shot_harness.dart';

/// A run a watch recorded this morning, waiting in Create.
class _Drafts implements RunDraftStore {
  @override
  Future<List<RunDraft>> list() async {
    final start = DateTime.now().subtract(const Duration(hours: 3));
    return [
      RunDraft(
        id: 'hc-1',
        savedAt: start.add(const Duration(minutes: 50)),
        distanceKm: 8.42,
        elapsed: const Duration(minutes: 46, seconds: 18),
        averagePace: '5:30',
        shareToFeed: false,
        startedAt: start,
        source: RunDraftSource.healthConnect,
        externalId: 'hc-session-1',
        heartRate: const HeartRateSummary(
            averageBpm: 152, maxBpm: 176, coverage: Duration(minutes: 46)),
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FinishHost extends StatefulWidget {
  const _FinishHost();
  @override
  State<_FinishHost> createState() => _FinishHostState();
}

class _FinishHostState extends State<_FinishHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showFinishRunSheet(
        context: context,
        route: durbanBeachfront(),
        distanceLabel: '11.8 km',
        durationLabel: '1:04:54',
        paceLabel: '5:30 /km',
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}

void main() {
  testWidgets('live map', (tester) async {
    await shoot(tester, 'live_map',
        shotApp(const LiveRunMapScreen(kind: ActivityKind.run), pushed: true, overrides: [
          ...signedIn(),
          liveRunStateProvider.overrideWith((ref) => Stream.value(liveRun())),
        ]));
  });

  testWidgets('finish sheet', (tester) async {
    await shoot(tester, 'finish_run', shotApp(const _FinishHost(), overrides: signedIn()));
  });

  testWidgets('finish sheet saved', (tester) async {
    await shoot(tester, 'finish_run_save', shotApp(const _FinishHost(), overrides: signedIn()),
        before: (t) async {
      final p = mainScroll(t);
      p.jumpTo(p.maxScrollExtent);
      await t.pump(const Duration(milliseconds: 200));
    });
  });

  testWidgets('finish clip', (tester) async {
    await shootFrames(tester, 'clip_finish_scroll',
        shotApp(const _FinishHost(), overrides: signedIn()),
        count: 96, step: (t, i, v) async {
      final p = mainScroll(t);
      final k = ((i - 18) / 60).clamp(0.0, 1.0);
      p.jumpTo(p.maxScrollExtent * Curves.easeInOutCubic.transform(k));
      await t.pump(const Duration(microseconds: 33333));
    });
  });

  testWidgets('treadmill', (tester) async {
    await shoot(tester, 'treadmill',
        shotApp(const TreadmillRunScreen(), pushed: true, overrides: [
          ...signedIn(),
          treadmillRunStateProvider.overrideWith((ref) => Stream.value(TreadmillRunState(
                isTracking: true,
                isPaused: false,
                elapsed: const Duration(minutes: 28, seconds: 40),
                distanceKm: 5.2,
                startedAt: DateTime.now().subtract(const Duration(minutes: 29)),
              ))),
        ]));
  });

  testWidgets('create drafts', (tester) async {
    await shoot(tester, 'create_drafts',
        shotApp(const CreateScreen(), pushed: true, overrides: [
          ...signedIn(),
          runDraftStoreProvider.overrideWithValue(_Drafts()),
          runImportLedgerProvider.overrideWithValue(const NoopRunImportLedger()),
        ]));
  });
}
