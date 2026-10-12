import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/comment_threads.dart';
import 'package:fitsocial_app/features/main/presentation/comments_sheet.dart';

class _RecordingRepository extends UnconfiguredContentRepository {
  final likes = <(String, String, String, bool)>[];

  @override
  Future<void> setCommentLike(
    String postId,
    String commentId,
    String userId, {
    required bool liked,
    UserProfileDraft? profile,
  }) async {
    likes.add((postId, commentId, userId, liked));
  }
}

Comment _comment({List<String> likedBy = const []}) => Comment(
      id: 'c1',
      authorId: 'author',
      authorName: 'Thandi',
      text: 'Strong session',
      createdAt: DateTime.now(),
      likedBy: likedBy,
    );

Future<_RecordingRepository> _pump(
  WidgetTester tester,
  Comment comment, {
  String? viewerId = 'me',
}) async {
  final repository = _RecordingRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contentRepositoryProvider.overrideWithValue(repository),
        currentUserIdProvider.overrideWithValue(viewerId),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: CommentThreadTile(
            postId: 'p1',
            thread: threadComments([comment]).single,
            onReply: (_) {},
          ),
        ),
      ),
    ),
  );
  return repository;
}

void main() {
  group('Comment.isLikedBy', () {
    test('reads the likedBy list, and nobody when signed out', () {
      final comment = _comment(likedBy: ['me']);
      expect(comment.isLikedBy('me'), isTrue);
      expect(comment.isLikedBy('other'), isFalse);
      expect(comment.isLikedBy(null), isFalse);
    });

    test('survives a change of author name', () {
      final renamed = _comment(likedBy: ['me'])
          .withAuthor(authorName: 'New', authorAvatarUrl: null);
      expect(renamed.likedBy, ['me']);
    });
  });

  group('the heart on a comment', () {
    testWidgets('an unliked comment shows an empty heart and no count',
        (tester) async {
      await _pump(tester, _comment());
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('tapping it likes the comment as the viewer', (tester) async {
      final repository = await _pump(tester, _comment());
      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump();
      expect(repository.likes, [('p1', 'c1', 'me', true)]);
    });

    testWidgets('a liked comment shows a filled heart, a count, and unlikes',
        (tester) async {
      final repository =
          await _pump(tester, _comment(likedBy: ['me', 'other']));
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pump();
      expect(repository.likes, [('p1', 'c1', 'me', false)]);
    });

    testWidgets('signed out, there is no heart to tap', (tester) async {
      await _pump(tester, _comment(), viewerId: null);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
    });
  });
}
