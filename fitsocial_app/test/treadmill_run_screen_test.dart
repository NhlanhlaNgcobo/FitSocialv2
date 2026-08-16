import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/music/application/music_presence_provider.dart';
import 'package:fitsocial_app/features/music/application/music_providers.dart';
import 'package:fitsocial_app/features/music/domain/music_presence.dart';
import 'package:fitsocial_app/features/tracking/application/tracking_providers.dart';
import 'package:fitsocial_app/features/tracking/data/treadmill_run_service.dart';
import 'package:fitsocial_app/features/tracking/presentation/treadmill_run_screen.dart';

void main() {
  late DateTime now;
  late TreadmillRunService service;

  void advance(Duration by) => now = now.add(by);

  setUp(() {
    now = DateTime(2026, 8, 16, 7);
    service = TreadmillRunService(now: () => now);
  });

  /// Pumps the screen with everything the phone would normally supply — a heart
  /// strap, a music account — stubbed out, so what is left under test is the
  /// timer and the one field the runner fills in.
  Future<void> pumpScreen(WidgetTester tester) async {
    // A phone-shaped surface: the default 800x600 test window leaves the run
    // controls below the fold, where they cannot be tapped.
    tester.view.physicalSize = const Size(440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          treadmillRunServiceProvider.overrideWithValue(service),
          liveHeartRateProvider.overrideWith((ref) => const Stream<int>.empty()),
          musicPresenceProvider.overrideWithValue(MusicPresence.none),
          musicConnectionsProvider.overrideWith(_NoMusic.new),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const TreadmillRunScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  /// Leaves no ticker running: a live run holds a periodic timer, and the test
  /// binding fails the test if one outlives it.
  Future<void> finishTicker(WidgetTester tester) async {
    service.stop();
    await tester.pump();
    service.dispose();
  }

  testWidgets('opens ready, on a zeroed clock', (tester) async {
    await pumpScreen(tester);

    expect(find.text('READY'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('Start Treadmill Run'), findsOneWidget);
    // Nothing to pause or finish before there is a run.
    expect(find.text('Finish'), findsNothing);

    await finishTicker(tester);
  });

  testWidgets('start runs the clock off the wall clock, not off frames',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Start Treadmill Run'));
    await tester.pump();

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('Finish'), findsOneWidget);

    // Nine minutes pass with a single frame drawn — the locked-phone case.
    advance(const Duration(minutes: 9, seconds: 30));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('09:30'), findsOneWidget);

    await finishTicker(tester);
  });

  testWidgets('pausing holds the clock and offers to resume', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Start Treadmill Run'));
    advance(const Duration(minutes: 4));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    advance(const Duration(minutes: 15));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('PAUSED'), findsOneWidget);
    expect(find.text('04:00'), findsOneWidget);
    // The circle has become the way back into the run.
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    await finishTicker(tester);
  });

  testWidgets('the typed distance drives the pace on the card', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Start Treadmill Run'));
    advance(const Duration(minutes: 30));
    await tester.pump(const Duration(seconds: 1));

    await tester.enterText(find.byType(TextField), '5');
    await tester.pump();

    expect(find.text('5 km'), findsOneWidget);
    expect(find.text('6:00'), findsOneWidget);

    await finishTicker(tester);
  });

  testWidgets('finishing without a distance keeps the run alive',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Start Treadmill Run'));
    advance(const Duration(minutes: 20));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Finish'));
    await tester.pump();

    expect(
      find.text(
        'Enter the distance from the treadmill display before finishing.',
      ),
      findsOneWidget,
    );
    // The whole point of asking before stopping: the clock is still counting,
    // so the runner can go and read the machine.
    expect(find.text('LIVE'), findsOneWidget);
    expect(service.current.isTracking, isTrue);

    await finishTicker(tester);
  });
}

/// A runner with no music account linked — the state the screen shows a connect
/// card for.
class _NoMusic extends MusicConnectionsController {
  _NoMusic(super.ref) {
    state = const MusicConnectionsState(services: {});
  }
}
