import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_palette.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/shared_post.dart';
import 'package:fitsocial_app/features/pulse/domain/pulse_models.dart';
import 'package:fitsocial_app/shared/widgets/route_sparkline.dart';
import 'package:fitsocial_app/shared/widgets/shared_post_card.dart';

FeedPost _post({
  String? imageUrl,
  List<RoutePoint> routePoints = const [],
  Map<String, dynamic>? workoutData,
  PostType postType = PostType.text,
  String caption = '',
}) {
  return FeedPost(
    id: 'p1',
    authorId: 'u1',
    userName: 'Bear M',
    activity: 'Morning run',
    caption: caption,
    metricLabels: const [],
    timestamp: 'now',
    likes: 0,
    comments: 0,
    backgroundColors: const [],
    likedBy: const [],
    postType: postType,
    imageUrl: imageUrl,
    workoutData: workoutData,
    routePoints: routePoints,
    imageAspectRatio: 0.8,
  );
}

void main() {
  group('SharedPostRef', () {
    test('a route outranks the stored type, exactly as the feed card has it',
        () {
      final ref = SharedPostRef.fromFeedPost(
        _post(
          postType: PostType.run,
          imageUrl: 'https://example.com/a.jpg',
          routePoints: const [
            RoutePoint(latitude: 1, longitude: 1),
            RoutePoint(latitude: 2, longitude: 2),
          ],
        ),
      );

      expect(ref.kind, SharedPostKind.route);
    });

    test('a run with a single fix is not a route', () {
      final ref = SharedPostRef.fromFeedPost(
        _post(
          postType: PostType.run,
          routePoints: const [RoutePoint(latitude: 1, longitude: 1)],
        ),
      );

      expect(ref.kind, SharedPostKind.text);
    });

    test('carries the trace, thinned, so the card can draw the run', () {
      final ref = SharedPostRef.fromFeedPost(
        _post(
          postType: PostType.run,
          routePoints: [
            for (var i = 0; i < 900; i++)
              RoutePoint(latitude: i / 1000, longitude: i / 1000),
          ],
        ),
      );

      expect(ref.hasRoute, isTrue);
      expect(ref.route.length, SharedPostRef.maxRoutePoints);
      expect(ref.route.first.latitude, 0);
      // The finish survives the thinning — it is where the shape closes.
      expect(ref.route.last.latitude, 899 / 1000);
    });

    test('a short route is carried whole', () {
      final ref = SharedPostRef.fromFeedPost(
        _post(
          postType: PostType.run,
          routePoints: const [
            RoutePoint(latitude: 1, longitude: 1),
            RoutePoint(latitude: 2, longitude: 2),
          ],
        ),
      );

      expect(ref.route.length, 2);
    });

    test('only a run carries a trace', () {
      final ref = SharedPostRef.fromFeedPost(
        _post(
          postType: PostType.run,
          routePoints: const [RoutePoint(latitude: 1, longitude: 1)],
        ),
      );

      // One fix is not a route, so this is a text share — and a text share has
      // no shape to put on the Pulse document.
      expect(ref.kind, SharedPostKind.text);
      expect(ref.route, isEmpty);
      expect(ref.hasRoute, isFalse);
    });

    test('a meal is a photo, and keeps the shape it was cropped to', () {
      final ref = SharedPostRef.fromFeedPost(
        _post(postType: PostType.meal, imageUrl: 'https://example.com/a.jpg'),
      );

      expect(ref.kind, SharedPostKind.photo);
      expect(ref.aspectRatio, 0.8);
      expect(ref.hasImage, isTrue);
    });

    test('a workout with no photo draws as a workout', () {
      final ref = SharedPostRef.fromFeedPost(
        _post(postType: PostType.workout, workoutData: const {'sets': 3}),
      );

      expect(ref.kind, SharedPostKind.workout);
    });

    test('a long caption is clipped, because the card is not the post', () {
      final ref = SharedPostRef.fromFeedPost(
        _post(caption: 'a' * 400),
      );

      expect(ref.caption.length, SharedPostRef.maxCaptionLength);
      expect(ref.caption, endsWith('…'));
    });

    test('survives the round trip through a Pulse document', () {
      final ref = SharedPostRef.fromFeedPost(
        _post(postType: PostType.image, imageUrl: 'https://example.com/a.jpg'),
      );

      final restored = SharedPostRef.fromMap(ref.toMap())!;

      expect(restored.postId, ref.postId);
      expect(restored.authorId, ref.authorId);
      expect(restored.authorName, ref.authorName);
      expect(restored.activity, ref.activity);
      expect(restored.kind, ref.kind);
      expect(restored.imageUrl, ref.imageUrl);
      expect(restored.aspectRatio, ref.aspectRatio);
    });

    test('a run keeps its shape through a Pulse document', () {
      final ref = SharedPostRef.fromFeedPost(
        _post(
          postType: PostType.run,
          routePoints: const [
            RoutePoint(latitude: -26.2, longitude: 28.04),
            RoutePoint(latitude: -26.21, longitude: 28.05),
            RoutePoint(latitude: -26.22, longitude: 28.04),
          ],
        ),
      );

      final restored = SharedPostRef.fromMap(ref.toMap())!;

      expect(restored.kind, SharedPostKind.route);
      expect(restored.route.length, 3);
      expect(restored.route.last.latitude, -26.22);
    });

    test('a trace longer than the cap is thinned on the way back in', () {
      // The length is capped on write, but the document was written by a
      // client and the card redraws it on every frame of playback.
      final restored = SharedPostRef.fromMap({
        'postId': 'p1',
        'kind': 'route',
        'route': [
          for (var i = 0; i < 5000; i++) {'lat': i / 10000, 'lng': i / 10000},
        ],
      })!;

      expect(restored.route.length, SharedPostRef.maxRoutePoints);
    });

    test('a stored snapshot with no post id is not a share', () {
      // Nothing to open, so nothing to draw — the viewer says so rather than
      // rendering a card that leads nowhere.
      expect(SharedPostRef.fromMap(const {'authorName': 'Bear'}), isNull);
      expect(SharedPostRef.fromMap(null), isNull);
      expect(SharedPostRef.fromMap('post'), isNull);
    });

    test('an author name written by a client is sanitised on the way back in',
        () {
      final restored = SharedPostRef.fromMap(const {
        'postId': 'p1',
        'authorName': 'bear@example.com',
      })!;

      expect(restored.authorName, PublicAuthorName.fallback);
    });

    test('an unknown kind from a newer build still renders as something', () {
      final restored = SharedPostRef.fromMap(const {
        'postId': 'p1',
        'kind': 'hologram',
      })!;

      expect(restored.kind, SharedPostKind.text);
    });
  });

  group('a Pulse that is a shared post', () {
    test('is publishable on the post alone — there is nothing to upload', () {
      final ref = SharedPostRef.fromFeedPost(_post());

      expect(
        const PulseDraft(type: PulseMediaType.post).isPublishable,
        isFalse,
      );
      expect(
        PulseDraft(type: PulseMediaType.post, sharedPost: ref).isPublishable,
        isTrue,
      );
    });

    test('carries no media, so publishing never touches Storage', () {
      expect(PulseMediaType.post.carriesMedia, isFalse);
      expect(PulseMediaType.text.carriesMedia, isFalse);
      expect(PulseMediaType.photo.carriesMedia, isTrue);
      expect(PulseMediaType.video.carriesMedia, isTrue);
    });

    test('round-trips through its stored key', () {
      expect(PulseMediaType.fromKey(PulseMediaType.post.key),
          PulseMediaType.post);
      // A document written before this kind existed still reads as a photo.
      expect(PulseMediaType.fromKey(null), PulseMediaType.photo);
    });

    test('holds the screen for a still frame, not a video length', () {
      final segment = PulseSegment(
        id: 's1',
        authorId: 'u1',
        authorName: 'Bear M',
        type: PulseMediaType.post,
        createdAt: DateTime(2026, 8, 10),
        expiresAt: DateTime(2026, 8, 11),
        sharedPost: SharedPostRef.fromFeedPost(_post()),
      );

      expect(segment.displayDuration, PulseTiming.frameDuration);
    });
  });

  group('SharedPostCard', () {
    Widget host(Widget child) {
      return MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.dark]),
        home: Scaffold(body: Center(child: child)),
      );
    }

    testWidgets('names the author and offers the way through to the post',
        (tester) async {
      await tester.pumpWidget(
        host(
          SharedPostCard(
            post: SharedPostRef.fromFeedPost(_post(caption: 'Felt strong')),
          ),
        ),
      );

      expect(find.text('Bear M'), findsOneWidget);
      expect(find.text('Morning run'), findsOneWidget);
      expect(find.text('Felt strong'), findsOneWidget);
      expect(find.text('VIEW POST'), findsOneWidget);
    });

    testWidgets('opens the post it came from when tapped', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        host(
          SharedPostCard(
            post: SharedPostRef.fromFeedPost(_post()),
            onTap: () => opened++,
          ),
        ),
      );

      await tester.tap(find.byType(SharedPostCard));
      expect(opened, 1);
    });

    testWidgets('a run share draws the line it was, not a glyph for it',
        (tester) async {
      await tester.pumpWidget(
        host(
          SharedPostCard(
            post: SharedPostRef.fromFeedPost(
              _post(
                postType: PostType.run,
                routePoints: const [
                  RoutePoint(latitude: 1, longitude: 1),
                  RoutePoint(latitude: 2, longitude: 2),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byType(RouteSparkline), findsOneWidget);
      expect(find.text('RUN ROUTE'), findsNothing);
      // Nothing is fetched to draw it — the trace rides on the snapshot.
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a share written before the trace was carried keeps the label',
        (tester) async {
      await tester.pumpWidget(
        host(
          SharedPostCard(
            post: SharedPostRef.fromMap(const {
              'postId': 'p1',
              'kind': 'route',
            })!,
          ),
        ),
      );

      expect(find.text('RUN ROUTE'), findsOneWidget);
      expect(find.byType(RouteSparkline), findsNothing);
    });
  });
}
