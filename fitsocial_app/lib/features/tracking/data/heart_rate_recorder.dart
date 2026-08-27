import 'dart:async';

import '../../main/domain/app_models.dart';

/// Reduces a session's worth of live BPM readings to one [HeartRateSummary].
///
/// Deliberately knows nothing about Bluetooth: it takes a `Stream<int>`, so the
/// connection can drop and reconnect underneath it without the recorder
/// noticing, and a test can drive it from a plain [StreamController].
///
/// The average is weighted by *time*, not by sample count. Straps notify at
/// roughly 1 Hz but BLE delivery bunches, so a plain `sum / count` quietly
/// over-weights whichever stretch happened to arrive fastest. Each reading is
/// instead credited for the time until the next one — capped at [staleAfter],
/// which is what keeps a strap that stopped reporting from being counted as
/// though it had held its last figure for the rest of the run.
///
/// That cap is doing more work than it looks. It handles a dropped connection
/// without being told about one, and it equally handles the case no connection
/// check would catch: a strap still nominally connected that has stopped
/// sending — a dry electrode, a loosened band. Both simply stop contributing.
class HeartRateRecorder {
  HeartRateRecorder({
    DateTime Function()? now,
    this.staleAfter = const Duration(seconds: 15),
  }) : _now = now ?? DateTime.now;

  /// How long a single reading may stand in for the heart rate before it is
  /// treated as stale. Banked the way [MovingTimeClock] banks its idle grace:
  /// a four-minute silence credits fifteen seconds and nothing more.
  final Duration staleAfter;

  final DateTime Function() _now;

  StreamSubscription<int>? _sub;

  /// BPM-seconds accumulated across closed intervals.
  double _weightedSum = 0;

  /// Time those intervals covered.
  Duration _covered = Duration.zero;

  int _maxBpm = 0;

  /// The reading waiting to be credited, and when it arrived. Null between
  /// sessions, while paused, and after a lapse has been closed out.
  int? _openBpm;
  DateTime? _openedAt;

  bool _isRecording = false;

  /// Readings outside this range are artifacts rather than heart rates — 255 in
  /// particular is common when a strap loses skin contact. They are dropped
  /// before they can reach [maxBpm], which has no averaging to dilute a spike.
  static const _minPlausibleBpm = 25;
  static const _maxPlausibleBpm = 240;

  /// The summary as it stands, including the interval still open.
  HeartRateSummary get summary {
    final covered = _covered + _openInterval(_now());
    if (covered <= Duration.zero) return HeartRateSummary.none;
    final weighted = _weightedSum + _openWeight(_now());
    return HeartRateSummary(
      averageBpm: (weighted / covered.inMilliseconds * 1000).round(),
      maxBpm: _maxBpm,
      coverage: covered,
    );
  }

  /// Discards any previous session and begins recording [source].
  void start(Stream<int> source) {
    _reset();
    _isRecording = true;
    _sub = source.listen(
      _add,
      // A stream that ends or fails has not un-recorded what it already
      // delivered; close the open interval so the run keeps what it earned
      // rather than leaving a reading dangling against a clock still running.
      onDone: () => _close(_now()),
      onError: (Object _) => _close(_now()),
    );
  }

  /// Stops crediting time — a paused run, or one the GPS auto-paused.
  ///
  /// Standing at a crossing with a heart rate coasting down is not part of the
  /// run, and counting it would drag the average below what was actually run.
  void pause() {
    if (!_isRecording) return;
    _isRecording = false;
    _close(_now());
  }

  void resume() => _isRecording = true;

  /// Closes the session and returns what it recorded.
  ///
  /// Idempotent: calling it twice returns the same summary rather than
  /// extending coverage to the second call.
  HeartRateSummary stop() {
    _close(_now());
    _isRecording = false;
    _sub?.cancel();
    _sub = null;
    return summary;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  void _add(int bpm) {
    if (!_isRecording) return;
    if (bpm < _minPlausibleBpm || bpm > _maxPlausibleBpm) return;
    final at = _now();
    // Close the previous reading at this instant, then open this one. A gap
    // longer than staleAfter closes short, and the time in between is simply
    // not covered — neither averaged in nor filled with a guess.
    _close(at);
    if (bpm > _maxBpm) _maxBpm = bpm;
    _openBpm = bpm;
    _openedAt = at;
  }

  /// Banks the open reading, crediting it up to [at] but never past its grace.
  void _close(DateTime at) {
    final interval = _openInterval(at);
    if (interval > Duration.zero) {
      _weightedSum += _openBpm! * interval.inMilliseconds / 1000;
      _covered += interval;
    }
    _openBpm = null;
    _openedAt = null;
  }

  Duration _openInterval(DateTime at) {
    final opened = _openedAt;
    if (opened == null || _openBpm == null) return Duration.zero;
    final elapsed = at.difference(opened);
    if (elapsed <= Duration.zero) return Duration.zero;
    return elapsed > staleAfter ? staleAfter : elapsed;
  }

  double _openWeight(DateTime at) {
    final bpm = _openBpm;
    if (bpm == null) return 0;
    return bpm * _openInterval(at).inMilliseconds / 1000;
  }

  void _reset() {
    _sub?.cancel();
    _sub = null;
    _weightedSum = 0;
    _covered = Duration.zero;
    _maxBpm = 0;
    _openBpm = null;
    _openedAt = null;
  }
}
