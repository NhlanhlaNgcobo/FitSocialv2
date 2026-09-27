import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:fitsocial_app/features/tracking/application/tracking_providers.dart';
import 'package:fitsocial_app/features/tracking/data/live_run_service.dart';
import 'package:fitsocial_app/features/tracking/presentation/live_run_screen.dart';

import 'shot_data.dart';
import 'shot_fakes.dart';
import 'shot_harness.dart';

LiveRunState liveRun() {
  final route = durbanBeachfront();
  final trail = route.take((route.length * 0.42).round()).toList();
  final start = DateTime.now().subtract(const Duration(minutes: 23, seconds: 5));
  return LiveRunState(
    isTracking: true,
    isPaused: false,
    isAutoPaused: false,
    distanceKm: 4.21,
    elapsed: const Duration(minutes: 23, seconds: 5),
    movingElapsed: const Duration(minutes: 23, seconds: 5),
    currentPaceMinPerKm: 5 + 29 / 60,
    startedAt: start,
    points: [
      for (var i = 0; i < trail.length; i++)
        RunPoint(
          latitude: trail[i].latitude,
          longitude: trail[i].longitude,
          timestamp: start.add(Duration(seconds: i * 18)),
        ),
    ],
    routePoints: [for (final p in trail) LatLng(p.latitude, p.longitude)],
  );
}

void main() {
  testWidgets('live run', (tester) async {
    await shoot(
      tester,
      'live_run',
      shotApp(const LiveRunScreen(), pushed: true, overrides: [
        ...baseFakes,
        liveRunStateProvider.overrideWith((ref) => Stream.value(liveRun())),
      ]),
    );
  });
}
