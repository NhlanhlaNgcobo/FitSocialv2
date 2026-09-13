import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/presentation/comments_sheet.dart';
import 'package:fitsocial_app/features/main/presentation/post_detail_screen.dart';

/// The reply thread, end to end on the screen that hosts it: a reply reads as
/// an answer to a comment rather than as one more line at the bottom, and the
/// button that writes one says where the words are going before they are sent.
void main() {
  testWidgets('a reply is drawn under the comment it answers', (tester) async {
    await _pump(tester, [
      _comment('c1', author: 'Thandi', text: 'Strong run'),
      _comment('c2', author: 'Neo', text: 'Where was this?'),
      _comment('c1r', author: 'Bear', text: 'Thanks!', parentId: 'c1'),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.text('Thanks!'), findsOneWidget);

    // Under its parent, and above the comment that was written before it —
    // which is the whole difference between a thread and a flat list.
    final reply = tester.getTopLeft(find.text('Thanks!'));
    final parent = tester.getTopLeft(find.text('Strong run'));
    final other = tester.getTopLeft(find.text('Where was this?'));

    expect(reply.dy, greaterThan(parent.dy));
    expect(reply.dy, lessThan(other.dy));
    // Indented past the words it answers.
    expect(reply.dx, greaterThan(parent.dx));
  });

  testWidgets('tapping Reply says who is being answered', (tester) async {
    await _pump(tester, [_comment('c1', author: 'Thandi', text: 'Strong run')]);

    await tester.tap(find.text('Reply'));
    await tester.pump();

    expect(find.text('Replying to Thandi'), findsOneWidget);
  });

  testWidgets('the reply can be taken back', (tester) async {
    await _pump(tester, [_comment('c1', author: 'Thandi', text: 'Strong run')]);

    await tester.tap(find.text('Reply'));
    // The chip grows in rather than popping, and is clipped until it has —
    // so the ✕ is only there to tap once the animation has landed.
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(find.text('Replying to Thandi'), findsNothing);
  });

  testWidgets('a long thread is collapsed until it is asked for',
      (tester) async {
    await _pump(tester, [
      _comment('c1', author: 'Thandi', text: 'Strong run'),
      for (var i = 1; i <= 4; i++)
        _comment('c1r$i', author: 'Bear', text: 'reply $i', parentId: 'c1'),
    ]);

    expect(find.text('reply 3'), findsNothing);
    expect(find.text('View 2 more replies'), findsOneWidget);

    await tester.tap(find.text('View 2 more replies'));
    await tester.pump();

    expect(find.text('reply 3'), findsOneWidget);
    expect(find.text('reply 4'), findsOneWidget);
    expect(find.text('Hide replies'), findsOneWidget);
  });

  testWidgets('one hidden reply is asked for in the singular', (tester) async {
    await _pump(tester, [
      _comment('c1', author: 'Thandi', text: 'Strong run'),
      for (var i = 1; i <= 3; i++)
        _comment('c1r$i', author: 'Bear', text: 'reply $i', parentId: 'c1'),
    ]);

    expect(find.text('View 1 more reply'), findsOneWidget);
  });
}

Comment _comment(
  String id, {
  required String author,
  required String text,
  String? parentId,
}) {
  return Comment(
    id: id,
    authorId: 'u-$id',
    authorName: author,
    text: text,
    createdAt: DateTime(2026, 9, 6, 16, 15),
    parentId: parentId,
  );
}

FeedPost get _post => const FeedPost(
      id: 'p1',
      authorId: 'me',
      userName: 'Author',
      activity: 'Session',
      caption: 'Rest day.',
      metricLabels: [],
      timestamp: 'now',
      likes: 0,
      comments: 0,
      backgroundColors: [Color(0xFF201010), Color(0xFF402020)],
      likedBy: [],
    );

Future<void> _pump(WidgetTester tester, List<Comment> comments) async {
  // Tall enough that the whole thread lays out at once — the assertions are
  // about where the rows sit relative to each other.
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Reaches FirebaseAuth otherwise, which no widget test has.
        currentUserIdProvider.overrideWithValue('me'),
        commentsStreamProvider('p1')
            .overrideWith((ref) => Stream.value(comments)),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: PostDetailScreen(postId: 'p1', initialPost: _post),
      ),
    ),
  );
  await tester.pump();
  // The list is a stream; let its first frame land.
  await tester.pump();

  expect(find.byType(CommentThreadTile), findsWidgets);
}
