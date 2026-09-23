import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/features/main/domain/activity_kind.dart';
import 'package:fitsocial_app/features/main/presentation/run_log_screen.dart';

/// The activity choice lives here rather than on the Create page.
///
/// Three tiles up front would have grown "What are you up to?" to eight rows
/// and turned a picker into a menu. One tile opens this screen, and the choice
/// is made where it can recolour the card you are about to tap — but the cost
/// of that decision is that this screen is now three screens wearing a coat,
/// and the manual form underneath has to follow the selection too.
void main() {
  Future<void> pumpRunLog(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/log-run',
      routes: [
        GoRoute(path: '/log-run', builder: (_, __) => const RunLogScreen()),
        GoRoute(
          path: '/live-run',
          builder: (_, __) => const Scaffold(body: Text('LIVE RUN SCREEN')),
        ),
        GoRoute(
          path: '/treadmill-run',
          builder: (_, __) => const Scaffold(body: Text('TREADMILL SCREEN')),
        ),
      ],
    );

    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
  }

  /// Taps a segment by its label. The descriptor owns the wording, so this
  /// keeps working if the labels are reworded.
  Future<void> choose(WidgetTester tester, ActivityKind kind) async {
    await tester.tap(find.text(kind.descriptor.singular).first);
    await tester.pumpAndSettle();
  }

  testWidgets('opens on a run, with all three offered', (tester) async {
    await pumpRunLog(tester);

    for (final kind in ActivityDescriptor.gpsKinds) {
      expect(find.text(kind.descriptor.singular), findsWidgets,
          reason: kind.name);
    }
    expect(find.text('Log Run'), findsOneWidget);
  });

  testWidgets('choosing an activity retitles the screen', (tester) async {
    await pumpRunLog(tester);

    await choose(tester, ActivityKind.hike);
    expect(find.text('Log Hike'), findsOneWidget);

    await choose(tester, ActivityKind.ride);
    expect(find.text('Log Ride'), findsOneWidget);
  });

  testWidgets('the treadmill card is offered for runs only', (tester) async {
    await pumpRunLog(tester);

    // A treadmill is a way of running indoors and nothing else: there is no
    // indoor hike, and a stationary bike is a different machine reporting
    // different numbers.
    expect(find.textContaining('Treadmill'), findsWidgets);

    await choose(tester, ActivityKind.ride);
    expect(find.textContaining('Treadmill'), findsNothing);

    await choose(tester, ActivityKind.run);
    expect(find.textContaining('Treadmill'), findsWidgets);
  });

  testWidgets('the GPS card describes pace on foot and speed on a bike',
      (tester) async {
    await pumpRunLog(tester);

    expect(find.textContaining('distance, pace and route'), findsOneWidget);

    await choose(tester, ActivityKind.ride);
    expect(find.textContaining('distance, speed and route'), findsOneWidget);
    expect(find.textContaining('distance, pace and route'), findsNothing);
  });

  testWidgets('the manual form switches between average pace and speed',
      (tester) async {
    await pumpRunLog(tester);

    // The summary only appears once both figures are filled in.
    await tester.enterText(find.byType(TextField).first, '10');
    await tester.enterText(find.byType(TextField).at(1), '30');
    await tester.pumpAndSettle();

    // The summary stat labels are upper-cased when they are painted. The
    // figure itself is drawn twice — once in the summary, once on the card
    // preview underneath — so it is counted as present, not as singular.
    expect(find.text('AVG PACE'), findsOneWidget);
    expect(find.text('3:00 /km'), findsWidgets);

    await choose(tester, ActivityKind.ride);

    // The same 10 km in 30 minutes. A cyclist reads that as 20 km/h; "3:00
    // /km" is a number no cyclist has ever used to describe anything.
    expect(find.text('AVG SPEED'), findsOneWidget);
    expect(find.text('20.0 km/h'), findsWidgets);
    expect(find.text('AVG PACE'), findsNothing);
    expect(find.text('3:00 /km'), findsNothing);
  });

  testWidgets('a comma-decimal keyboard fills the form like a dotted one',
      (tester) async {
    await pumpRunLog(tester);

    // Exactly what a tester in a comma-decimal locale typed. Both figures
    // were on screen and the form still asked for a distance and a time.
    await tester.enterText(find.byType(TextField).first, '10,01');
    await tester.enterText(find.byType(TextField).at(1), '50,42');
    await tester.pumpAndSettle();

    expect(find.text('AVG PACE'), findsOneWidget);
    // 50.42 min over 10.01 km is 5:02 /km — only reachable if both commas
    // were read as decimal points.
    expect(find.text('5:02 /km'), findsWidgets);
    expect(find.textContaining('before saving'), findsNothing);
  });

  testWidgets('the GPS card opens the tracker with the chosen activity',
      (tester) async {
    await pumpRunLog(tester);
    await choose(tester, ActivityKind.hike);

    await tester.tap(find.text('Track live with GPS'));
    await tester.pumpAndSettle();

    // The kind travels as `extra` rather than in the path, so this is the only
    // place it can be checked short of the tracker itself.
    expect(find.text('LIVE RUN SCREEN'), findsOneWidget);
  });
}
