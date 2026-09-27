// Clips for the launch video: real scrolling and real animation, frame by frame.
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/challenges/data/running_challenge_repository.dart';
import 'package:fitsocial_app/features/challenges/presentation/challenge_board_screen.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/application/create_flow_controller.dart';
import 'package:fitsocial_app/features/main/presentation/home_screen.dart';
import 'package:fitsocial_app/features/main/presentation/meal_review_screen.dart';
import 'package:fitsocial_app/features/pulse/application/pulse_providers.dart';
import 'package:fitsocial_app/features/pulse/presentation/pulse_viewer_screen.dart';
import 'package:fitsocial_app/features/safety/presentation/hold_to_alert.dart';
import 'package:fitsocial_app/features/safety/presentation/safety_screen.dart';

import 'challenge_board_test.dart' show ShotChallenges;
import 'meal_review_test.dart' show mealFlow;
import 'pulse_viewer_test.dart' show pulseOverrides;
import 'safety_test.dart' show safetyOverrides;
import 'shot_data.dart';
import 'shot_fakes.dart';
import 'shot_harness.dart';

void main() {
  testWidgets('home scroll', (tester) async {
    await shootFrames(
      tester,
      'clip_home_scroll',
      shotApp(inShell(const HomeScreen()), overrides: [
        ...signedIn(),
        feedPostsProvider.overrideWith(
            (ref) => FeedPostsNotifier(const ShotContent(), null)),
        activePulsesProvider.overrideWith((ref) => Stream.value(trayPulses)),
        pulseSeenMarkersProvider
            .overrideWith((ref) => Stream.value(const <String, DateTime>{})),
      ]),
      count: 126,
      step: scrollStep(0, 1010),
    );
  });

  testWidgets('meal scroll', (tester) async {
    await shootFrames(
      tester,
      'clip_meal_scroll',
      shotApp(const MealReviewScreen(), pushed: true, overrides: [
        ...baseFakes,
        createFlowControllerProvider.overrideWith((ref) => mealFlow()),
      ]),
      count: 108,
      step: scrollStep(0, 640),
    );
  });

  testWidgets('challenge scroll', (tester) async {
    await shootFrames(
      tester,
      'clip_challenge_scroll',
      shotApp(const ChallengeBoardScreen(challengeId: 'ch-100k'),
          pushed: true,
          overrides: [
            ...signedIn(),
            runningChallengeRepositoryProvider
                .overrideWithValue(ShotChallenges()),
          ]),
      count: 66,
      step: scrollStep(0, 300),
    );
  });

  testWidgets('pulse playing', (tester) async {
    await shootFrames(
      tester,
      'clip_pulse_play',
      shotApp(const PulseViewerScreen(initialAuthorId: 'u-lerato'),
          pushed: true, overrides: pulseOverrides()),
      count: 78,
      step: tickStep,
    );
  });

  testWidgets('sos hold', (tester) async {
    TestGesture? finger;
    await shootFrames(
      tester,
      'clip_sos_hold',
      shotApp(const SafetyScreen(), pushed: true, overrides: safetyOverrides()),
      // Lands on the 10th frame, holds to just short of sending.
      count: 66,
      step: (t, i, _) async {
        if (i == 9) {
          finger = await t.startGesture(t.getCenter(find.byType(HoldToAlertButton)));
        }
        await t.pump(const Duration(microseconds: 33333));
      },
    );
    await finger?.cancel();
  });
}
