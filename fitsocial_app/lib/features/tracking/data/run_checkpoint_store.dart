import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../main/domain/activity_kind.dart';
import 'atomic_file.dart';
import 'live_run_service.dart' show RunPoint;

/// How old a checkpoint may be and still be worth offering back.
///
/// A run the app died in the middle of half a day ago is not going to be
/// resumed, and asking about it on every launch is noise. Six hours covers an
/// ultra and a very long lunch.
const Duration kRunCheckpointMaxAge = Duration(hours: 6);

/// A live run, frozen mid-stride, so an OS kill costs at most the last few
/// seconds instead of the whole thing.
///
/// Deliberately not a snapshot of [MovingTimeClock]'s internals: only its
/// settled [movingElapsed] is kept. Restoring an open stretch would bank the
/// wall time the process spent dead as time the runner spent moving.
class RunCheckpoint {
  const RunCheckpoint({
    required this.startedAt,
    required this.savedAt,
    required this.distanceMeters,
    required this.movingElapsed,
    required this.isPaused,
    required this.points,
    this.activityKind = ActivityKind.run,
    this.elevationGainMeters = 0,
    Duration? totalElapsed,
  }) : totalElapsed = totalElapsed ?? movingElapsed;

  static const int schemaVersion = 1;

  final DateTime startedAt;

  /// When this checkpoint was written — how [isStale] is judged.
  final DateTime savedAt;

  final double distanceMeters;
  final Duration movingElapsed;

  /// The run's duration — wall time since the start, manual pauses taken out.
  /// The number on the headline clock, so it has to survive a kill just as
  /// [movingElapsed] does. Defaults to [movingElapsed] for checkpoints written
  /// before the two came apart.
  final Duration totalElapsed;

  final bool isPaused;
  final List<RunPoint> points;

  /// Climb banked so far, in metres. Zero for checkpoints written before
  /// elevation was measured, which is also the right answer for a phone that
  /// never reported an altitude.
  final double elevationGainMeters;

  /// What was being recorded, so a recovered session resumes under its own GPS
  /// tuning and is offered back by the right name. Defaults to a run, which is
  /// what every checkpoint written before the field existed holds.
  final ActivityKind activityKind;

  double get distanceKm => distanceMeters / 1000;

  bool get isStale => DateTime.now().difference(savedAt) > kRunCheckpointMaxAge;

  /// Whether there is enough here to be worth offering back at all. The live
  /// run screen discards runs under 50 m; a checkpoint below that is not a run
  /// someone lost, it is a run someone never started.
  bool get isWorthRecovering => distanceMeters >= 50 && points.length >= 2;

  Map<String, dynamic> toJson() {
    return {
      'v': schemaVersion,
      'startedAt': startedAt.toIso8601String(),
      'savedAt': savedAt.toIso8601String(),
      'distanceMeters': distanceMeters,
      'movingSeconds': movingElapsed.inSeconds,
      'totalSeconds': totalElapsed.inSeconds,
      'isPaused': isPaused,
      // Written only when it is not a run, so an ordinary run's checkpoint
      // stays byte-for-byte what it has always been — and an older build
      // reading a newer file recovers the session as a run rather than
      // rejecting it. Same reason the schema version does not move: fromJson
      // discards any file whose version it does not recognise, and a bump
      // would throw away every unsaved run sitting on a phone mid-upgrade.
      if (activityKind != ActivityKind.run)
        'activityKind': activityKind.wireName,
      if (elevationGainMeters > 0) 'elevationGainMeters': elevationGainMeters,
      // Triples rather than {lat, lng, ts} maps: this file is rewritten every
      // twenty seconds, and a four-thousand-point run is about 130 KB this way
      // against 400 KB as maps. The timestamp stays because the rolling pace
      // needs it after a restore.
      'points': points
          .map((p) => [
                p.latitude,
                p.longitude,
                p.timestamp.millisecondsSinceEpoch,
              ])
          .toList(growable: false),
    };
  }

