import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/comment_threads.dart';

Comment comment(String id, {String? parentId, String authorId = 'u1'}) {
  return Comment(
    id: id,
    authorId: authorId,
    authorName: 'Author $authorId',
    text: id,
    createdAt: DateTime(2026, 9, 6, 16, 15),
    parentId: parentId,
  );
}

void main() {
  group('grouping comments into threads', () {
    test('a flat list stays flat', () {
      final threads = threadComments([comment('a'), comment('b')]);

      expect(threads.map((t) => t.comment.id), ['a', 'b']);
      expect(threads.every((t) => t.replies.isEmpty), isTrue);
    });

    test('replies sit under the comment they answer, in order', () {
      final threads = threadComments([
        comment('a'),
        comment('b'),
        comment('a1', parentId: 'a'),
        comment('a2', parentId: 'a'),
      ]);

      expect(threads.map((t) => t.comment.id), ['a', 'b']);
      expect(threads.first.replies.map((c) => c.id), ['a1', 'a2']);
      expect(threads.first.length, 3);
    });

    test('a reply to a reply joins the same thread rather than nesting', () {
      // Nothing in the app writes this, but hand-written data can — and a
      // second level of indentation has nowhere to go on a phone.
      final threads = threadComments([
        comment('a'),
        comment('a1', parentId: 'a'),
        comment('a1x', parentId: 'a1'),
      ]);

      expect(threads.single.comment.id, 'a');
      expect(threads.single.replies.map((c) => c.id), ['a1', 'a1x']);
    });

    test('a reply whose parent is gone becomes a thread of its own', () {
      // The post owner deleting one comment must not take other people's
      // words down with it.
      final threads = threadComments([
        comment('b'),
        comment('orphan', parentId: 'deleted'),
      ]);

      expect(threads.map((t) => t.comment.id), ['b', 'orphan']);
    });

    test('a cycle in the data does not hang the list', () {
      final threads = threadComments([
        comment('a', parentId: 'b'),
        comment('b', parentId: 'a'),
      ]);

      expect(threads, isNotEmpty);
    });

    test('an empty list threads to nothing', () {
      expect(threadComments(const []), isEmpty);
    });
  });

  group('who a new comment tells', () {
    test('the post author, on a plain comment', () {
      final audience = commentNotificationAudience(
        actorId: 'me',
        postAuthorId: 'author',
        parentAuthorId: '',
        mentioned: const {},
      );

      expect(audience, {'author': false});
    });

    test('nobody, when you comment on your own post', () {
      final audience = commentNotificationAudience(
        actorId: 'me',
        postAuthorId: 'me',
        parentAuthorId: '',
        mentioned: const {},
      );

      expect(audience, isEmpty);
    });

    test('the post author and the person being replied to', () {
      final audience = commentNotificationAudience(
        actorId: 'me',
        postAuthorId: 'author',
        parentAuthorId: 'commenter',
        mentioned: const {},
      );

      expect(audience, {'commenter': true, 'author': false});
    });

    test('one row when the post author is the one being replied to', () {
      final audience = commentNotificationAudience(
        actorId: 'me',
        postAuthorId: 'author',
        parentAuthorId: 'author',
        mentioned: const {},
      );

      expect(audience, {'author': true});
    });

    test('a mention already told them, so the comment does not repeat it', () {
      final audience = commentNotificationAudience(
        actorId: 'me',
        postAuthorId: 'author',
        parentAuthorId: 'commenter',
        mentioned: const {'author'},
      );

      expect(audience, {'commenter': true});
    });

    test('a missing author is not a recipient', () {
      final audience = commentNotificationAudience(
        actorId: 'me',
        postAuthorId: '',
        parentAuthorId: '',
        mentioned: const {},
      );

      expect(audience, isEmpty);
    });
  });
}
