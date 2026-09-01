import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/run_draft.dart';
import 'atomic_file.dart';

/// Where finished-but-unsent runs live between the finish sheet and the day
/// there is a connection to publish them over.
abstract interface class RunDraftStore {
  /// Newest first. Unreadable files are skipped, never thrown over.
  Future<List<RunDraft>> list();

  /// Writes [draft], first copying [sourcePhotoPath] into the drafts
  /// directory so the saved run keeps its backdrop after the picker's cache
  /// is evicted. Returns the draft as stored, whose `photoPath` points at the
  /// copy.
  Future<RunDraft> save(RunDraft draft, {String? sourcePhotoPath});

  /// Records that a publish is about to be attempted. See
  /// [RunDraft.publishAttemptedAt].
  Future<void> markPublishAttempted(RunDraft draft);

  /// Removes the draft and its photo together.
  Future<void> delete(String id);

  /// Everything for this user — for account deletion.
  Future<void> clearAll();
}

/// One JSON file per draft, plus its photo alongside, under the app's
/// documents directory.
///
/// Documents rather than cache, because the cache directory is exactly what
/// the OS reclaims under pressure, and a run recorded on a flight has to still
/// be there a day later. Files rather than a database, because this holds a
/// handful of records that are always read all at once — a schema and a
/// migration story would cost more than they bought.
class FileRunDraftStore implements RunDraftStore {
  FileRunDraftStore({
    required Future<Directory> Function() rootDirectory,
    required this.userId,
  }) : _rootDirectory = rootDirectory;

  /// Injected so tests can hand over a temp directory and never go near
  /// path_provider's platform channel.
  final Future<Directory> Function() _rootDirectory;

  /// Drafts are filed per user: a phone can be shared, and a draft has to wait
  /// for its own author to come back rather than showing up in someone else's
  /// list.
  final String userId;

  Future<Directory>? _directory;

  /// Every write goes through this chain, so a save can never interleave with
  /// the delete or the sweep and leave a half-written directory.
  Future<void> _pending = Future<void>.value();

  Future<Directory> _ensureDirectory() {
    return _directory ??= () async {
      final root = await _rootDirectory();
      final directory = Directory('${root.path}/run_drafts/$userId');
      await directory.create(recursive: true);
      await _sweepOrphans(directory);
      return directory;
    }();
  }

  /// Clears anything a half-finished write or delete left behind: a `.tmp`
  /// that never got renamed, or a photo whose draft is gone. Runs once, when
  /// the directory is first resolved.
  Future<void> _sweepOrphans(Directory directory) async {
    try {
      final entries = await directory.list().toList();
      final draftIds = entries
          .whereType<File>()
          .map((file) => _idOf(file, '.json'))
          .whereType<String>()
          .toSet();

      for (final entry in entries.whereType<File>()) {
        final path = entry.path;
        final isStrayTemp = path.endsWith('.tmp');
        final photoId = _idOf(entry, '.jpg');
        final isStrayPhoto = photoId != null && !draftIds.contains(photoId);
        if (isStrayTemp || isStrayPhoto) {
          await entry.delete().catchError((Object _) => entry);
        }
      }
    } catch (error) {
      // A sweep is tidying, not a precondition. Failing it must not stop the
      // drafts themselves from being readable.
      debugPrint('Could not sweep the run drafts directory: $error');
    }
  }

  static String? _idOf(File file, String extension) {
    final name = file.uri.pathSegments.last;
    if (!name.endsWith(extension)) return null;
    return name.substring(0, name.length - extension.length);
  }

  File _draftFile(Directory directory, String id) =>
      File('${directory.path}/$id.json');

  File _photoFile(Directory directory, String id) =>
      File('${directory.path}/$id.jpg');

  /// Queues [action] behind whatever else is writing, and hands back its
  /// result.
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
  Future<List<RunDraft>> list() async {
    final directory = await _ensureDirectory();
    final drafts = <RunDraft>[];

    await for (final entry in directory.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      try {
        final draft = RunDraft.fromJson(
          jsonDecode(await entry.readAsString()),
        );
        if (draft != null) {
          drafts.add(draft);
        } else {
          debugPrint('Skipped an unreadable run draft at ${entry.path}.');
        }
      } catch (error) {
        debugPrint('Could not read the run draft at ${entry.path}: $error');
      }
    }

    drafts.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return List.unmodifiable(drafts);
  }

  @override
  Future<RunDraft> save(RunDraft draft, {String? sourcePhotoPath}) {
    return _serialized(() async {
      final directory = await _ensureDirectory();

      // The photo is copied *before* the JSON that names it is written, so a
      // draft file that exists always points at a photo that existed. The
      // other order leaves a draft advertising a picture that was never there.
      var stored = draft;
      if (sourcePhotoPath != null) {
        final destination = _photoFile(directory, draft.id);
        try {
          await File(sourcePhotoPath).copy(destination.path);
          stored = draft.copyWith(photoPath: destination.path);
        } catch (error) {
          // Never lose a run over a picture — the same trade the save path
          // already makes when a backdrop upload fails.
          debugPrint('Could not copy the run draft photo: $error');
          stored = draft.copyWith(clearPhotoPath: true, photoUnavailable: true);
        }
      }

      await writeFileAtomically(
        _draftFile(directory, stored.id),
        utf8.encode(jsonEncode(stored.toJson())),
      );
      return stored;
    });
  }

  @override
  Future<void> markPublishAttempted(RunDraft draft) {
    return _serialized(() async {
      final directory = await _ensureDirectory();
      final stamped = draft.copyWith(publishAttemptedAt: DateTime.now());
      await writeFileAtomically(
        _draftFile(directory, draft.id),
        utf8.encode(jsonEncode(stamped.toJson())),
      );
    });
  }

  @override
  Future<void> delete(String id) {
    return _serialized(() async {
      final directory = await _ensureDirectory();
      for (final file in [
        _draftFile(directory, id),
        _photoFile(directory, id),
      ]) {
        try {
          if (await file.exists()) await file.delete();
        } catch (error) {
          debugPrint('Could not delete ${file.path}: $error');
        }
      }
    });
  }

  @override
  Future<void> clearAll() {
    return _serialized(() async {
      final directory = await _ensureDirectory();
      try {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      } catch (error) {
        debugPrint('Could not clear the run drafts directory: $error');
      }
      // Resolved again — and recreated — on the next call.
      _directory = null;
    });
  }
}

/// The web build's store: there is nowhere durable to put a draft there.
///
/// `getApplicationDocumentsDirectory` has no web implementation and dart:io's
/// `File` is a throwing stub, and a photo picked on web is a `blob:` URL that
/// dies with the page — so a durable draft is not merely unimplemented there,
/// it is not possible. Web keeps the online save path and lets Firestore's own
/// persistence carry an offline write.
class NoopRunDraftStore implements RunDraftStore {
  const NoopRunDraftStore();

  @override
  Future<List<RunDraft>> list() async => const [];

  @override
  Future<RunDraft> save(RunDraft draft, {String? sourcePhotoPath}) {
    throw UnsupportedError('Run drafts are not available on the web.');
  }

  @override
  Future<void> markPublishAttempted(RunDraft draft) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> clearAll() async {}
}
