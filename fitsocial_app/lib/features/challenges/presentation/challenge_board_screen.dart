import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/confirm_destructive_sheet.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/glass.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider;
import '../application/running_challenge_providers.dart';
import '../domain/running_challenge.dart';
import 'challenge_indicators.dart';
import 'challenge_invite_sheet.dart';
import 'challenge_leaderboard.dart';

/// One running challenge, in full.
///
/// The sections are the ones the specification requires, in its order: what the
/// challenge is, where you are in it, your consistency, everybody's standing,
/// what you have actually run, and the controls for joining, inviting and
/// leaving.
class ChallengeBoardScreen extends ConsumerWidget {
  const ChallengeBoardScreen({required this.challengeId, super.key});

  final String challengeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final challenge = ref.watch(runningChallengeProvider(challengeId));

    return Scaffold(
      appBar: AppBar(title: const Text('CHALLENGE')),
      body: challenge.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // A private challenge the caller may not read comes back as a
        // permission error, which is indistinguishable from "no such challenge"
        // on purpose — telling somebody a private challenge exists is most of
        // what keeping it private is meant to prevent.
        error: (_, __) => _Missing(palette: palette),
        data: (value) => value == null
            ? _Missing(palette: palette)
            : _Board(challenge: value),
      ),
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          'This challenge is not available.',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.muted),
        ),
      ),
    );
  }
}

class _Board extends ConsumerWidget {
  const _Board({required this.challenge});

  final RunningChallenge challenge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myParticipantProvider(challenge.id)).valueOrNull;
    final myId = ref.watch(currentUserIdProvider);
    final isCreator = myId != null && myId == challenge.creatorId;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        40,
      ),
      children: [
        _Header(challenge: challenge),
        const SizedBox(height: AppSpacing.lg),

        if (me != null && me.status.isCounting) ...[
          const ChallengeLabel('MY PROGRESS'),
          const SizedBox(height: 10),
          _MyProgress(challenge: challenge, participant: me),
          const SizedBox(height: AppSpacing.lg),
        ],

        if (me != null && me.status == ParticipantStatus.invited) ...[
          _InviteDecision(challenge: challenge),
          const SizedBox(height: AppSpacing.lg),
        ],

        const ChallengeLabel('LEADERBOARD'),
        const SizedBox(height: 10),
        ChallengeLeaderboard(challengeId: challenge.id, challenge: challenge),
        const SizedBox(height: AppSpacing.lg),

        // Run-by-run history, which an activity challenge does not keep: its
        // days are the daily stats, already on the user's own screens.
        if (me != null && me.status.isCounting && !challenge.isActivity) ...[
          const ChallengeLabel('RECENT ACTIVITY'),
          const SizedBox(height: 10),
          _RecentActivity(challengeId: challenge.id),
          const SizedBox(height: AppSpacing.lg),
        ],

        _Controls(challenge: challenge, participant: me, isCreator: isCreator),
      ],
    );
  }
}

/// Title, dates, participant count and time remaining.
class _Header extends StatelessWidget {
  const _Header({required this.challenge});

  final RunningChallenge challenge;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final remaining = challenge.daysRemaining();
    final ended = challenge.hasEnded() ||
        challenge.status != RunningChallengeStatus.active;

