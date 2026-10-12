import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tracking/application/run_draft_providers.dart';
import '../data/workout_log_form_store.dart';
import '../domain/workout_log_form.dart';

/// The form store, filed under the signed-in user — rooted where the live
/// session and the run drafts are, for the reasons given on
/// [runStorageRootProvider] and [runDraftOwnerProvider].
final workoutLogFormStoreProvider = Provider<WorkoutLogFormStore>((ref) {
  final userId = ref.watch(runDraftOwnerProvider);
  if (kIsWeb || userId == null) return const NoopWorkoutLogFormStore();
  return FileWorkoutLogFormStore(
    rootDirectory: ref.watch(runStorageRootProvider),
    userId: userId,
  );
});

/// The Log Workout form that has not been saved, or null when there is none.
///
/// Read by the form itself, to pick up where it was left; by the shell's
/// resume banner; and by the background notice that says it is waiting.
final workoutLogFormProvider =
    StateNotifierProvider<WorkoutLogFormController, WorkoutLogForm?>((ref) {
  return WorkoutLogFormController(ref.watch(workoutLogFormStoreProvider));
});

/// Owns the unsaved form: in memory at once, on disk shortly after.
///
/// The write trails the typing by [debounce] so a burst of keystrokes is one
/// file write rather than one per character. [flush] writes it now, for the
/// moments that cannot wait — the app leaving the screen, the screen closing.
class WorkoutLogFormController extends StateNotifier<WorkoutLogForm?> {
  WorkoutLogFormController(
    this._store, {
    this.debounce = const Duration(milliseconds: 400),
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now,
        super(null) {
    ready = _restore();
  }

  final WorkoutLogFormStore _store;
  final Duration debounce;
  final DateTime Function() _now;

  /// Completes once any saved form has been read. The screen waits for it
  /// before deciding it is starting from blank.
  late final Future<void> ready;

  Timer? _timer;

  Future<void> _restore() async {
    final saved = await _store.read();
    if (!mounted || state != null) return;
    if (saved == null) return;
    if (!saved.hasContent || saved.isStale(_now())) {
      // Nothing worth offering back. Cleared so it is not read again.
      await _store.clear();
      return;
    }
    state = saved;
  }

  /// Records [form] as the unsaved state of the screen. An empty form is the
  /// same as none: nothing is left on disk for it.
  void update(WorkoutLogForm form) {
    if (!form.hasContent) {
      clear();
      return;
    }
    state = form;
    _timer?.cancel();
    _timer = Timer(debounce, _write);
  }

  /// Writes the pending form now rather than after the debounce.
  Future<void> flush() async {
    if (_timer?.isActive ?? false) {
      _timer!.cancel();
      await _write();
    }
  }

  /// The form was saved, or thrown away on purpose.
  void clear() {
    _timer?.cancel();
    _timer = null;
    if (mounted) state = null;
    unawaited(_store.clear());
  }

  Future<void> _write() async {
    _timer = null;
    final form = state;
    if (form == null) return;
    try {
      await _store.write(form);
    } catch (error) {
      // Logged and otherwise ignored, as the live session does: a full disk
      // must not stop somebody typing their workout in.
      debugPrint('Could not save the unsaved workout log: $error');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
