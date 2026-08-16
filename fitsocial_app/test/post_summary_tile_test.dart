import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/shared/widgets/post_summary_tile.dart';
import 'package:fitsocial_app/shared/widgets/route_sparkline.dart';

FeedPost _post({
  String activity = '',
  String caption = '',
  PostType postType = PostType.text,
  List<String> metricLabels = const [],
  List<RoutePoint> routePoints = const [],
  Map<String, dynamic>? workoutData,
  String? imageUrl,
}) {
  return FeedPost(
    id: 'p1',
    authorId: 'u1',
    userName: 'Neo M.',
    activity: activity,
    caption: caption,
    metricLabels: metricLabels,
    timestamp: 'now',
    likes: 0,
    comments: 0,
    backgroundColors: const [],
    likedBy: const [],
    postType: postType,
    imageUrl: imageUrl,
    workoutData: workoutData,
    routePoints: routePoints,
  );
}

const _route = [
  RoutePoint(latitude: -26.20, longitude: 28.00),
  RoutePoint(latitude: -26.21, longitude: 28.02),
];

/// A profile tile: three across on a phone, square.
Widget harness(Widget tile) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 114, height: 114, child: tile)),
    ),
  );
}

void main() {
  group('what the body leads with', () {
    testWidgets('a GPS run: its route, with the distance under it',
        (tester) async {
      await tester.pumpWidget(harness(
        PostSummaryTile(
          post: _post(
            activity: 'Run',
            postType: PostType.run,
            metricLabels: const ['5.24 km', '32:10', "6'08\"/km"],
            routePoints: _route,
          ),
          compact: true,
        ),
      ));

      expect(find.byType(RouteSparkline), findsOneWidget);
      expect(find.text('5.24 km'), findsOneWidget);
      // Three across leaves no room for the rest of the read-out, and half a
      // line of it would be worse than none.
      expect(find.text("32:10 · 6'08\"/km"), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a workout: its headline, then its own title', (tester) async {
      await tester.pumpWidget(harness(
        PostSummaryTile(
          post: _post(
            activity: 'Leg Day',
            postType: PostType.workout,
            metricLabels: const ['45 min', '320 kcal', '6 moves'],
            workoutData: const {'title': 'Leg Day'},
          ),
          compact: true,
        ),
      ));

      expect(find.text('45 min'), findsOneWidget);
      expect(find.text('Leg Day'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a meal with no photo: its calories, then what it was',
        (tester) async {
      await tester.pumpWidget(harness(
        PostSummaryTile(
          post: _post(
            activity: 'Oats',
            postType: PostType.meal,
            metricLabels: const ['420 kcal', '30g protein', '12g fat'],
          ),
          compact: true,
        ),
      ));

      expect(find.text('420 kcal'), findsOneWidget);
      expect(find.text('Oats'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a written post: the words themselves', (tester) async {
      // The whole point of the change: a post whose content is text used to be
      // a gradient rectangle labelled with its subtitle, never showing a word
      // of what was actually written.
      await tester.pumpWidget(harness(
        PostSummaryTile(
          post: _post(
            activity: 'Morning thoughts',
            caption: 'Three weeks in and the 5am alarm finally stopped hurting.',
          ),
          compact: true,
        ),
      ));

      expect(
        find.textContaining('the 5am alarm finally stopped hurting'),
        findsOneWidget,
      );
      expect(find.text('Morning thoughts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('nothing is drawn twice, and nothing renders empty', () {
    testWidgets('a written post with no subtitle shows only its words',
        (tester) async {
      await tester.pumpWidget(harness(
        PostSummaryTile(post: _post(caption: 'Rest day.'), compact: true),
      ));

      expect(find.text('Rest day.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a post with neither words nor numbers falls back to its title',
        (tester) async {
      // Older runs were written without metrics. The body takes the activity
      // and the footer line drops rather than printing it a second time.
      await tester.pumpWidget(harness(
        PostSummaryTile(
          post: _post(activity: 'Run', postType: PostType.run),
          compact: true,
        ),
      ));

      expect(find.text('Run'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a run typed in by hand leads with the distance',
        (tester) async {
      await tester.pumpWidget(harness(
        PostSummaryTile(
          post: _post(
            activity: 'Run',
            postType: PostType.run,
            metricLabels: const ['5.20 km', '30:00', '5:46/km'],
          ),
          compact: true,
        ),
      ));

      expect(find.byType(RouteSparkline), findsNothing);
      expect(find.text('5.20 km'), findsOneWidget);
      expect(find.text('Run'), findsOneWidget);
    });
  });

  group('a photo is the backdrop, not the whole tile', () {
    testWidgets('a run keeps its route and its distance over the picture',
        (tester) async {
      await tester.pumpWidget(harness(
        PostMediaTile(
          post: _post(
            activity: 'Run',
            postType: PostType.run,
            metricLabels: const ['5.24 km', '32:10'],
            routePoints: _route,
            imageUrl: 'https://example.test/sunrise.jpg',
          ),
          compact: true,
        ),
      ));

      expect(find.byType(RouteSparkline), findsOneWidget);
      expect(find.text('5.24 km'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a workout keeps its headline over the picture',
        (tester) async {
      await tester.pumpWidget(harness(
        PostMediaTile(
          post: _post(
            activity: 'Leg Day',
            postType: PostType.workout,
            metricLabels: const ['45 min', '320 kcal'],
            workoutData: const {'title': 'Leg Day'},
            imageUrl: 'https://example.test/gym.jpg',
          ),
          compact: true,
        ),
      ));

      expect(find.text('45 min'), findsOneWidget);
      // Three across leaves room for one line, so the rest of the read-out is
      // dropped here exactly as it is on the card.
      expect(find.text('320 kcal'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a photograph on its own stays a bare photograph',
        (tester) async {
      // A written post's picture *is* the post. Nothing is being summarised
      // over it, so a profile grid draws it the way it always has.
      await tester.pumpWidget(harness(
        PostMediaTile(
          post: _post(
            activity: 'Saturday',
            caption: 'Trail with the club.',
            imageUrl: 'https://example.test/trail.jpg',
          ),
          compact: true,
        ),
      ));

      expect(find.text('Saturday'), findsNothing);
      expect(find.text('Trail with the club.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a post whose picture never arrives still shows the run',
        (tester) async {
      // The placeholder stands in for the photo; the trace and the numbers are
      // drawn over it either way, so a failed download costs the backdrop and
      // nothing else.
      await tester.pumpWidget(harness(
        PostMediaTile(
          post: _post(
            activity: 'Run',
            postType: PostType.run,
            metricLabels: const ['5.24 km'],
            routePoints: _route,
            imageUrl: 'https://example.test/missing.jpg',
          ),
          compact: true,
        ),
      ));
      await tester.pump();

      expect(find.byType(RouteSparkline), findsOneWidget);
      expect(find.text('5.24 km'), findsOneWidget);
    });
  });

  group('density', () {
    testWidgets('the author is named only where the grid mixes people',
        (tester) async {
      final post = _post(
        activity: 'Run',
        postType: PostType.run,
        metricLabels: const ['5.24 km'],
        routePoints: _route,
      );

      // A profile grid is one person's work throughout.
      await tester.pumpWidget(harness(
        PostSummaryTile(post: post, compact: true),
      ));
      expect(find.text('Neo M.'), findsNothing);

      await tester.pumpWidget(harness(
        PostSummaryTile(post: post, showAuthor: true),
      ));
      expect(find.text('Neo M.'), findsOneWidget);
    });

    testWidgets('the full size carries the rest of the metrics',
        (tester) async {
      await tester.pumpWidget(harness(
        PostSummaryTile(
          post: _post(
            activity: 'Leg Day',
            postType: PostType.workout,
            metricLabels: const ['45 min', '320 kcal', '6 moves'],
          ),
        ),
      ));

      expect(find.text('320 kcal · 6 moves'), findsOneWidget);
    });
  });
}
