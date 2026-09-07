import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'atomic_file.dart';

/// Remembers which Health Connect sessions have already been dealt with.
///
/// The import rescans a fixed 48-hour window every time the app is opened,
/// because Health Connect is written in batches and a run that finished an hour
/// ago is often not there yet. That only works if the app can tell a session it
/// has already seen from one it has not — which is what this is.
///
/// The critical property is that an entry survives the draft being **discarded**.
/// A runner who imports a session and decides they do not want it must not have
/// it offered back on the next launch; without the ledger, discarding would be
/// indistinguishable from never having imported it, and the same unwanted run
/// would reappear every morning for two days.
abstract interface class RunImportLedger {
  /// The external ids already imported or dismissed.
  Future<Set<String>> handled();

  /// Records [externalIds] as dealt with. Adding an id already present is a
  /// no-op, not an error.
  Future<void> markHandled(Iterable<String> externalIds);
}

/// A single JSON file alongside the user's drafts.
///
/// Deliberately **not** a `.json` file: [FileRunDraftStore] treats every
/// `*.json` in that directory as a draft, and would spend a log line on this
/// one on every read. `.ledger` keeps them out of each other's way while
/// leaving both in the one place account deletion already clears.
class FileRunImportLedger implements RunImportLedger {
  FileRunImportLedger({
    required Future<Directory> Function() rootDirectory,
    required this.userId,
  }) : _rootDirectory = rootDirectory;

  final Future<Directory> Function() _rootDirectory;

  /// Same per-user filing as the drafts themselves: a shared phone must not
  /// have one runner's import history suppressing another's.
  final String userId;

  /// How long an id is remembered.
  ///
  /// Comfortably longer than the 48-hour scan window and than the 30 days
  /// Health Connect will serve without `READ_HEALTH_DATA_HISTORY`, so an entry
  /// is only ever dropped once the session behind it has become unreadable
  /// anyway. Without a prune this file grows for the life of the install.
  static const Duration retention = Duration(days: 60);

  static const int schemaVersion = 1;

  /// Writes are serialised, so two syncs racing on a resume cannot each read
  /// the file, add their own id, and write the other's away.
  Future<void> _pending = Future<void>.value();

  /// Resolved fresh each time rather than cached: account deletion removes this
  /// whole directory through [FileRunDraftStore.clearAll], and a cached handle
  /// would then point at a path that no longer exists.
  Future<File> _file() async {
    final root = await _rootDirectory();
    final directory = Directory('${root.path}/run_drafts/$userId');
    await directory.create(recursive: true);
    return File('${directory.path}/imported.ledger');
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

  /// The file as `{id: first seen}`. An unreadable file reads as empty.
  ///
  /// Empty rather than a throw, and the consequence is worth being explicit
  /// about: a lost ledger means already-imported sessions are offered again,
  /// which the overlap check against the runner's existing runs then catches
  /// for anything they actually posted. Duplicated offers are recoverable;
  /// refusing to import at all is not.
  Future<Map<String, DateTime>> _read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      if ((decoded['v'] as num?)?.toInt() != schemaVersion) return {};
      final entries = decoded['entries'];
      if (entries is! Map) return {};

      final result = <String, DateTime>{};
      entries.forEach((key, value) {
        if (key is! String || value is! String) return;
        final seenAt = DateTime.tryParse(value);
        if (seenAt != null) result[key] = seenAt;
      });
      return result;
    } catch (error) {
      debugPrint('Could not read the run import ledger: $error');
      return {};
    }
  }

  @override
  Future<Set<String>> handled() async {
    final entries = await _read();
    return entries.keys.toSet();
  }

  @override
  Future<void> markHandled(Iterable<String> externalIds) {
    return _serialized(() async {
      final ids = externalIds.toSet();
      if (ids.isEmpty) return;

      final now = DateTime.now();
      final entries = await _read();
      // First-seen is kept for ids already present: the prune should retire an
      // id a fixed time after it was dealt with, not keep refreshing it every
      // time the same session is rescanned.
      for (final id in ids) {
        entries.putIfAbsent(id, () => now);
      }
      entries.removeWhere((_, seenAt) => now.difference(seenAt) > retention);

      try {
        await writeFileAtomically(
          await _file(),
          utf8.encode(
            jsonEncode({
              'v': schemaVersion,
              'entries': entries.map(
                (id, seenAt) => MapEntry(id, seenAt.toIso8601String()),
              ),
            }),
          ),
        );
      } catch (error) {
        // Swallowed, like the checkpoint's writes. A ledger that failed to
        // save costs a repeated offer on the next launch; taking the import
        // down over it would cost the run.
        debugPrint('Could not write the run import ledger: $error');
      }
    });
  }
}

/// The web and signed-out ledger. Nothing is imported there, so nothing needs
/// remembering.
class NoopRunImportLedger implements RunImportLedger {
  const NoopRunImportLedger();

  @override
  Future<Set<String>> handled() async => const {};

  @override
  Future<void> markHandled(Iterable<String> externalIds) async {}
}
