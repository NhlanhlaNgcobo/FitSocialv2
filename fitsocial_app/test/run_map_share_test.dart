import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/data/firestore_models.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/shared_post.dart';
import 'package:fitsocial_app/shared/widgets/fit_social_logo.dart';
import 'package:fitsocial_app/shared/widgets/route_sparkline.dart';
import 'package:fitsocial_app/shared/widgets/run_route_map.dart';
import 'package:fitsocial_app/shared/widgets/run_summary_card.dart';

const _route = [
  RoutePoint(latitude: -26.20, longitude: 28.00),
  RoutePoint(latitude: -26.21, longitude: 28.02),
  RoutePoint(latitude: -26.22, longitude: 28.01),
];

const _mapPicture = 'https://example.com/run_map.jpg';

Future<void> _pumpCard(
  WidgetTester tester, {
  required bool showMap,
  String? backgroundUrl,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: RunSummaryCard(
          route: _route,
          distanceLabel: '5.20 km',
          durationLabel: '28:14',
          background:
              backgroundUrl == null ? null : NetworkImage(backgroundUrl),
          showMap: showMap,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('run card with the map chosen', () {
    testWidgets('a posted run shows its map picture, not a live map',
        (tester) async {
      await _pumpCard(tester, showMap: true, backgroundUrl: _mapPicture);

      expect(find.byType(RunRouteMap), findsNothing);
      // The route and the branding are already in the picture; drawing them
      // again would double them up.
      expect(find.byType(RouteSparkline), findsNothing);
      expect(find.byType(FitSocialLogo), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is NetworkImage &&
              (widget.image as NetworkImage).url == _mapPicture,
        ),
        findsOneWidget,
      );
    });

    testWidgets('without a picture the map is drawn live', (tester) async {
      await _pumpCard(tester, showMap: true);

      expect(find.byType(RunRouteMap), findsOneWidget);
      expect(find.byType(RouteSparkline), findsNothing);
      // Branded live, the way the picture will be.
      expect(find.byType(FitSocialLogo), findsOneWidget);
    });

    testWidgets('left off, the card is the bare line as before',
        (tester) async {
      await _pumpCard(tester, showMap: false, backgroundUrl: _mapPicture);

      expect(find.byType(RunRouteMap), findsNothing);
      expect(find.byType(RouteSparkline), findsOneWidget);
    });
  });

  group('the choice on the post', () {
    test('is read off the document, and absent means no map', () {
      final chosen = FirestorePostRecord.fromMap('a', const {
        'postType': 'run',
        'showRouteMap': true,
      });
      final older = FirestorePostRecord.fromMap('b', const {
        'postType': 'run',
      });

      expect(chosen.showRouteMap, isTrue);
      expect(older.showRouteMap, isFalse);
    });
  });

  group('sharing a map run to Pulse', () {
    SharedPostRef share({required bool routeOnImage, String? imageUrl}) =>
        SharedPostRef.of(
          postId: 'p1',
          authorId: 'u1',
          authorName: 'Bear',
          imageUrl: imageUrl,
          route: _route,
          routeOnImage: routeOnImage,
        );

    test('carries that the picture already holds the route', () {
      final ref = share(routeOnImage: true, imageUrl: _mapPicture);
      final restored = SharedPostRef.fromMap(ref.toMap())!;

      expect(ref.routeOnImage, isTrue);
      expect(restored.routeOnImage, isTrue);
    });

    test('a run without a picture cannot claim one', () {
      expect(share(routeOnImage: true).routeOnImage, isFalse);
    });

    test('an ordinary run share is unchanged', () {
      final ref = share(routeOnImage: false, imageUrl: _mapPicture);

      expect(ref.routeOnImage, isFalse);
      expect(ref.toMap().containsKey('routeOnImage'), isFalse);
    });
  });
}
