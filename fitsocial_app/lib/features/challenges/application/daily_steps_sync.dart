import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tracking/application/tracking_providers.dart';
import 'challenge_providers.dart';

/// Keeps a durable record of today's step count.
///
/// The steps task is the one automatic requirement with nothing on the server
/// to read. Workouts, runs, meals and Pulses are already Firestore documents by
/// the time the engine looks; steps live on the phone, and the job that closes
/// a day runs at 2 AM when the phone is asleep. So the number has to be pushed
/// while the app is awake.
///
/// Three moments cover it: on open, on returning to the foreground, and on a
/// slow timer while the app stays open. Writes are cheap — one document per
/// user per day, merged — and the repository keeps the highest value seen, so a
/// reading that comes back low cannot erase the day's walking.
class DailyStepsSync extends ConsumerStatefulWidget {
  const DailyStepsSync({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DailyStepsSync> createState() => _DailyStepsSyncState();
}

class _DailyStepsSyncState extends ConsumerState<DailyStepsSync>
    with WidgetsBindingObserver {
  Timer? _timer;

  /// The offset last written to the user's profile in this session. Kept so a
  /// clock that has not moved is not rewritten every half hour — the server
  /// needs the value to be current, not to be re-sent.
  int? _writtenOffset;

  /// Slow on purpose. A step count that is half an hour stale still closes the
  /// day correctly, and polling Health Connect harder would cost battery for
  /// a number nobody is watching tick.
  static const Duration _interval = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_interval, (_) => _sync());
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Both edges. Coming back is when the count has moved most; going away is
    // the last chance to record it before the phone is put down for the night,
    // which is exactly the walk that would otherwise be lost.
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.paused) {
      _sync();
    }
  }

  Future<void> _sync() async {
    final actions = ref.read(challengeActionsProvider);

    // The clock goes first and runs for everybody, challenge or not: Early
    // Worm asks whether a Pulse landed in the user's own 4-to-6 window, and the
    // server cannot answer that without knowing which zone they are in.
    final offset = ref.read(challengeClockProvider).utcOffsetMinutes;
    if (offset != _writtenOffset) {
      try {
        if (await actions.syncUserClock() != null) _writtenOffset = offset;
      } catch (_) {
        // Left unwritten; the next sync tries again. The server falls back to
        // the launch market's offset in the meantime.
      }
    }

    // The step record itself only matters while a run is going. Early Worm does
    // not ask for steps, and writing a document a day for every user who has
    // never entered a challenge would be paying for data nobody reads.
    if (!ref.read(hasRunningEnrollmentProvider)) return;

    try {
      final summary =
          await ref.read(healthServiceProvider).readTodaySummary();
      final steps = summary.steps;
      if (!summary.available || steps == null || steps <= 0) return;

      await actions.recordSteps(
            steps: steps,
            source: 'health_connect',
          );
    } catch (_) {
      // A failed sync is not worth surfacing: the next one is half an hour
      // away at worst, and there is nothing the user could do about it.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
