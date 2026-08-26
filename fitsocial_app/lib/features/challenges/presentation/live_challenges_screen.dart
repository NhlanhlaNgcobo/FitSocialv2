import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/running_challenge_providers.dart';
import '../domain/running_challenge.dart';

/// Public challenges anyone can join.
///
/// Only public, active challenges appear here, and that is enforced by the
/// query rather than by this screen — see
/// [RunningChallengeRepository.watchPublicChallenges]. A private challenge
/// cannot reach this list even by accident.
class LiveChallengesScreen extends ConsumerWidget {
  const LiveChallengesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final challenges = ref.watch(publicChallengesProvider);
    final mine = ref.watch(myActiveParticipationsProvider);
    final joinedIds = mine.map((p) => p.challengeId).toSet();

    return Scaffold(
      appBar: AppBar(
        title: const Text('LIVE CHALLENGES'),
        actions: [
          IconButton(
            tooltip: 'New challenge',
            onPressed: () => context.push('/challenges/create'),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: challenges.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'Live challenges could not be loaded.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted),
            ),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No public challenges are running.',
                      style: TextStyle(color: palette.muted),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () => context.push('/challenges/create'),
                      child: const Text('Create the first one'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              40,
            ),
            itemCount: list.length,
            itemBuilder: (context, index) => RunningChallengeCard(
              challenge: list[index],
              joined: joinedIds.contains(list[index].id),
            ),
          );
        },
      ),
    );
  }
}

/// One challenge, as a row in a list.
class RunningChallengeCard extends StatelessWidget {
  const RunningChallengeCard({
    required this.challenge,
    this.joined = false,
    this.trailing,
    super.key,
  });

  final RunningChallenge challenge;
  final bool joined;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final remaining = challenge.daysRemaining();
    final ended = challenge.hasEnded() ||
        challenge.status != RunningChallengeStatus.active;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => context.push('/challenge/board/${challenge.id}'),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.stroke),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (challenge.visibility.isPrivate) ...[
                          Icon(
                            Icons.lock_rounded,
                            size: 14,
                            color: palette.muted,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            challenge.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${challenge.goalValueKm.round()} km  ·  '
                      '${challenge.participantCount} in  ·  '
                      '${ended ? "finished" : "$remaining ${remaining == 1 ? "day" : "days"} left"}',
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (joined)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: palette.brandSoft,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: palette.brandSoftStroke),
                  ),
                  child: Text(
                    'Joined',
                    style: TextStyle(
                      color: palette.brand,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Icon(Icons.chevron_right_rounded, color: palette.muted),
            ],
          ),
        ),
      ),
    );
  }
}
