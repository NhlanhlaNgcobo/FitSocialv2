import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/shared_post.dart';
import 'package:fitsocial_app/shared/services/run_card_exporter.dart';
import 'package:fitsocial_app/shared/services/workout_card_exporter.dart';
import 'package:fitsocial_app/shared/widgets/share_sheet.dart';

const _route = [
  RoutePoint(latitude: -26.20, longitude: 28.00),
  RoutePoint(latitude: -26.21, longitude: 28.02),
];

final _post = SharedPostRef.of(
  postId: 'p1',
  authorId: 'u1',
  authorName: 'Sam',
  activity: 'Run',
  route: _route,
);

const _card = RunCardExport(
  route: _route,
  distanceLabel: '5.2 km',
  durationLabel: '28:14',
);

const _workoutCard = WorkoutCardExport(
  activity: 'Workout',
  workoutData: {
    'title': 'Legs',
    'exercises': [
      {'name': 'Squat', 'sets': 5, 'reps': 8},
    ],
  },
);

/// Opens the share sheet and leaves it up.
Future<void> openSheet(
  WidgetTester tester, {
  RunCardExport? runCard,
  WorkoutCardExport? workoutCard,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPostShareSheet(
              context,
              _post,
              runCard: runCard,
              workoutCard: workoutCard,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('offers to save the image on a post that draws a run card',
      (tester) async {
    await openSheet(tester, runCard: _card);

    expect(find.text('Save image'), findsOneWidget);
    // Still last, after the three link rows it does not belong to.
    expect(
      tester.getTopLeft(find.text('Save image')).dy,
      greaterThan(tester.getTopLeft(find.text('Copy link')).dy),
    );
  });

  testWidgets('offers to save the image on a post that draws a workout card',
      (tester) async {
    await openSheet(tester, workoutCard: _workoutCard);

    expect(find.text('Save image'), findsOneWidget);
  });

  testWidgets('leaves the row out when there is no card to draw',
      (tester) async {
    await openSheet(tester);

    expect(find.text('Save image'), findsNothing);
    // The rows that were always there are untouched.
    expect(find.text('Add to your Pulse'), findsOneWidget);
    expect(find.text('Share to…'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
  });
}
