import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/challenges/application/running_challenge_providers.dart';
import 'package:fitsocial_app/features/challenges/domain/running_challenge.dart';
import 'package:fitsocial_app/features/challenges/presentation/challenge_invite_sheet.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';

/// The invite sheet offering the action that will actually work.
///
/// A tester sent invitations to a whole group, and every tap after the first
/// came back as "that invitation could not be sent" — the sheet had no idea who
/// it had already asked, so it kept offering Invite to people who were already
/// on the challenge or already holding an invitation.
void main() {
  testWidgets('somebody with no standing is offered an invitation',
      (tester) async {
    await _pump(tester, const {});

    expect(find.text('Invite'), findsOneWidget);
  });

  testWidgets('somebody still deciding is offered a resend', (tester) async {
    await _pump(tester, {'u1': ParticipantStatus.invited});

    expect(find.text('Resend'), findsOneWidget);
    expect(find.text('Invite'), findsNothing);
  });

  testWidgets('somebody already on the challenge is not offered anything',
      (tester) async {
    await _pump(tester, {'u1': ParticipantStatus.active});

    expect(find.text('On the challenge'), findsOneWidget);
    expect(find.text('Invite'), findsNothing);
    expect(find.text('Resend'), findsNothing);
  });

  testWidgets('a finisher reads the same as anybody else competing',
      (tester) async {
    await _pump(tester, {'u1': ParticipantStatus.completed});

    expect(find.text('On the challenge'), findsOneWidget);
  });

  testWidgets('an answered no is said, not offered again', (tester) async {
    await _pump(tester, {'u1': ParticipantStatus.declined});

    expect(find.text('Declined'), findsOneWidget);
    expect(find.text('Invite'), findsNothing);
    expect(find.text('Resend'), findsNothing);
  });
}

const _challenge = RunningChallenge(
  id: 'c1',
  creatorId: 'me',
  title: 'September 100',
  goalValueKm: 100,
  startDayKey: '2026-09-01',
  endDayKey: '2026-09-30',
  utcOffsetMinutes: 120,
);

Future<void> _pump(
  WidgetTester tester,
  Map<String, ParticipantStatus> standings,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('me'),
        // One person followed, so there is exactly one row to read.
        followingIdsProvider.overrideWith((ref) => Stream.value({'u1'})),
        userProfileProvider('u1').overrideWith(
          (ref) async => const UserSearchResult(
            id: 'u1',
            displayName: 'Blk',
            handle: '@blk',
            initials: 'B',
            postsCount: 0,
          ),
        ),
        challengeParticipantsProvider('c1').overrideWith(
          (ref) => Stream.value([
            for (final entry in standings.entries)
              ChallengeParticipant(
                userId: entry.key,
                challengeId: 'c1',
                status: entry.value,
              ),
          ]),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showChallengeInviteSheet(context, _challenge),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.text('Blk'), findsOneWidget);
}
