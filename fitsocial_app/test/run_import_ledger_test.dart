import 'dart:convert';
import 'dart:io';

import 'package:fitsocial_app/features/tracking/data/run_draft_store.dart';
import 'package:fitsocial_app/features/tracking/data/run_import_ledger.dart';
import 'package:fitsocial_app/features/tracking/domain/run_draft.dart';
import 'package:flutter_test/flutter_test.dart';

// A real temp directory, for the same reason the draft store's tests use one:
// what this class is for is what survives on disk after the process is gone.

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('run_ledger_test'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  FileRunImportLedger ledgerFor(String userId) => FileRunImportLedger(
        rootDirectory: () async => root,
        userId: userId,
      );

  File fileFor(String userId) =>
      File('${root.path}/run_drafts/$userId/imported.ledger');

  /// Writes the ledger directly, so an entry can be given an age.
  void seed(String userId, Map<String, DateTime> entries) {
    final file = fileFor(userId);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({
        'v': FileRunImportLedger.schemaVersion,
        'entries': entries.map(
          (id, seenAt) => MapEntry(id, seenAt.toIso8601String()),
        ),
      }),
    );
  }

  group('remembering', () {
    test('an id survives a new ledger over the same directory', () async {
      await ledgerFor('runner').markHandled(['session-a']);

      expect(await ledgerFor('runner').handled(), {'session-a'});
    });

    test('marking is additive and idempotent', () async {
      final ledger = ledgerFor('runner');
      await ledger.markHandled(['a']);
      await ledger.markHandled(['a', 'b']);

      expect(await ledger.handled(), {'a', 'b'});
    });

    test('marking nothing writes nothing', () async {
      await ledgerFor('runner').markHandled(const []);

      expect(fileFor('runner').existsSync(), isFalse);
    });

    test('ids are filed per user', () async {
      await ledgerFor('runner').markHandled(['a']);

      expect(await ledgerFor('someone-else').handled(), isEmpty);
    });

    test('concurrent marks do not write each other away', () async {
      final ledger = ledgerFor('runner');
      await Future.wait([
        ledger.markHandled(['a']),
        ledger.markHandled(['b']),
        ledger.markHandled(['c']),
      ]);

      expect(await ledger.handled(), {'a', 'b', 'c'});
    });
  });

  group('pruning', () {
    test('drops entries past the retention window on the next write', () async {
      final now = DateTime.now();
      seed('runner', {
        'ancient': now.subtract(FileRunImportLedger.retention * 2),
        'recent': now.subtract(const Duration(days: 1)),
      });

      await ledgerFor('runner').markHandled(['fresh']);

      expect(await ledgerFor('runner').handled(), {'recent', 'fresh'});
    });

    test('re-marking an id does not refresh its age', () async {
      final now = DateTime.now();
      // A day inside the window. Re-marking must not push it back out to 60
      // days, or an id rescanned every launch would never be retired.
      seed('runner', {
        'old': now
            .subtract(FileRunImportLedger.retention - const Duration(hours: 1)),
      });

      final ledger = ledgerFor('runner');
      await ledger.markHandled(['old']);
      expect(await ledger.handled(), contains('old'));

      seed('runner', {
        'old': now.subtract(FileRunImportLedger.retention * 2),
      });
      await ledger.markHandled(['other']);

      expect(await ledger.handled(), {'other'});
    });
  });

  group('surviving trouble', () {
    test('an unreadable file reads as empty rather than throwing', () async {
      final file = fileFor('runner');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('{not json');

      expect(await ledgerFor('runner').handled(), isEmpty);
    });

    test('a ledger from a future schema is ignored, not misread', () async {
      final file = fileFor('runner');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'v': FileRunImportLedger.schemaVersion + 1,
          'entries': {'a': DateTime.now().toIso8601String()},
        }),
      );

      expect(await ledgerFor('runner').handled(), isEmpty);
    });

    test('leaves no stray temp file behind', () async {
      await ledgerFor('runner').markHandled(['a']);

      final names = Directory('${root.path}/run_drafts/runner')
          .listSync()
          .map((entry) => entry.uri.pathSegments.last)
          .toList();
      expect(names, ['imported.ledger']);
    });
  });

  group('living beside the drafts', () {
    test('the drafts list does not try to read the ledger', () async {
      final store = FileRunDraftStore(
        rootDirectory: () async => root,
        userId: 'runner',
      );
      await store.save(
        RunDraft(
          id: 'draft-1',
          savedAt: DateTime.utc(2026, 9, 6, 9),
          distanceKm: 5,
          elapsed: const Duration(minutes: 30),
          averagePace: '6:00 /km',
          shareToFeed: false,
        ),
      );
      await ledgerFor('runner').markHandled(['session-a']);

      final drafts = await store.list();
      expect(drafts.map((draft) => draft.id), ['draft-1']);
    });

    test('account deletion takes the ledger with the drafts', () async {
      await ledgerFor('runner').markHandled(['session-a']);

      await FileRunDraftStore(
        rootDirectory: () async => root,
        userId: 'runner',
      ).clearAll();

      expect(fileFor('runner').existsSync(), isFalse);
      // And the ledger still works afterwards rather than throwing on a
      // directory that is no longer there.
      await ledgerFor('runner').markHandled(['session-b']);
      expect(await ledgerFor('runner').handled(), {'session-b'});
    });
  });
}
