import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/links/share_links.dart';
import '../../auth/application/app_session.dart';
import '../../auth/domain/auth_models.dart';
import '../../main/domain/activity_kind.dart';
import '../../main/domain/app_models.dart' show RoutePoint;
import '../data/live_run_service.dart';
import '../data/live_share_repository.dart';
import '../domain/live_activity_share.dart';
import 'tracking_providers.dart';

/// A share that is open: its id and the link that opens it.
@immutable
class LiveShareSession {
  const LiveShareSession({required this.id, required this.link});

  final String id;
  final Uri link;
}

@immutable
class LiveShareState {
  const LiveShareState({
    this.session,
    this.isStarting = false,
    this.errorMessage,
  });

  static const idle = LiveShareState();

  final LiveShareSession? session;

  /// Between the tap and the document existing — a network round trip, during
  /// which the button should neither be tappable again nor say it is sharing.
  final bool isStarting;

  /// Why the last attempt to start failed, for the screen to show. Cleared on
  /// the next attempt.
  final String? errorMessage;

  bool get isSharing => session != null;
}

/// Keeps a shared activity's document current while the activity is tracked.
///
/// Listens to the run tracker rather than being driven by the screen, so a
/// share carries on when the screen is behind the lock screen — which is
/// where it is for most of a run — and ends itself when the run does, whether
/// the runner remembered it was on or not.
///
/// Writes are rationed. The tracker emits about once a second; Firestore is
/// written at most once per [writeInterval], and only when something other
/// than the clock has moved, with a heartbeat every [heartbeatInterval] so a
/// runner standing at a crossing does not read as a phone that has died. The
/// viewer runs its own clock forward from the last write in between.
class LiveShareController extends StateNotifier<LiveShareState> {
  LiveShareController({
    required LiveShareRepository repository,
    required Stream<LiveRunState> runStates,
    required LiveRunState Function() currentRunState,
    required UserProfileDraft? Function() profile,
    DateTime Function()? now,
  })  : _repository = repository,
        _runStates = runStates,
        _currentRunState = currentRunState,
        _profile = profile,
        _now = now ?? DateTime.now,
        super(LiveShareState.idle);

  /// How often the tracker's latest state is considered for a write.
  static const Duration writeInterval = Duration(seconds: 5);

  /// The longest a live share goes without a write, whatever the tracker is
  /// doing. Comfortably inside [LiveActivityShare.staleAfter], which is the
  /// threshold the viewer judges lost contact by.
  static const Duration heartbeatInterval = Duration(seconds: 45);

  final LiveShareRepository _repository;
  final Stream<LiveRunState> _runStates;
  final LiveRunState Function() _currentRunState;
  final UserProfileDraft? Function() _profile;
  final DateTime Function() _now;

  StreamSubscription<LiveRunState>? _runSub;
  Timer? _ticker;

  ActivityKind _kind = ActivityKind.run;
  LiveShareSnapshot? _latest;
  LiveShareSnapshot? _lastWritten;
  DateTime? _lastWriteAt;
  bool _writeInFlight = false;

  /// Opens a share for the activity in progress and starts keeping it current.
  ///
  /// A no-op when one is already open, and when nothing is being tracked —
  /// there is no position to share before the run starts, and the button is
  /// not offered then either.
  Future<void> start(ActivityKind kind) async {
    if (state.isSharing || state.isStarting) return;
    final run = _currentRunState();
    if (!run.isTracking) return;

    state = const LiveShareState(isStarting: true);
    try {
      final id = await _repository.begin(
        kind: kind,
        startedAt: run.startedAt ?? _now(),
        profile: _profile(),
      );
      _kind = kind;
      _latest = _snapshotOf(run);
      _lastWritten = null;
      _lastWriteAt = null;
      state = LiveShareState(
        session: LiveShareSession(id: id, link: FitSocialLinks.live(id)),
      );
      // The first write goes straight away so the link has a position on it
      // by the time it has been pasted anywhere.
      await _flush();
      _runSub = _runStates.listen(_onRunState);
      _ticker = Timer.periodic(writeInterval, (_) => unawaited(_flush()));
    } catch (e) {
      state = LiveShareState(errorMessage: 'Could not start sharing: $e');
    }
  }

  /// Stops sharing mid-activity and removes the document, so the link shows
  /// nothing from here on. The activity itself carries on untouched.
  Future<void> stop() async {
    final session = state.session;
    if (session == null) return;
    _teardown();
    state = LiveShareState.idle;
    try {
      await _repository.discard(session.id);
    } catch (_) {
      // The document expires on its own. Nothing to tell the runner: the
      // share is over from their point of view either way.
    }
  }

  void _onRunState(LiveRunState run) {
    if (!run.isTracking) {
      // The run was finished (or discarded). The state that announces it
      // still carries the final numbers, so they go out as the closing write.
      unawaited(_finish(_snapshotOf(run)));
      return;
    }

    final previous = _latest;
    _latest = _snapshotOf(run);
    // A pause is worth telling the viewer about now rather than in up to five
    // seconds: it is the one change that explains a marker that has stopped.
    if (previous != null && previous.isPaused != _latest!.isPaused) {
      unawaited(_flush());
    }
  }

  /// Writes the latest snapshot if it is worth writing.
  Future<void> _flush() async {
    final session = state.session;
    final latest = _latest;
    if (session == null || latest == null || _writeInFlight) return;

    final lastWriteAt = _lastWriteAt;
    final due = lastWriteAt == null ||
        _now().difference(lastWriteAt) >= heartbeatInterval;
    if (!due && !latest.differsFrom(_lastWritten)) return;

    _writeInFlight = true;
    try {
      await _repository.update(session.id, latest);
      _lastWritten = latest;
      _lastWriteAt = _now();
    } catch (_) {
      // Left for the next tick. A share that misses a write is a marker that
      // is a few seconds behind, which is not worth interrupting a run over.
    } finally {
      _writeInFlight = false;
    }
  }

  Future<void> _finish(LiveShareSnapshot last) async {
    final session = state.session;
    if (session == null) return;
    _teardown();
    state = LiveShareState.idle;
    try {
      await _repository.end(session.id, last);
    } catch (_) {
      // Expiry closes it eventually; the viewer will see it go stale first.
    }
  }

  void _teardown() {
    _runSub?.cancel();
    _runSub = null;
    _ticker?.cancel();
    _ticker = null;
    _latest = null;
    _lastWritten = null;
    _lastWriteAt = null;
  }

  LiveShareSnapshot _snapshotOf(LiveRunState run) => LiveShareSnapshot(
        distanceKm: run.distanceKm,
        elapsed: run.elapsed,
        paceLabel: run.formattedAverageFor(_kind),
        isPaused: run.isPaused,
        route: run.points
            .map((p) => RoutePoint(latitude: p.latitude, longitude: p.longitude))
            .toList(growable: false),
      );

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}

final liveShareControllerProvider =
    StateNotifierProvider<LiveShareController, LiveShareState>((ref) {
  final runService = ref.watch(liveRunServiceProvider);
  return LiveShareController(
    repository: ref.watch(liveShareRepositoryProvider),
    runStates: runService.stream,
    currentRunState: () => runService.current,
    profile: () => ref.read(appSessionProvider).profile,
  );
});
