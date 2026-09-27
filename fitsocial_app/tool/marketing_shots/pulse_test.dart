import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/shared_post.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fitsocial_app/features/pulse/application/pulse_providers.dart';
import 'package:fitsocial_app/features/pulse/domain/pulse_models.dart';
import 'package:fitsocial_app/features/pulse/presentation/pulse_composer_screen.dart';
import 'package:fitsocial_app/features/pulse/presentation/pulse_viewer_screen.dart';
import 'package:fitsocial_app/features/pulse/presentation/share_post_to_pulse_screen.dart';

import 'pulse_viewer_test.dart' show pulseOverrides;
import 'shot_data.dart';
import 'shot_fakes.dart';
import 'shot_harness.dart';

SharedPostRef siphoRunRef() {
  final p = homeFeedPosts.first;
  return SharedPostRef.of(
    postId: p.id,
    authorId: p.authorId,
    authorName: p.userName,
    activity: p.activity,
    caption: p.caption,
    route: p.routePoints,
  );
}

void main() {
  testWidgets('composer', (tester) async {
    await shoot(tester, 'pulse_composer',
        shotApp(const PulseComposerScreen(), pushed: true, overrides: [...signedIn(), ...pulseOverrides()]));
  });

  testWidgets('text pulse clip', (tester) async {
    const text = 'Comrades in 8 weeks. No days off.';
    await shootFrames(
      tester,
      'clip_pulse_text',
      shotApp(const PulseComposerScreen(), pushed: true,
          overrides: [...signedIn(), ...pulseOverrides()]),
      count: 112,
      step: (t, i, _) async {
        if (i == 8) await t.tap(find.byIcon(Icons.format_quote_rounded));
        if (i == 16) await t.tap(find.text('Say something'));
        if (i >= 20 && i <= 58) {
          final n = ((i - 20) / 38 * text.length).round().clamp(1, text.length);
          await t.enterText(find.byType(TextField).last, text.substring(0, n));
        }
        if (i == 66) await t.tap(find.text('Neon').last);
        // The chip row scrolls; bring Strong in the way a thumb would.
        if (i == 74) await t.drag(find.text('Typewriter').last, const Offset(-220, 0));
        if (i == 84) await t.tap(find.text('Strong').last);
        if (i == 96) await t.tap(find.text('Done').last);
        await t.pump(const Duration(microseconds: 33333));
      },
    );
  });

  testWidgets('own pulse viewers', (tester) async {
    final now = DateTime.now();
    await shoot(
      tester,
      'pulse_own_viewers',
      shotApp(const PulseViewerScreen(initialAuthorId: 'u-sipho'), pushed: true, overrides: [
        ...signedIn(),
        activePulsesProvider.overrideWith((ref) => Stream.value(trayPulses)),
        pulseSeenMarkersProvider
            .overrideWith((ref) => Stream.value(const <String, DateTime>{})),
        pulseTrayProvider.overrideWithValue(AsyncValue.data(buildPulseTray(
          segments: trayPulses,
          seenMarkers: const {},
          currentUserId: 'u-sipho',
          now: now,
        ))),
        pulseViewersProvider.overrideWith((ref, id) => Stream.value([
              for (final (i, p) in people.values.where((p) => p.id != 'u-sipho').indexed)
                PulseViewerRecord(
                    userId: p.id, name: p.displayName,
                    viewedAt: now.subtract(Duration(minutes: 7 + i * 11))),
            ])),
      ]),
      before: (t) async {
        await t.tap(find.text('34'));
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      },
    );
  });

  testWidgets('share post', (tester) async {
    await shoot(tester, 'pulse_share_post',
        shotApp(SharePostToPulseScreen(post: siphoRunRef()), pushed: true,
            overrides: [...signedIn(), ...pulseOverrides()]));
  });
}
