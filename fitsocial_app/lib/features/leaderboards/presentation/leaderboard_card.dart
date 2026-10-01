import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../main/application/content_providers.dart' show userProfileProvider;
import '../../main/domain/progress_models.dart'
    show ProgressPeriod, ProgressWindow, formatThousands;
import '../application/leaderboard_providers.dart';
import '../domain/leaderboard.dart';

/// The top of the week's or month's step board, and the way into the full one.
///
/// Sits under Compare on the Progress tab and draws nothing — spacing included —
/// while leaderboards are switched off, on a day or year view, or on a period
/// that is not the current one. That last rule is the honest one: a board is
/// about how this week is going, and there is no board for five weeks ago to
/// page back to.
class LeaderboardCard extends ConsumerWidget {
  const LeaderboardCard({required this.window, super.key});

  final ProgressWindow window;

  /// How many places the card shows before handing over to the full screen.
  static const int _preview = 3;

  /// The scope a Progress window maps to, or null for one no board covers.
  static LeaderboardScope? scopeFor(ProgressWindow window) {
    if (!window.isCurrent) return null;
    return switch (window.period) {
      ProgressPeriod.week => LeaderboardScope.week,
      ProgressPeriod.month => LeaderboardScope.month,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(leaderboardsEnabledProvider)) return const SizedBox.shrink();
    final scope = scopeFor(window);
    if (scope == null) return const SizedBox.shrink();

    final palette = context.palette;
    // Steps, always, on the card. One figure is a summary; four would be the
    // full screen with worse spacing, and that screen is one tap away.
    final board = ref
        .watch(
          leaderboardProvider((scope: scope, metric: LeaderboardMetric.steps)),
        )
        .valueOrNull;

    // Nothing at all until there is a board. A card saying "no leaderboard yet"
    // on every Progress tab is a card that is wrong most of the time: most
    // people have not followed anybody who walks yet.
    if (board == null || board.isEmpty) return const SizedBox.shrink();

    final shown = board.rows.take(_preview).toList(growable: false);
    final viewerRow = board.viewerRow ??
        board.rows.where((place) => place.isViewer).firstOrNull;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: DarkCard(
        onTap: () => context.push('/leaderboard'),
        semanticLabel: 'Open the full leaderboard',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Steps ${scope.label.toLowerCase()}',
                    style: TextStyle(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: palette.muted,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final place in shown) _MiniRow(place: place),
            // Only when the viewer is not already in the three above, and only
            // when they are on the board at all.
            if (viewerRow != null && !shown.contains(viewerRow))
              _MiniRow(place: viewerRow),
          ],
        ),
      ),
    );
  }
}

class _MiniRow extends ConsumerWidget {
  const _MiniRow({required this.place});

  final LeaderboardPlace place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final profile = ref.watch(userProfileProvider(place.userId)).valueOrNull;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '${place.rank}',
              style: TextStyle(
                color: palette.muted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Avatar(
            initials: profile?.initials ?? '',
            imageUrl: profile?.avatarUrl,
            size: 24,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              place.isViewer ? 'You' : (profile?.displayName ?? ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.text,
                fontSize: 13,
                fontWeight: place.isViewer ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            formatThousands(place.value),
            style: TextStyle(
              color: palette.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