    return DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  challenge.title,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (challenge.visibility.isPrivate)
                Icon(Icons.lock_rounded, size: 16, color: palette.muted),
            ],
          ),
          if (challenge.description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              challenge.description,
              style: TextStyle(color: palette.muted, fontSize: 13),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${challenge.goalLabel}  ·  '
            '${challenge.startDayKey} to ${challenge.endDayKey}',
            style: TextStyle(color: palette.muted, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            ended
                ? 'Finished  ·  ${_people(challenge.participantCount)}'
                : '$remaining ${remaining == 1 ? "day" : "days"} left'
                    '  ·  ${_people(challenge.participantCount)}',
            style: TextStyle(
              color: ended ? palette.muted : palette.brand,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Current metric against goal, the bar, and the three consistency figures.
class _MyProgress extends StatelessWidget {
  const _MyProgress({required this.challenge, required this.participant});

  final RunningChallenge challenge;
  final ChallengeParticipant participant;

  @override
  Widget build(BuildContext context) {
    if (challenge.isActivity) {
      return _MyActivityProgress(
        challenge: challenge,
        participant: participant,
      );
    }
    final palette = context.palette;
    // Aged against today rather than shown as stored: somebody whose last
    // qualifying run was three days ago has a streak of zero now, and the board
    // should say so without waiting for a job to notice.
    final streak = participant.currentStreakAsOf(challenge.clock.today());

    return DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _km(participant.totalDistanceKm),
                style: TextStyle(
                  color: palette.text,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '/ ${challenge.goalValueKm.round()} km',
                  style: TextStyle(color: palette.muted, fontSize: 15),
                ),
              ),
              const Spacer(),
              Text(
                '${participant.completionPercentage.round()}%',
                style: TextStyle(
                  color: palette.brand,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: participant.fraction,
              minHeight: 8,
              backgroundColor: palette.stroke,
              valueColor: AlwaysStoppedAnimation(palette.brand),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _Figure(label: 'Current streak', value: '$streak'),
              _Figure(
                label: 'Completed days',
                value: '${participant.completedDays}',
              ),
              _Figure(
                label: 'Longest streak',
                value: '${participant.longestStreak}',
              ),
            ],
          ),
          if (participant.rank > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Ranked #${participant.rank} of '
              '${_people(challenge.participantCount)}',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: palette.text,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: TextStyle(color: palette.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// The days that actually counted, most recent first.
class _RecentActivity extends ConsumerWidget {
  const _RecentActivity({required this.challengeId});

  final String challengeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final days = ref.watch(myChallengeDaysProvider(challengeId)).valueOrNull;

    if (days == null || days.isEmpty) {
      return Text(
        'No qualifying runs yet.',
        style: TextStyle(color: palette.muted),
      );
    }

    return Column(
      children: [
        for (final day in days)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                Icon(
                  day.qualified
                      ? Icons.check_circle_rounded
                      : Icons.remove_circle_outline_rounded,
                  size: 16,
                  color: day.qualified ? palette.success : palette.muted,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    day.dayKey,
                    style: TextStyle(color: palette.text, fontSize: 13),
                  ),
                ),
                Text(
                  '${_km(day.distanceKm)} km'
                  '${day.runCount > 1 ? "  ·  ${day.runCount} runs" : ""}',
                  style: TextStyle(color: palette.muted, fontSize: 13),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Accept or decline an outstanding invitation.
class _InviteDecision extends ConsumerWidget {
  const _InviteDecision({required this.challenge});

  final RunningChallenge challenge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final actions = ref.read(runningChallengeActionsProvider);

    // The one card here using colour to mean something rather than to decorate,
    // so the colour goes *under* the lens as a bloom and arrives bent along
    // with everything else -- a flat brand fill on top of the pane would be the
    // one surface on the screen that is not glass.
    return DarkCard(
      backdrop: GlassBloom(colors: [palette.brand]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You have been invited to this challenge.',
            style: TextStyle(color: palette.text, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => actions.accept(challenge.id),
                  child: const Text('Accept'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => actions.decline(challenge.id),
                  child: const Text('Decline'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Join, invite, share and leave — whichever the viewer is entitled to.
class _Controls extends ConsumerWidget {
  const _Controls({
    required this.challenge,
    required this.participant,
    required this.isCreator,
  });

  final RunningChallenge challenge;
  final ChallengeParticipant? participant;
  final bool isCreator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final actions = ref.read(runningChallengeActionsProvider);
    final me = participant;
    final open = challenge.isRunning();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Joining is offered only on a public challenge that is still running
        // and still has room. A private one is reached by invitation, and the
        // rules refuse a self-join on it whatever the app shows.
        if (me == null &&
            open &&
            !challenge.visibility.isPrivate &&
            challenge.hasRoom)
          FilledButton(
            onPressed: () => actions.join(challenge),
            child: const Text('Join challenge'),
          ),

        if (me == null && open && !challenge.hasRoom)
          Text(
            'This challenge is full.',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted),
          ),

        if (isCreator && open) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => showChallengeInviteSheet(context, challenge),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('Invite someone'),
          ),
        ],

        if (me != null && me.status.isCounting && open) ...[
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () async {
              final confirmed = await confirmDestructiveAction(
                context,
                title: 'Leave this challenge?',
                message: 'Your distance and streak stay on record, but they '
                    'stop counting from now on. Re-joining starts you over.',
                confirmLabel: 'Leave',
                icon: Icons.logout_rounded,
              );
              if (!confirmed) return;
              await actions.leave(challenge.id);
              if (context.mounted) context.pop();
            },
            child: Text('Leave challenge',
                style: TextStyle(color: palette.danger)),
          ),
        ],
      ],
    );
  }
}

String _people(int count) => '$count ${count == 1 ? "person" : "people"}';

String _km(double value) {
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

/// An activity challenge's own figures: the metric, how far toward the
/// target or along the streak, and the place.
class _MyActivityProgress extends StatelessWidget {
  const _MyActivityProgress({
    required this.challenge,
    required this.participant,
  });

  final RunningChallenge challenge;
  final ChallengeParticipant participant;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fraction = participant.activityFraction(challenge);
    final reached = participant.targetReachedDayKey != null;

    return DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  participant.activityHeadline(challenge),
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
              const Spacer(),
              if (reached)
                Icon(Icons.check_circle_rounded, color: palette.success),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            participant.activityDetail(challenge),
            style: TextStyle(color: palette.muted, fontSize: 13),
          ),
          if (fraction != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: palette.stroke,
                valueColor: AlwaysStoppedAnimation(
                  reached ? palette.success : palette.brand,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            participant.finalRank != null
                ? 'Finished #${participant.finalRank} of '
                    '${_people(challenge.participantCount)}'
                : participant.rank > 0
                    ? 'Ranked #${participant.rank} of '
                        '${_people(challenge.participantCount)}'
                    : 'Counting from the day you joined. Updates a minute or '
                        'two after a log or a step sync.',
            style: TextStyle(color: palette.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
