import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/tracking/data/run_draft_store.dart';
import 'package:fitsocial_app/features/tracking/domain/run_draft.dart';

// A real temp directory rather than a mocked filesystem: the whole point of
// this store is what survives on disk, and the interesting cases — a photo
// whose source has been evicted, a file half-written by a process that died —
// only exist there.

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('run_drafts_test'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  FileRunDraftStore storeFor(String userId) => FileRunDraftStore(
        rootDirectory: () async => root,
        userId: userId,
      );

  Directory directoryFor(String userId) =>
      Directory('${root.path}/run_drafts/$userId');

  RunDraft draft(String id, {DateTime? savedAt}) => RunDraft(
        id: id,
        savedAt: savedAt ?? DateTime.utc(2026, 8, 31, 9),
        distanceKm: 5.2,
        elapsed: const Duration(minutes: 28),
        averagePace: '5:26 /km',
        shareToFeed: true,
      );

  File sourcePhoto(String name) {
    final file = File('${root.path}/$name')
      ..writeAsBytesSync(const [1, 2, 3, 4]);
    return file;
  }

  group('saving and listing', () {
    test('round trips a draft', () async {
      final store = storeFor('u1');
      await store.save(draft('a'));

      final drafts = await store.list();
      expect(drafts, hasLength(1));
      expect(drafts.single.id, 'a');
      expect(drafts.single.distanceKm, 5.2);
    });

    test('lists newest first', () async {
      final store = storeFor('u1');
      await store.save(draft('older', savedAt: DateTime.utc(2026, 8, 30)));
      await store.save(draft('newest', savedAt: DateTime.utc(2026, 8, 31)));
      await store.save(draft('middle', savedAt: DateTime.utc(2026, 8, 30, 18)));

      expect(
        (await store.list()).map((d) => d.id),
        ['newest', 'middle', 'older'],
      );
    });

    test('an empty directory lists nothing', () async {
      expect(await storeFor('u1').list(), isEmpty);
    });
  });

  group('the photo', () {
    // The reason the copy exists at all: image_cropper hands back a path in
    // the temp directory, and the OS is free to reclaim it long before the
    // runner gets signal back.
    test('survives the source being evicted', () async {
      final store = storeFor('u1');
      final source = sourcePhoto('picked.jpg');

      final stored = await store.save(draft('a'), sourcePhotoPath: source.path);
      source.deleteSync();

      expect(stored.photoPath, isNotNull);
      expect(File(stored.photoPath!).existsSync(), isTrue);
      expect(File(stored.photoPath!).readAsBytesSync(), [1, 2, 3, 4]);
      expect((await store.list()).single.photoPath, stored.photoPath);
    });

    // Never lose a run over a picture.
    test('a source that is already gone still saves the run', () async {
      final store = storeFor('u1');

      final stored = await store.save(
        draft('a'),
        sourcePhotoPath: '${root.path}/never-existed.jpg',
      );

      expect(stored.photoPath, isNull);
      expect(stored.photoUnavailable, isTrue);
      final listed = (await store.list()).single;
      expect(listed.id, 'a');
      expect(listed.photoUnavailable, isTrue);
    });

    test('is deleted along with its draft', () async {
      final store = storeFor('u1');
      final stored =
          await store.save(draft('a'), sourcePhotoPath: sourcePhoto('p').path);

      await store.delete('a');

      expect(await store.list(), isEmpty);
      expect(File(stored.photoPath!).existsSync(), isFalse);
    });
  });

  group('damaged files', () {
    test('one unreadable draft does not hide the others', () async {
      final store = storeFor('u1');
      await store.save(draft('good'));
      File('${directoryFor('u1').path}/broken.json')
          .writeAsStringSync('{ this is not json');

      final drafts = await store.list();
      expect(drafts, hasLength(1));
      expect(drafts.single.id, 'good');
    });

    test('a draft from a future version is skipped, not guessed at', () async {
      final store = storeFor('u1');
      await store.save(draft('good'));
      final future = draft('future').toJson()..['v'] = 99;
      File('${directoryFor('u1').path}/future.json')
          .writeAsStringSync(jsonEncode(future));

      expect((await store.list()).map((d) => d.id), ['good']);
    });
  });

  group('the orphan sweep', () {
    // What a process killed between writing the temp file and renaming it
    // leaves behind.
    test('removes a stray .tmp', () async {
      final directory = directoryFor('u1')..createSync(recursive: true);
      final stray = File('${directory.path}/a.json.tmp')..writeAsStringSync('');

      await storeFor('u1').list();

      expect(stray.existsSync(), isFalse);
    });

    // And what a delete that got half way leaves behind.
    test('removes a photo whose draft is gone', () async {
      final directory = directoryFor('u1')..createSync(recursive: true);
      final orphan = File('${directory.path}/gone.jpg')
        ..writeAsBytesSync(const [1]);

      await storeFor('u1').list();

      expect(orphan.existsSync(), isFalse);
    });

    test('keeps a photo whose draft is still there', () async {
      final store = storeFor('u1');
      final stored =
          await store.save(draft('a'), sourcePhotoPath: sourcePhoto('p').path);

      // A fresh store, so the sweep runs again over the same directory.
      await storeFor('u1').list();

      expect(File(stored.photoPath!).existsSync(), isTrue);
    });
  });

  group('separation and clearing', () {
    // A phone gets shared. A draft waits for its own author.
    test('one user cannot see another user\'s drafts', () async {
      await storeFor('u1').save(draft('mine'));

      expect(await storeFor('u2').list(), isEmpty);
      expect((await storeFor('u1').list()).single.id, 'mine');
    });

    test('clearAll leaves nothing behind', () async {
      final store = storeFor('u1');
      await store.save(draft('a'), sourcePhotoPath: sourcePhoto('p').path);
      await store.save(draft('b'));

      await store.clearAll();

      expect(await store.list(), isEmpty);
    });
  });

  test('markPublishAttempted survives a reload', () async {
    final store = storeFor('u1');
    await store.save(draft('a'));

    await store.markPublishAttempted(draft('a'));

    final listed = (await store.list()).single;
    expect(listed.mayHavePublished, isTrue);
    expect(listed.publishAttemptedAt, isNotNull);
  });

  // The writes are chained precisely so two of them cannot interleave and
  // leave a truncated file.
  test('concurrent saves all land and all parse', () async {
    final store = storeFor('u1');

    await Future.wait([
      store.save(draft('a')),
      store.save(draft('b')),
      store.save(draft('c')),
    ]);

    expect((await store.list()).map((d) => d.id).toSet(), {'a', 'b', 'c'});
  });
}
