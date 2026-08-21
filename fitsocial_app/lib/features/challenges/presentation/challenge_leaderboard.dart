import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/avatar.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider, userProfileProvider;
import '../application/running_challenge_providers.dart';
import '../domain/running_challenge.dart';

/// The ranked board, with the current user pinned when they are below it.
///
/// The pinned row is the requirement that matters most here. A leaderboard that
/// only shows the top ten is a leaderboard for the people already winning;
/// somebody in fortieth place has to be able to see that they are in fortieth
/// place, or there is no reason for them to open it.
class ChallengeLeaderboard extends ConsumerWidget {
  const ChallengeLeaderboard({required this.challengeId, super.key});

  final String challengeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final board = ref.watch(challengeLeaderboardProvider(challengeId));
    final me = ref.watch(myParticipantProvider(challengeId)).valueOrNull;
    final myId = ref.watch(currentUserIdProvider);

    return board.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          'The leaderboard could not be loaded.',
          style: TextStyle(color: palette.muted),
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text(
              'Nobody has logged a qualifying run yet. Be first.',
              style: TextStyle(color: palette.muted),
            ),
          );
        }

        final onBoard = rows.any((row) => row.userId == myId);
        final pinned = !onBoard && me != null && me.status.isRanked;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in rows)
              LeaderboardRow(
                participant: row,
                isSelf: row.userId == myId,
              ),
            if (pinned) ...[
              // A visible break, so the pinned row reads as "and, separately,
              // you" rather than as the next position after the last one shown.
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(child: Divider(color: palette.stroke)),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      child: Text(
                        '⋯',
                        style: TextStyle(color: palette.muted, fontSize: 16),
                      ),
                    ),
                    Expanded(child: Divider(color: palette.stroke)),
                  ],
                ),
              ),
              LeaderboardRow(participant: me, isSelf: true),
            ],
          ],
        );
      },
    );
  }
}

/// One row: position, who, streak, distance, progress.
///
/// The four figures the specification asks a board to show, in the order they
/// matter — the rank is the answer, the streak is why, and the distance is the
/// tie-break. Progress goes last because it is the least comparable of them.
class LeaderboardRow extends ConsumerWidget {
  const LeaderboardRow({
    required this.participant,
    this.isSelf = false,
    super.key,
  });

  final ChallengeParticipant participant;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final profile = ref.watch(userProfileProvider(participant.userId));
    final name = profile.valueOrNull?.displayName ?? 'Runner';
    final initials = profile.valueOrNull?.initials ?? '';
    final avatarUrl = profile.valueOrNull?.avatarUrl;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        // The current user's own row is tinted wherever it appears, so it is
        // findable at a glance whether it is in the board or pinned under it.
        color: isSelf ? palette.brandSoft : palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelf ? palette.brandSoftStroke : palette.stroke,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: _RankBadge(rank: participant.rank),
          ),
          Avatar(initials: initials, imageUrl: avatarUrl, size: 36),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSelf ? 'You' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${participant.completedDays} '
                  '${participant.completedDays == 1 ? "day" : "days"}'
                  '  ·  ${_km(participant.totalDistanceKm)} km',
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (participant.currentStreak > 0)
                Text(
                  '\u{1F525} ${participant.currentStreak}',
                  style: TextStyle(color: palette.brand, fontSize: 13),
                ),
              Text(
                '${participant.completionPercentage.round()}%',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The position. Medals for the top three, the plain number after that.
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    // Rank zero means the engine has not placed this person yet, which is what
    // a brand-new participant looks like for the moment before their first
    // recompute. A dash is honest; "0" would read as a position.
    if (rank <= 0) {
      return Text('–', style: TextStyle(color: palette.muted));
    }

    final medal = switch (rank) {
      1 => '\u{1F947}',
      2 => '\u{1F948}',
      3 => '\u{1F949}',
      _ => null,
    };

    if (medal != null) {
      return Text(medal, style: const TextStyle(fontSize: 18));
    }

    return Text(
      '$rank',
      style: TextStyle(
        color: palette.muted,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// One decimal, with a trailing `.0` dropped — the same treatment
/// `formatTaskAmount` gives a distance, for the same reason: a run is rarely a
/// round number, and rounding 9.6 up to 10 would overstate it.
String _km(double value) {
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}
