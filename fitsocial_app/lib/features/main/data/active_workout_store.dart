import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../tracking/data/atomic_file.dart';
import '../domain/active_workout.dart';

/// Where the workout in progress is kept, so that a killed app can offer to
/// resume it instead of losing an hour of sets.
abstract interface class ActiveWorkoutStore {
  /// The saved session, or null when there is none or it cannot be read. Never
  /// throws: a corrupt file costs the session, not the screen.
  Future<ActiveWorkout?> read();

  Future<void> write(ActiveWorkout workout);

  Future<void> clear();
}

/// One JSON file per user, rewritten after every change.
///
/// Documents rather than cache, for the reason [FileRunDraftStore] gives — the
/// cache is what the OS reclaims under pressure. Written atomically, since the
/// moment this file matters is the moment the process was killed mid-write.
class FileActiveWorkoutStore implements ActiveWorkoutStore {
  FileActiveWorkoutStore({
    required Future<Directory> Function() rootDirectory,
    required this.userId,
  }) : _rootDirectory = rootDirectory;

  /// Injected so tests can hand over a temp directory.
  final Future<Directory> Function() _rootDirectory;

  /// Filed per user: a phone can be shared, and one person's half-finished
  /// workout must not be offered to the next to sign in.
  final String userId;

  /// Every operation queues behind the last, so a write can never land after
  /// the clear that was meant to follow it.
  Future<void> _pending = Future<void>.value();

  Future<File> _file() async {
    final root = await _rootDirectory();
    final directory = Directory('${root.path}/active_workout');
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
  Future<ActiveWorkout?> read() {
    return _serialized(() async {
      try {
        final file = await _file();
        if (!await file.exists()) return null;
        return ActiveWorkout.fromJson(jsonDecode(await file.readAsString()));
      } catch (error) {
        debugPrint('Could not read the saved workout: $error');
        return null;
      }
    });
  }

  @override
  Future<void> write(ActiveWorkout workout) {
    return _serialized(() async {
      await writeFileAtomically(
        await _file(),
        utf8.encode(jsonEncode(workout.toJson())),
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
        debugPrint('Could not clear the saved workout: $error');
      }
    });
  }
}

/// The web build's store. There is nowhere durable to put a session there, so
/// a refresh ends it — the same trade the run drafts make.
class NoopActiveWorkoutStore implements ActiveWorkoutStore {
  const NoopActiveWorkoutStore();

  @override
  Future<ActiveWorkout?> read() async => null;

  @override
  Future<void> write(ActiveWorkout workout) async {}

  @override
  Future<void> clear() async {}
}
