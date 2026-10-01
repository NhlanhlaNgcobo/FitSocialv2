import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/observability/app_analytics.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider, userProfileProvider;
import '../../main/domain/progress_models.dart' show formatThousands;
import '../application/leaderboard_providers.dart';
import '../data/leaderboard_repository.dart';
import '../domain/leaderboard.dart';

/// The friends leaderboard: the people you follow, on one figure at a time.
///
/// Week or month across the top, the four figures as chips under it, the board
/// below. The opt-out sits at the bottom of this same screen rather than in
/// Settings: it is the one place somebody who has just seen their name on a
/// board will look for the way off it, and it has to be here anyway — opting
/// out empties the board above it, so a switch anywhere else would be the only
/// way back on.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  LeaderboardScope _scope = LeaderboardScope.week;
  LeaderboardMetric _metric = LeaderboardMetric.steps;

  /// Set while the opt-out write is in flight, which greys the switch. The value
  /// itself is never held here: the server acts on the profile document, so the
  /// document is what the switch reports.
  bool _saving = false;

  BoardRequest get _request => (scope: _scope, metric: _metric);

  @override
  void initState() {
    super.initState();
    // Once per visit, after the frame — a view is a side effect, and build runs
    // again every time a filter moves. Changing a filter has its own event.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appAnalyticsProvider).log(AnalyticsEvent.leaderboardViewed, {
        'scope': _scope.key,
        'metric': _metric.field,
      });
    });
  }

  void _changeFilter({LeaderboardScope? scope, LeaderboardMetric? metric}) {
    setState(() {
      if (scope != null) _scope = scope;
      if (metric != null) _metric = metric;
    });
    ref.read(appAnalyticsProvider).log(
      AnalyticsEvent.leaderboardFilterChanged,
      {'scope': _scope.key, 'metric': _metric.field},
    );
  }

  Future<void> _setOptOut(bool optedOut) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    setState(() => _saving = true);
    try {
      await ref.read(leaderboardRepositoryProvider).setOptOut(userId, optedOut);
      ref.read(appAnalyticsProvider).log(
        AnalyticsEvent.leaderboardOptoutToggled,
        {'opted_out': optedOut},
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That did not save. Check your connection.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final optedOut = ref.watch(leaderboardOptOutProvider).valueOrNull ?? false;
    final board = ref.watch(leaderboardProvider(_request));

    return Scaffold(
      appBar: AppBar(title: const Text('LEADERBOARD')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(leaderboardProvider(_request)),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            SegmentedButton<LeaderboardScope>(
              segments: [
                for (final scope in LeaderboardScope.values)
                  ButtonSegment(value: scope, label: Text(scope.label)),
              ],
              selected: {_scope},
              showSelectedIcon: false,
              onSelectionChanged: (set) => _changeFilter(scope: set.first),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final metric in LeaderboardMetric.values)
                  ChoiceChip(
                    label: Text(metric.label),
                    selected: metric == _metric,
                    onSelected: (_) {
                      if (metric == _metric) return;
                      _changeFilter(metric: metric);
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            board.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const _Notice(
                icon: Icons.cloud_off_rounded,
                title: 'The board could not load',
                body: 'Check your connection and pull down to try again.',
              ),
              data: (data) => data.isEmpty
                  ? _Notice(
                      icon: Icons.groups_rounded,
                      title: 'Nothing on this board yet',
                      body: _emptyBody(),
                    )
                  : _Board(board: data, metric: _metric),
            ),
            const SizedBox(height: AppSpacing.lg),
            _OptOutCard(
              optedOut: optedOut,
              onChanged: _saving ? null : _setOptOut,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Steps typed in by hand, and any day carrying an impossible '
              'number, are left out of every figure here. Yours still show in '
              'full on your own screens.',
              style: TextStyle(color: palette.muted, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  String _emptyBody() {
    final period = _scope == LeaderboardScope.week ? 'week' : 'month';
    return 'Nobody you follow has ${_metric.label.toLowerCase()} to show for '
        'this $period yet. Follow a few more people, or give it a day.';
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.board, required this.metric});

  final LeaderboardBoard board;
  final LeaderboardMetric metric;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final viewerRow = board.viewerRow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final place in board.rows) _BoardRow(place: place, metric: metric),
        if (viewerRow != null) ...[
          // A visible break, so the pinned row reads as "and, separately, you"
          // rather than as the next position after the last one shown. The same
          // treatment the challenge board gives its own pinned row.
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
          _BoardRow(place: viewerRow, metric: metric),
        ],
      ],
    );
  }
}

/// One place on the board: position, who, how steady, the figure.
class _BoardRow extends ConsumerWidget {
  const _BoardRow({required this.place, required this.metric});

  final LeaderboardPlace place;
  final LeaderboardMetric metric;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final mine = place.isViewer;
    // Nothing waits on this: a row draws with its figure and fills the name in
    // when it arrives. The board is the figures.
    final profile = ref.watch(userProfileProvider(place.userId)).valueOrNull;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        // The viewer's own row is tinted wherever it appears, so it is findable
        // at a glance whether it is in the board or pinned under it — the same
        // rule, and the same colours, as the challenge board's rows.
        color: mine ? palette.brandSoft : palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: mine ? palette.brandSoftStroke : palette.stroke,
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: 34, child: _RankBadge(rank: place.rank)),
          Avatar(
            initials: profile?.initials ?? '',
            imageUrl: profile?.avatarUrl,
            size: 36,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mine ? 'You' : (profile?.displayName ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  place.entry.activeDays == 1
                      ? '1 active day'
                      : '${place.entry.activeDays} active days',
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _figure(place.value, metric),
            style: TextStyle(
              color: palette.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static String _figure(int value, LeaderboardMetric metric) {
    final text = formatThousands(value);
    return metric.unit.isEmpty ? text : '$text ${metric.unit}';
  }
}

/// The position. Medals for the top three, the plain number after that — as on
/// the challenge board, so a place reads the same wherever it is shown.
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

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
      style: TextStyle(color: palette.muted, fontWeight: FontWeight.w600),
    );
  }
}

/// The way off the boards, and back on.
class _OptOutCard extends StatelessWidget {
  const _OptOutCard({required this.optedOut, required this.onChanged});

  final bool optedOut;

  /// Null while a change is in flight, which greys the switch and refuses the
  /// tap.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final change = onChanged;

    return DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Show me on leaderboards',
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              // The switch reads as "show me", not as "opt out": a switch you
              // turn *on* to be left alone is the kind of double negative people
              // get wrong, and getting this one wrong is a privacy mistake.
              Switch(
                value: !optedOut,
                onChanged: change == null ? null : (on) => change(!on),
                activeTrackColor: palette.brand,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            optedOut
                ? 'You are off every board. The figures you had on them have '
                    'been removed, and nothing new is published.'
                : 'Only the people who follow you can see you here, and only '
                    'these four figures — never your meals, your heart rate or '
                    'which days you trained.',
            style: TextStyle(color: palette.muted, fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return DarkCard(
      child: Column(
        children: [
          Icon(icon, size: 30, color: palette.muted),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.text, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted, fontSize: 13, height: 1.35),
          ),
        ],
      ),
    );
  }
}
