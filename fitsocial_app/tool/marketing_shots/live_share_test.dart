import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/activity_kind.dart';
import 'package:fitsocial_app/features/tracking/application/live_share_controller.dart';
import 'package:fitsocial_app/features/tracking/application/tracking_providers.dart';
import 'package:fitsocial_app/features/tracking/data/live_share_repository.dart';
import 'package:fitsocial_app/features/tracking/domain/live_activity_share.dart';
import 'package:fitsocial_app/features/tracking/presentation/live_activity_viewer_screen.dart';
import 'package:fitsocial_app/features/tracking/presentation/live_run_screen.dart';

import 'live_run_test.dart' show liveRun;
import 'shot_data.dart';
import 'shot_fakes.dart';
import 'shot_harness.dart';

class _Repo implements LiveShareRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Sharing already on, the link out.
class _Sharing extends LiveShareController {
  _Sharing()
      : super(
          repository: _Repo(),
          runStates: const Stream.empty(),
          currentRunState: liveRun,
          profile: () => siphoProfile,
        ) {
    state = LiveShareState(
        session: LiveShareSession(id: 'ls-1', link: Uri.parse('https://fitsocial.app/live/ls-1')));
  }
}

LiveActivityShare siphoFinished() {
  final route = durbanBeachfront();
  final now = DateTime.now();
  return LiveActivityShare(
    id: 'ls-1',
    authorId: 'u-sipho',
    authorName: 'Sipho Ndlovu',
    kind: ActivityKind.run,
    phase: LiveSharePhase.ended,
    startedAt: now.subtract(const Duration(minutes: 70)),
    updatedAt: now.subtract(const Duration(minutes: 5)),
    endedAt: now.subtract(const Duration(minutes: 5)),
    expiresAt: now.add(const Duration(hours: 2)),
    distanceKm: 11.8,
    elapsed: const Duration(hours: 1, minutes: 4, seconds: 54),
    paceLabel: '5:30',
    isPaused: false,
    trail: route,
    position: route.last,
  );
}

LiveActivityShare siphoLive() {
  final route = durbanBeachfront();
  final trail = route.take((route.length * 0.42).round()).toList();
  final now = DateTime.now();
  return LiveActivityShare(
    id: 'ls-1',
    authorId: 'u-sipho',
    authorName: 'Sipho Ndlovu',
    kind: ActivityKind.run,
    phase: LiveSharePhase.live,
    startedAt: now.subtract(const Duration(minutes: 23, seconds: 5)),
    updatedAt: now.subtract(const Duration(seconds: 4)),
    expiresAt: now.add(const Duration(hours: 3)),
    distanceKm: 4.21,
    elapsed: const Duration(minutes: 23, seconds: 5),
    paceLabel: '5:29',
    isPaused: false,
    trail: trail,
    position: trail.last,
  );
}

void main() {
  testWidgets('sharing on', (tester) async {
    await shoot(tester, 'live_sharing',
        shotApp(const LiveRunScreen(), pushed: true, overrides: [
          ...signedIn(),
          liveRunStateProvider.overrideWith((ref) => Stream.value(liveRun())),
          liveShareControllerProvider.overrideWith((ref) => _Sharing()),
        ]));
  });

  testWidgets('viewer', (tester) async {
    await shoot(tester, 'live_viewer',
        shotApp(const LiveActivityViewerScreen(shareId: 'ls-1'), pushed: true, overrides: [
          ...signedIn(me: 'u-ayanda'),
          liveActivityShareProvider.overrideWith((ref, id) => Stream.value(siphoLive())),
        ]));
  });

  testWidgets('viewer finished', (tester) async {
    await shoot(tester, 'live_viewer_done',
        shotApp(const LiveActivityViewerScreen(shareId: 'ls-1'), pushed: true, overrides: [
          ...signedIn(me: 'u-ayanda'),
          liveActivityShareProvider.overrideWith((ref, id) => Stream.value(siphoFinished())),
        ]));
  });
}
