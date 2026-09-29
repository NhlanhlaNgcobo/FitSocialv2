import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tracking/application/tracking_providers.dart';
import '../domain/challenge_clock.dart';
import '../domain/daily_health.dart';
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

  /// The last correction written for yesterday, and the day it was written
  /// for. Kept so the same number is not rewritten on every tick, while a
  /// larger one — Health Connect having received another late batch in the
  /// meantime — still goes through.
  String? _backfilledDayKey;
  int _backfilledSteps = 0;

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

    // The day record only matters while something reads it: a Pulse 75 run,
    // or a Build 11 feature that is switched on. Early Worm does not ask for
    // steps, and writing a document a day for every user when nothing reads
    // it would be paying for data nobody uses.
    if (!ref.read(needsDailyHealthProvider)) return;

    try {
      final summary = await ref.read(healthServiceProvider).readTodaySummary();
      final steps = summary.steps;
      if (summary.available && steps != null && steps > 0) {
        final now = DateTime.now();
        await actions.recordDailyHealth(
          reading: await _readDay(
            DateTime(now.year, now.month, now.day),
            now,
            steps,
          ),
          source: 'health_connect',
        );
      }
    } catch (_) {
      // A failed sync is not worth surfacing: the next one is half an hour
      // away at worst, and there is nothing the user could do about it.
    }

    // Deliberately not inside the block above, and not behind its early
    // return: in the small hours today's count is legitimately zero, and
    // correcting yesterday is the whole reason to be awake at that time.
    try {
      await _backfillYesterday(actions);
    } catch (_) {
      // Same reasoning. Yesterday either gets corrected before 2 AM or closes
      // on the number it already has, which is the behaviour without this.
    }
  }

  /// Corrects yesterday's total while the day is still inside its 2 AM grace.
  ///
  /// Health Connect is not written to live. Samsung Health flushes into it in
  /// batches, so the last stretch of an evening's walking usually lands after
  /// the phone has been put down — and the reading the day would otherwise
  /// close on is short by exactly that much, permanently. After midnight the
  /// figure is both complete and still changeable, so it is read once more
  /// against yesterday's window and written under yesterday's key. The server
  /// recomputes yesterday alongside today on every step write, so a correction
  /// that arrives before the lock is picked up without any change there.
  ///
  /// This only helps somebody who opens the app between midnight and 2 AM, and
  /// that is on purpose. The version that always works is a background job at
  /// 01:30, which is the first thing aggressive battery management kills — it
  /// would fail most reliably on the devices with the worst lag.
  Future<void> _backfillYesterday(ChallengeActions actions) async {
    final now = DateTime.now();
    final clock = ref.read(challengeClockProvider);
    final dayKey = ChallengeClock.addDays(clock.today(now), -1);

    // The same predicate the lock is judged by, rather than a hand-rolled
    // "is it before 2 AM": outside the grace window there is nothing a write
    // could still change, and the server would drop it anyway.
    if (!clock.isOpen(dayKey, now)) return;

    // Yesterday in local wall-clock terms: the midnight that just passed, and
    // the one before it. Both are built as dates rather than by stepping back
    // 24 hours, because the day a zone shifts its clocks is 23 hours long or
    // 25 — and a window measured in elapsed time then either misses an hour of
    // yesterday's steps or reaches back into the day before.
    //
    // Health Connect is asked for its own de-duplicated total over that window
    // rather than for a summary, because the day is over — there is no "so far
    // today" left to read.
    final midnight = DateTime(now.year, now.month, now.day);
    final start = DateTime(now.year, now.month, now.day - 1);
    final steps =
        await ref.read(healthServiceProvider).readStepsBetween(start, midnight);

    if (!mounted || steps == null || steps <= 0) return;
    if (dayKey == _backfilledDayKey && steps <= _backfilledSteps) return;

    await actions.recordDailyHealth(
      reading: await _readDay(start, midnight, steps),
      source: 'health_connect_backfill',
      dayKey: dayKey,
    );
    _backfilledDayKey = dayKey;
    _backfilledSteps = steps;
  }

  /// The rest of a day's reading, around a step total already in hand.
  ///
  /// Each extra read fails on its own: a missing heart-rate permission, or a
  /// phone with no watch at all, must still leave the steps to be written.
  Future<DailyHealthReading> _readDay(
    DateTime start,
    DateTime end,
    int steps,
  ) async {
    final health = ref.read(healthServiceProvider);
    final manual = await health.readManualStepsBetween(start, end);
    final heartRate = await health.readHeartRateSummary(start: start, end: end);
    return DailyHealthReading(
      steps: steps,
      manualSteps: manual,
      avgHeartRate: heartRate?.averageBpm,
      maxHeartRate: heartRate?.maxBpm,
      heartRateCoverageMinutes: heartRate?.coverage.inMinutes,
      utcOffsetMinutes: ref.read(challengeClockProvider).utcOffsetMinutes,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
