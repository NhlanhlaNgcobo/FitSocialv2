import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/pulse/application/pulse_providers.dart';
import 'package:fitsocial_app/features/pulse/domain/pulse_models.dart';
import 'package:fitsocial_app/features/pulse/presentation/pulse_viewer_screen.dart';

import 'shot_data.dart';
import 'shot_fakes.dart';
import 'shot_harness.dart';

List<Override> pulseOverrides() => [
      ...baseFakes,
      currentUserIdProvider.overrideWithValue('u-me'),
      activePulsesProvider.overrideWith((ref) => Stream.value(trayPulses)),
      pulseSeenMarkersProvider
          .overrideWith((ref) => Stream.value(const <String, DateTime>{})),
      // Loaded before the viewer opens, the way it is when you tap a ring.
      pulseTrayProvider.overrideWithValue(AsyncValue.data(buildPulseTray(
        segments: trayPulses,
        seenMarkers: const {},
        currentUserId: 'u-me',
        now: DateTime.now(),
      ))),
    ];

void main() {
  testWidgets('pulse viewer', (tester) async {
    await shoot(
      tester,
      'pulse_viewer',
      shotApp(const PulseViewerScreen(initialAuthorId: 'u-lerato'),
          pushed: true, overrides: pulseOverrides()),
    );
  });
}
