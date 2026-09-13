import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_palette.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/shared_post.dart';
import 'package:fitsocial_app/features/pulse/domain/pulse_models.dart';
import 'package:fitsocial_app/features/pulse/presentation/pulse_text_tool.dart';
import 'package:fitsocial_app/features/pulse/presentation/share_post_to_pulse_screen.dart';
import 'package:fitsocial_app/shared/widgets/route_sparkline.dart';
import 'package:fitsocial_app/shared/widgets/shared_post_card.dart';
import 'package:fitsocial_app/shared/widgets/workout_summary_card.dart';

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

/// A log the way the workout screen writes one.
const Map<String, dynamic> _legDay = {
  'title': 'Leg day',
  'duration': '45 min',
  'calories': '320 kcal',
  'exercises': [
    {'name': 'Squat', 'sets': 5, 'reps': 5, 'weightKg': 100},
    {'name': 'Lunge', 'sets': 3, 'reps': 12, 'weightKg': 20},
  ],
};

void main() {
  runShareScreenTests();
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

    test(
        'a workout with a photo is still a workout — the photo is its backdrop',
        () {
      final ref = SharedPostRef.fromFeedPost(
        _post(
          postType: PostType.workout,
          imageUrl: 'https://example.com/gym.jpg',
          workoutData: _legDay,
        ),
      );

      expect(ref.kind, SharedPostKind.workout);
      expect(ref.hasImage, isTrue);
      expect(ref.hasWorkout, isTrue);
    });

    test('a workout carries its log, thinned to what the sheet reads', () {
      final ref = SharedPostRef.fromFeedPost(
        _post(
          postType: PostType.workout,
          workoutData: {
            ..._legDay,
            'notes': 'felt strong',
            'exercises': [
              ..._legDay['exercises'] as List,
              'Plain string exercise',
              const {'sets': 3},
              for (var i = 0; i < 20; i++) {'name': 'Filler $i'},
            ],
          },
        ),
      );

      final log = ref.workoutData!;
      expect(log['title'], 'Leg day');
      expect(log['duration'], '45 min');
      expect(log.containsKey('notes'), isFalse);
      final exercises = log['exercises'] as List;
      expect(exercises.length, SharedPostRef.maxWorkoutExercises);
      expect(exercises.first,
          {'name': 'Squat', 'sets': 5, 'reps': 5, 'weightKg': 100});
      // A bare name survives; an entry with no name does not.
      expect(exercises[2], {'name': 'Plain string exercise'});
      expect(exercises[3], {'name': 'Filler 0'});
    });

    test('a workout keeps its log through a Pulse document', () {
      final ref = SharedPostRef.fromFeedPost(
        _post(postType: PostType.workout, workoutData: _legDay),
      );

      final restored = SharedPostRef.fromMap(ref.toMap())!;

      expect(restored.kind, SharedPostKind.workout);
      expect(restored.workoutData, ref.workoutData);
    });

    test('only a workout carries a log', () {
      final ref = SharedPostRef.fromFeedPost(
        _post(postType: PostType.image, imageUrl: 'https://example.com/a.jpg'),
      );

      expect(ref.workoutData, isNull);
      expect(ref.toMap().containsKey('workoutData'), isFalse);
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
      expect(
          PulseMediaType.fromKey(PulseMediaType.post.key), PulseMediaType.post);
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

    testWidgets('a run logged on a photo draws the line on that photo',
        (tester) async {
      await tester.pumpWidget(
        host(
          SharedPostCard(
            // Narrow enough that a 4:5 photo and the card's chrome fit the
            // test surface without overflowing.
            width: 240,
            post: SharedPostRef.fromFeedPost(
              _post(
                postType: PostType.run,
                imageUrl: 'https://example.com/run.jpg',
                routePoints: const [
                  RoutePoint(latitude: 1, longitude: 1),
                  RoutePoint(latitude: 2, longitude: 2),
                ],
              ),
            ),
          ),
        ),
      );

      // Both, and in that order: the photo is the backdrop, the line is over
      // it. The tinted tile that stands in for a photo is not drawn at all.
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(RouteSparkline), findsOneWidget);
      expect(find.text('RUN ROUTE'), findsNothing);
      final photoY = tester.getRect(find.byType(Image)).top;
      final lineY = tester.getRect(find.byType(RouteSparkline)).top;
      expect(lineY, greaterThanOrEqualTo(photoY));
    });

    testWidgets('a workout share draws the log sheet, not a glyph for it',
        (tester) async {
      await tester.pumpWidget(
        host(
          SharedPostCard(
            width: 280,
            post: SharedPostRef.fromFeedPost(
              _post(postType: PostType.workout, workoutData: _legDay),
            ),
          ),
        ),
      );

      expect(find.byType(WorkoutSummaryCard), findsOneWidget);
      expect(find.text('Leg day'), findsOneWidget);
      expect(find.text('Squat'), findsOneWidget);
      expect(find.text('Lunge'), findsOneWidget);
      expect(find.text('WORKOUT'), findsNothing);
    });

    testWidgets('a workout share on a photo draws the sheet over the photo',
        (tester) async {
      await tester.pumpWidget(
        host(
          SharedPostCard(
            width: 280,
            post: SharedPostRef.fromFeedPost(
              _post(
                postType: PostType.workout,
                imageUrl: 'https://example.com/gym.jpg',
                workoutData: _legDay,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(WorkoutSummaryCard), findsOneWidget);
      expect(find.byKey(WorkoutSummaryCard.backdropKey), findsOneWidget);
      expect(find.text('Squat'), findsOneWidget);
    });

    testWidgets(
        'a workout share written before the log was carried keeps the label',
        (tester) async {
      await tester.pumpWidget(
        host(
          SharedPostCard(
            post: SharedPostRef.fromMap(const {
              'postId': 'p1',
              'kind': 'workout',
            })!,
          ),
        ),
      );

      expect(find.text('WORKOUT'), findsOneWidget);
      expect(find.byType(WorkoutSummaryCard), findsNothing);
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

/// The share screen, mounted the way the router mounts it: the post rides in
/// as a snapshot, and nothing is read until Share is pressed.
Future<void> pumpShareScreen(WidgetTester tester, FeedPost post) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.dark]),
        home: SharePostToPulseScreen(post: SharedPostRef.fromFeedPost(post)),
      ),
    ),
  );
  await tester.pump();
}

void runShareScreenTests() {
  group('sharing a run to Pulse', () {
    final run = _post(
      postType: PostType.run,
      imageUrl: 'https://example.com/run.jpg',
      routePoints: const [
        RoutePoint(latitude: 1, longitude: 1),
        RoutePoint(latitude: 2, longitude: 2),
      ],
    );

    testWidgets(
        'mounts the card with its photo, and offers the text tool '
        'and the backdrop wheel', (tester) async {
      await pumpShareScreen(tester, run);

      expect(find.byType(SharedPostCard), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(RouteSparkline), findsOneWidget);
      expect(find.byTooltip('Add text'), findsOneWidget);
      expect(find.byTooltip('Change background'), findsOneWidget);
      expect(find.text('Share Pulse'), findsOneWidget);
    });

    testWidgets('the wheel steps the mount to the next backdrop',
        (tester) async {
      await pumpShareScreen(tester, run);

      LinearGradient mount() {
        final boxes = tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .map((box) => box.decoration)
            .whereType<BoxDecoration>()
            .map((decoration) => decoration.gradient)
            .whereType<LinearGradient>();
        return boxes.first;
      }

      final before = mount();
      await tester.tap(find.byTooltip('Change background'));
      await tester.pump();

      expect(mount(), isNot(equals(before)));
    });

    testWidgets('the text tool opens over the card', (tester) async {
      await pumpShareScreen(tester, run);

      await tester.tap(find.byTooltip('Add text'));
      await tester.pump();

      expect(find.byType(PulseTextEditor), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });
  });
}