  /// Null for anything unreadable — a truncated or foreign file must read as
  /// "nothing to recover", never as a crash on launch.
  static RunCheckpoint? fromJson(Object? value) {
    if (value is! Map) return null;
    if ((value['v'] as num?)?.toInt() != schemaVersion) return null;

    final startedAt = DateTime.tryParse(value['startedAt'] as String? ?? '');
    final savedAt = DateTime.tryParse(value['savedAt'] as String? ?? '');
    if (startedAt == null || savedAt == null) return null;

    final distance = (value['distanceMeters'] as num?)?.toDouble();
    final seconds = (value['movingSeconds'] as num?)?.toInt();
    if (distance == null || seconds == null || seconds < 0) return null;
    // Absent in files written before the duration clock existed, and in that
    // case moving time is the best answer available — never null, so a good
    // checkpoint is never thrown away over a field it predates.
    final totalSeconds = (value['totalSeconds'] as num?)?.toInt();

    return RunCheckpoint(
      startedAt: startedAt,
      savedAt: savedAt,
      distanceMeters: distance,
      movingElapsed: Duration(seconds: seconds),
      totalElapsed: totalSeconds == null || totalSeconds < 0
          ? null
          : Duration(seconds: totalSeconds),
      isPaused: value['isPaused'] as bool? ?? false,
      activityKind: ActivityKindX.fromWire(value['activityKind']),
      elevationGainMeters:
          (value['elevationGainMeters'] as num?)?.toDouble() ?? 0,
      points: _pointsFrom(value['points']),
    );
  }

  static List<RunPoint> _pointsFrom(Object? value) {
    if (value is! List) return const [];
    final points = <RunPoint>[];
    for (final entry in value) {
      if (entry is! List || entry.length < 3) continue;
      // Typed rather than cast: a damaged file must cost the fix it damaged,
      // not the whole trace.
      if (entry[0] is! num || entry[1] is! num || entry[2] is! num) continue;
      final lat = (entry[0] as num).toDouble();
      final lng = (entry[1] as num).toDouble();
      if (lat.abs() > 90 || lng.abs() > 180) continue;
      points.add(RunPoint(
        latitude: lat,
        longitude: lng,
        // UTC so a decoded fix is the same DateTime it went in as, not just
        // the same instant wearing the device's current offset.
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (entry[2] as num).toInt(),
          isUtc: true,
        ),
      ));
    }
    return List.unmodifiable(points);
  }
}

/// The single slot holding whatever run is currently in progress.
abstract interface class RunCheckpointStore {
  Future<RunCheckpoint?> read();
  Future<void> write(RunCheckpoint checkpoint);
  Future<void> clear();
}

/// One file, overwritten in place, next to the run drafts.
///
/// One slot rather than a list because there is only ever one live run: the
/// tracking service is a singleton and starting a second run replaces the
/// first.
class FileRunCheckpointStore implements RunCheckpointStore {
  FileRunCheckpointStore({
    required Future<Directory> Function() rootDirectory,
    required this.userId,
  }) : _rootDirectory = rootDirectory;

  final Future<Directory> Function() _rootDirectory;
  final String userId;

  Future<File>? _file;

  /// Writes are chained so the twenty-second timer and the lifecycle write
  /// that fires when the app is backgrounded cannot land on top of each other.
  Future<void> _pending = Future<void>.value();

  Future<File> _ensureFile() {
    return _file ??= () async {
      final root = await _rootDirectory();
      final directory = Directory('${root.path}/run_drafts/$userId');
      await directory.create(recursive: true);
      return File('${directory.path}/in_progress.json');
    }();
  }

  @override
  Future<RunCheckpoint?> read() async {
    try {
      final file = await _ensureFile();
      if (!await file.exists()) return null;
      return RunCheckpoint.fromJson(jsonDecode(await file.readAsString()));
    } catch (error) {
      debugPrint('Could not read the run checkpoint: $error');
      return null;
    }
  }

  @override
  Future<void> write(RunCheckpoint checkpoint) {
    return _pending = _pending.then((_) async {
      try {
        await writeFileAtomically(
          await _ensureFile(),
          utf8.encode(jsonEncode(checkpoint.toJson())),
        );
      } catch (error) {
        // A failed checkpoint costs crash-recovery for this run, nothing more.
        // It must never surface into a run in progress.
        debugPrint('Could not write the run checkpoint: $error');
      }
    });
  }

  @override
  Future<void> clear() {
    return _pending = _pending.then((_) async {
      try {
        final file = await _ensureFile();
        if (await file.exists()) await file.delete();
      } catch (error) {
        debugPrint('Could not clear the run checkpoint: $error');
      }
    });
  }
}

/// Web has no durable storage here and no background GPS to recover. See
/// [NoopRunDraftStore].
class NoopRunCheckpointStore implements RunCheckpointStore {
  const NoopRunCheckpointStore();

  @override
  Future<RunCheckpoint?> read() async => null;

  @override
  Future<void> write(RunCheckpoint checkpoint) async {}

  @override
  Future<void> clear() async {}
}
