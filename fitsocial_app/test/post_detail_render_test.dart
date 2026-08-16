import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/presentation/post_detail_screen.dart';

/// Opening a post from a profile grid drew an empty page: app bar, comment box,
/// and nothing in between. Every kind of post is pumped here because the cause
/// sat in the metric strip, which only some of them reach.
void main() {
  testWidgets('a meal post draws its author and its metrics', (tester) async {
    await _pump(tester, _post(metricLabels: const ['100 kcal']));

    expect(tester.takeException(), isNull);
    expect(find.text('Author'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('kcal'), findsOneWidget);
  });

  testWidgets('a run post draws the metrics its card does not', (tester) async {
    await _pump(
      tester,
      _post(
        postType: PostType.run,
        metricLabels: const ['5.23 km', '28:14', "5'23\"/km"],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Author'), findsOneWidget);
  });

  testWidgets('a workout post draws its session', (tester) async {
    // The shape the share flow writes: labels, not numbers.
    await _pump(
      tester,
      _post(
        postType: PostType.workout,
        workoutData: const {
          'title': 'Leg Day',
          'duration': '45 min',
          'calories': '320 kcal',
          'exercises': [
            {'name': 'squats', 'sets': 5, 'reps': 25},
          ],
        },
        metricLabels: const ['45 min', '320 kcal', '1 moves'],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Leg Day'), findsOneWidget);
    expect(find.text('45 min'), findsOneWidget);
    expect(find.textContaining('squats'), findsOneWidget);
  });

  testWidgets('a workout whose numbers were stored as numbers still draws',
      (tester) async {
    // The `workouts` document writes these same keys as ints. A post carrying
    // that shape used to throw mid-layout and blank the page.
    await _pump(
      tester,
      _post(
        postType: PostType.workout,
        workoutData: const {
          'title': 'Leg Day',
          'duration': 45,
          'calories': 320,
        },
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('45'), findsOneWidget);
    expect(find.text('320'), findsOneWidget);
  });

  testWidgets('a plain text post draws', (tester) async {
    await _pump(tester, _post(caption: 'Rest day.'));

    expect(tester.takeException(), isNull);
    expect(find.text('Author'), findsOneWidget);
    expect(find.textContaining('Rest day.'), findsWidgets);
  });

  testWidgets('a single metric still fills the strip', (tester) async {
    // The narrowest case, and the one the profile's meal tab actually opens.
    await _pump(tester, _post(metricLabels: const ['100 kcal']));

    expect(tester.takeException(), isNull);
  });

  testWidgets('a metric with no unit renders as all value', (tester) async {
    await _pump(tester, _post(metricLabels: const ['28:14']));

    expect(tester.takeException(), isNull);
    expect(find.text('28:14'), findsOneWidget);
  });
}

FeedPost _post({
  List<String> metricLabels = const [],
  PostType postType = PostType.text,
  Map<String, dynamic>? workoutData,
  String caption = '',
}) {
  return FeedPost(
    id: 'p1',
    authorId: 'me',
    userName: 'Author',
    activity: 'Session',
    caption: caption,
    metricLabels: metricLabels,
    timestamp: 'now',
    likes: 0,
    comments: 0,
    backgroundColors: const [Color(0xFF201010), Color(0xFF402020)],
    likedBy: const [],
    postType: postType,
    workoutData: workoutData,
  );
}

Future<void> _pump(WidgetTester tester, FeedPost post) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Reaches FirebaseAuth otherwise, which no widget test has.
        currentUserIdProvider.overrideWithValue('me'),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: PostDetailScreen(postId: post.id, initialPost: post),
      ),
    ),
  );
  await tester.pump();
}
