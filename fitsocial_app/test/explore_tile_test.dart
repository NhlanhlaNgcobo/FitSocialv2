import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/presentation/explore_screen.dart';
import 'package:fitsocial_app/shared/widgets/route_sparkline.dart';

FeedPost _post({
  required String activity,
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
    caption: '',
    metricLabels: metricLabels,
    timestamp: 'now',
    likes: 4,
    comments: 2,
    // The muddy pair a run used to be painted with. Nothing on an activity
    // tile should be reading it any more.
    backgroundColors: const [Color(0xFF7A4D2E), Color(0xFF121212)],
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
  RoutePoint(latitude: -26.22, longitude: 28.01),
];

Widget harness(List<FeedPost> posts) {
  return ProviderScope(
    overrides: [
      trendingPostsProvider.overrideWith((ref) async => posts),
    ],
    child: const MaterialApp(home: ExploreScreen()),
  );
}

void main() {
  group('explore activity tiles', () {
    testWidgets('a GPS run draws its route and leads with the distance',
        (tester) async {
      await tester.pumpWidget(harness([
        _post(
          activity: 'Run',
          postType: PostType.run,
          metricLabels: const ['5.24 km', '32:10', "6'08\"/km"],
          routePoints: _route,
        ),
      ]));
      await tester.pumpAndSettle();

      expect(find.byType(RouteSparkline), findsOneWidget);
      expect(find.text('5.24 km'), findsOneWidget);
      expect(find.text("32:10 · 6'08\"/km"), findsOneWidget);
      // The distance heads the footer, so the word "Run" — which the icon
      // already says — is not printed as well.
      expect(find.text('Run'), findsNothing);
    });

    testWidgets('a run typed in by hand leads with the distance instead',
        (tester) async {
      // No trace to draw, so the number takes the body and the title falls to
      // the footer. It must still not read as an empty tile.
      await tester.pumpWidget(harness([
        _post(
          activity: 'Run',
          postType: PostType.run,
          metricLabels: const ['5.20 km', '30:00', '5:46/km'],
        ),
      ]));
      await tester.pumpAndSettle();

      expect(find.byType(RouteSparkline), findsNothing);
      expect(find.text('5.20 km'), findsOneWidget);
      expect(find.text('Run'), findsOneWidget);
      expect(find.text('30:00 · 5:46/km'), findsOneWidget);
    });

    testWidgets('a workout shows what it measured, under its own title',
        (tester) async {
      await tester.pumpWidget(harness([
        _post(
          activity: 'Leg Day',
          postType: PostType.workout,
          metricLabels: const ['45 min', '320 kcal', '6 moves'],
          workoutData: const {'title': 'Leg Day'},
        ),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('45 min'), findsOneWidget);
      expect(find.text('Leg Day'), findsOneWidget);
      expect(find.text('320 kcal · 6 moves'), findsOneWidget);
      expect(find.text('Neo M.'), findsOneWidget);
    });

    testWidgets('a photo post is still shown as its photo', (tester) async {
      // A meal with a picture keeps the media treatment: author over the
      // image, activity underneath, no stats card.
      await tester.pumpWidget(harness([
        _post(
          activity: 'Oats',
          postType: PostType.meal,
          metricLabels: const ['420 kcal', '30g protein'],
          imageUrl: 'https://example.test/oats.jpg',
        ),
      ]));
      await tester.pumpAndSettle();

      expect(find.byType(RouteSparkline), findsNothing);
      expect(find.text('Neo M.'), findsOneWidget);
      // The photo never loads under the test binding, so the tile is showing
      // the neutral placeholder — which says nothing, leaving the caption band
      // as the only place the activity appears.
      expect(find.text('Oats'), findsOneWidget);
      expect(find.text('420 kcal · 30g protein'), findsNothing);
    });
  });
}
