import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/shared_post.dart';
import 'package:fitsocial_app/features/pulse/application/pulse_providers.dart';
import 'package:fitsocial_app/features/pulse/domain/pulse_models.dart';
import 'package:fitsocial_app/features/pulse/presentation/pulse_viewer_screen.dart';
import 'package:fitsocial_app/shared/reactions/fit_reaction.dart';
import 'package:fitsocial_app/shared/widgets/shared_post_card.dart';

/// Viewing never writes anything a test cares about.
class _QuietActions implements PulseActions {
  @override
  Future<void> markSeen(PulseSegment segment) async {}

  @override
  Future<void> recordView(String pulseId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('a long workout share fits between the header and the reactions',
      (tester) async {
    // The Galaxy A06: 720 x 1600 at 1.875, where a twelve-exercise log sheet
    // overflowed the frame by hundreds of pixels.
    tester.view.devicePixelRatio = 1.875;
    tester.view.physicalSize = const Size(720, 1600);
    addTearDown(tester.view.reset);

    final segment = PulseSegment(
      id: 's1',
      authorId: 'daisy',
      authorName: 'Daisy',
      type: PulseMediaType.post,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
      sharedPost: SharedPostRef.fromMap({
        'postId': 'p1',
        'authorId': 'daisy',
        'authorName': 'Daisy',
        'activity': 'Gym',
        'caption': 'Push day done',
        'kind': 'workout',
        'workoutData': {
          'title': 'Push day',
          'duration': '75 min',
          'calories': '540 kcal',
          'exercises': [
            for (var i = 0; i < 12; i++)
              {'name': 'Exercise $i', 'sets': 4, 'reps': 10, 'weightKg': 40},
          ],
        },
      }),
    );
    final entry = PulseTrayEntry(
      authorId: 'daisy',
      authorName: 'Daisy',
      segments: [segment],
      isOwn: false,
      hasUnseen: true,
      firstUnseenIndex: 0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pulseTrayProvider.overrideWithValue(AsyncValue.data([entry])),
          activePulsesProvider.overrideWith((ref) => Stream.value([segment])),
          myFitReactionProvider
              .overrideWith((ref, id) => Stream<FitReaction?>.value(null)),
          pulseActionsProvider.overrideWithValue(_QuietActions()),
        ],
        child: const MaterialApp(
          home: PulseViewerScreen(initialAuthorId: 'daisy'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    final card = tester.getRect(find.byType(SharedPostCard));
    final comment = tester.getRect(find.text('Comment'));
    expect(card.bottom, lessThan(comment.top));

    // Leave before the frame timer runs out and tries to pop a route that
    // this test never pushed.
    await tester.pumpWidget(const SizedBox());
  });
}
