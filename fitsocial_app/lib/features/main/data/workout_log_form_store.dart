import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../tracking/data/atomic_file.dart';
import '../domain/workout_log_form.dart';

/// Where the Log Workout form is kept while it is being filled in.
abstract interface class WorkoutLogFormStore {
  /// The saved form, or null when there is none or it cannot be read. Never
  /// throws: a corrupt file costs the form, not the screen.
  Future<WorkoutLogForm?> read();

  Future<void> write(WorkoutLogForm form);

  Future<void> clear();
}

/// One JSON file per user, beside the live session's — and for the same
/// reasons as [FileActiveWorkoutStore]: documents rather than cache, written
/// atomically, every operation queued behind the last so a write can never
/// land after the clear that followed it.
class FileWorkoutLogFormStore implements WorkoutLogFormStore {
  FileWorkoutLogFormStore({
    required Future<Directory> Function() rootDirectory,
    required this.userId,
  }) : _rootDirectory = rootDirectory;

  final Future<Directory> Function() _rootDirectory;

  /// Filed per user, so one person's unsaved log is never offered to the next
  /// to sign in on the same phone.
  final String userId;

  Future<void> _pending = Future<void>.value();

  Future<File> _file() async {
    final root = await _rootDirectory();
    final directory = Directory('${root.path}/workout_log_form');
    await directory.create(recursive: true);
    return File('${directory.path}/$userId.json');
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _pending = _pending.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  Future<WorkoutLogForm?> read() {
    return _serialized(() async {
      try {
        final file = await _file();
        if (!await file.exists()) return null;
        return WorkoutLogForm.fromJson(jsonDecode(await file.readAsString()));
      } catch (error) {
        debugPrint('Could not read the unsaved workout log: $error');
        return null;
      }
    });
  }

  @override
  Future<void> write(WorkoutLogForm form) {
    return _serialized(() async {
      await writeFileAtomically(
        await _file(),
        utf8.encode(jsonEncode(form.toJson())),
      );
    });
  }

  @override
  Future<void> clear() {
    return _serialized(() async {
      try {
        final file = await _file();
        if (await file.exists()) await file.delete();
        final stray = File('${file.path}.tmp');
        if (await stray.exists()) await stray.delete();
      } catch (error) {
        debugPrint('Could not clear the unsaved workout log: $error');
      }
    });
  }
}

/// The web build's store, and the one tests get by default: nothing is kept.
class NoopWorkoutLogFormStore implements WorkoutLogFormStore {
  const NoopWorkoutLogFormStore();

  @override
  Future<WorkoutLogForm?> read() async => null;

  @override
  Future<void> write(WorkoutLogForm form) async {}

  @override
  Future<void> clear() async {}
}
