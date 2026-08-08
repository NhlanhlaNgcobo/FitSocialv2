import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/username_repository_contract.dart';
import '../domain/username.dart';

/// Answers "is this username free?" while someone types it.
///
/// Two screens ask the same question of the same collection and render the
/// same three states, so the debouncing, the race handling and the
/// format-before-network shortcut live here once rather than twice.
///
/// The answer is always advisory. Between this check and the save, someone
/// else can commit the same name; the transaction behind the save is what
/// actually decides. What this buys is telling people early, not telling them
/// authoritatively.
class UsernameAvailabilityChecker extends ChangeNotifier {
  UsernameAvailabilityChecker(this._repository);

  final UsernameRepository _repository;

  /// Long enough that ordinary typing produces one lookup rather than one per
  /// keystroke, short enough that the answer feels like a reaction to what was
  /// typed rather than a later interruption.
  static const Duration _debounce = Duration(milliseconds: 400);

  Timer? _timer;
  bool _isChecking = false;
  String _checkedValue = '';
  UsernameAvailability? _result;

  /// The value waiting on the debounce, and the lookup already running. Kept
  /// so [settle] can finish what [check] started instead of waiting out a
  /// delay that only exists to spare the network.
  String? _queued;
  Future<void>? _inFlight;

  /// The edit sheet builds a checker per opening and disposes it on close, so
  /// a lookup can still be in flight when this object goes away. Notifying
  /// after that throws, and the answer is no longer wanted anyway.
  bool _disposed = false;

  /// Distinguishes replies to the current keystroke from replies to an
  /// abandoned one. Without it a slow lookup for "bea" can land after a fast
  /// one for "bear" and overwrite the newer, correct answer.
  int _generation = 0;

  bool get isChecking => _isChecking;

  /// The verdict on the last settled value, or null before anything has been
  /// checked. Null is what tells the UI to show no hint at all, which is the
  /// right state for an untouched field.
  UsernameAvailability? get result => _result;

  /// Whether the field currently holds something saveable.
  ///
  /// Null while a check is outstanding: neither yes nor no is honest yet, and
  /// callers use it to keep the save button from committing to an answer that
  /// has not arrived.
  bool? get canUse => _isChecking ? null : _result?.canUse;

  /// Queues a check for [candidate], replacing any check already queued.
  ///
  /// A malformed username never reaches the network — the format rules already
  /// reject it, and spending a read to be told so would be slower and no more
  /// informative.
  void check(String candidate) {
    if (_disposed) return;
    _timer?.cancel();

    final username = normalizeUsername(candidate);
    if (username == _checkedValue && _result != null && !_isChecking) return;

    final formatError = validateUsernameFormat(username);
    if (formatError != null) {
      _generation++;
      _queued = null;
      _checkedValue = username;
      _isChecking = false;
      _result = UsernameAvailability.malformed(formatError);
      notifyListeners();
      return;
    }

    _queued = username;
    _isChecking = true;
    notifyListeners();

    _timer = Timer(_debounce, () {
      _timer = null;
      _inFlight = _run(username);
    });
  }

  /// Runs any queued check immediately and waits for the answer.
  ///
  /// The debounce exists to spare the network while someone types, and once
  /// they have pressed Save there is nothing left to spare it from. Without
  /// this the press would land inside the delay and be dropped — a button that
  /// does nothing, for reasons invisible to whoever pressed it.
  Future<void> settle() async {
    final queued = _queued;
    if (_timer != null && queued != null) {
      _timer!.cancel();
      _timer = null;
      _inFlight = _run(queued);
    }
    await _inFlight;
  }

  /// Drops any queued check and clears the hint.
  void reset() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    _queued = null;
    _generation++;
    _isChecking = false;
    _checkedValue = '';
    _result = null;
    notifyListeners();
  }

  Future<void> _run(String username) async {
    final generation = ++_generation;
    try {
      final availability = await _repository.checkAvailability(username);
      if (generation != _generation) return;
      _checkedValue = username;
      _result = availability;
    } catch (_) {
      if (generation != _generation) return;
      // Offline, or rules said no. Staying silent is the right failure: a red
      // "unavailable" would be a claim we cannot support, and the save still
      // refuses a genuine collision.
      _checkedValue = username;
      _result = null;
    } finally {
      if (generation == _generation && !_disposed) {
        _queued = null;
        _isChecking = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
