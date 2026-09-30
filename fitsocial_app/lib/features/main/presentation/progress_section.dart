import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/activity_grid.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../compare/presentation/compare_card.dart';
import '../../weather/presentation/weather_card.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';
import '../domain/progress_models.dart';
import 'progress_session_actions.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// The Progress tab: a period to report on, the numbers for it, the streak
/// grid, and the sessions that make up the numbers.
class ProgressSection extends ConsumerStatefulWidget {
  const ProgressSection({super.key});

  @override
  ConsumerState<ProgressSection> createState() => _ProgressSectionState();
}

class _ProgressSectionState extends ConsumerState<ProgressSection> {
  ProgressPeriod _period = ProgressPeriod.week;

  /// How many periods back from the current one the user has paged.
  int _offset = 0;

  ProgressWindow get _window => ProgressWindow.forOffset(_period, _offset);

  void _selectPeriod(ProgressPeriod period) {
    setState(() {
      _period = period;
      // Offsets do not carry over: five weeks back and five months back are
      // nowhere near each other, so switching period returns to the present.
      _offset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final window = _window;

    return Column(
      children: [
        // Conditions lead the tab: what the weather is doing decides whether
        // today's session happens outside, and that decision comes before
        // looking back at the week.
        const WeatherCard(),
        const SizedBox(height: AppSpacing.md),
        _PeriodPicker(selected: _period, onSelected: _selectPeriod),
        const SizedBox(height: AppSpacing.md),
        _DateNavigator(
          window: window,
          onPrevious: () => setState(() => _offset -= 1),
          // Null past the current period — there is no training in the future.
          onNext: window.isCurrent ? null : () => setState(() => _offset += 1),
        ),
        const SizedBox(height: AppSpacing.md),
        _OverviewCard(window: window),
        const SizedBox(height: AppSpacing.md),
        // Carries its own spacing, and draws nothing while Compare is off or
        // for the day and year views.
        CompareCard(window: window),
        // Always the full year, whatever period is being reported on: this is
        // the streak at a glance, not a chart of the selected window.
        const ActivityGridCard(
          fixedRange: ActivityRange.year,
          expanded: true,
        ),
        const SizedBox(height: AppSpacing.md),
        _SessionList(window: window),
      ],
    );
  }
}

/// Day / Week / Month / Year.
class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.selected, required this.onSelected});

  final ProgressPeriod selected;
  final ValueChanged<ProgressPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.stroke),
        ),
        child: Row(
          children: [
            for (final period in ProgressPeriod.values)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelected(period),
                  child: Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: period == selected
                          ? palette.brandSoft
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      period.label,
                      style: TextStyle(
                        color: period == selected
                            ? palette.brandText
                            : palette.muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `‹  📅 2 – 8 May 2026  ›`
class _DateNavigator extends StatelessWidget {
  const _DateNavigator({
    required this.window,
    required this.onPrevious,
    required this.onNext,
  });

  final ProgressWindow window;
  final VoidCallback onPrevious;

  /// Null disables the forward arrow, which is how the current period stops
  /// the user paging into a future that cannot hold anything.
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        _NavArrow(
          icon: Icons.chevron_left_rounded,
          onTap: onPrevious,
          semanticLabel: 'Previous ${window.period.label.toLowerCase()}',
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 15,
                color: palette.muted,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  window.label,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
        _NavArrow(
          icon: Icons.chevron_right_rounded,
          onTap: onNext,
          semanticLabel: 'Next ${window.period.label.toLowerCase()}',
        ),
      ],
    );
  }
}

class _NavArrow extends StatelessWidget {
  const _NavArrow({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onTap != null;

    return IconButton(
      onPressed: onTap,
      icon: Icon(icon),
      iconSize: 26,
      tooltip: enabled ? semanticLabel : null,
      color: palette.text,
      disabledColor: palette.muted.withValues(alpha: 0.3),
    );
  }
}

/// The four headline numbers for the window.
class _OverviewCard extends ConsumerWidget {
  const _OverviewCard({required this.window});

  final ProgressWindow window;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final overview = ref.watch(progressOverviewProvider(window));

    // An empty overview rather than a spinner while loading: the card keeps
    // its shape, so the page does not jump as the numbers arrive.
    final data = overview.valueOrNull ??
        const ProgressOverview(
          sessionCount: 0,
          duration: Duration.zero,
          calories: 0,
          activeDays: 0,
          goalDays: 0,
          sessionCountDelta: 0,
          durationDelta: Duration.zero,
          caloriesDelta: 0,
        );

    return DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            window.isCurrent ? window.period.overviewTitle : 'Overview',
            style: TextStyle(
              color: palette.text,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MetricTile(
                  icon: Icons.local_fire_department_rounded,
                  iconColor: palette.brand,
                  value: '${data.sessionCount}',
                  label: data.sessionCount == 1 ? 'Workout' : 'Workouts',
                  delta: _deltaLabel(
                    formatSignedInt(data.sessionCountDelta),
                    data.sessionCountDelta,
                  ),
                ),
              ),
              Expanded(
                child: _MetricTile(
                  icon: Icons.schedule_rounded,
                  iconColor: const Color(0xFF4C9AFF),
                  value: formatSessionDuration(data.duration),
                  label: 'Total Duration',
                  delta: _deltaLabel(
                    formatSignedDuration(data.durationDelta),
                    data.durationDelta.inMinutes,
                  ),
                ),
              ),
              Expanded(
                child: _MetricTile(
                  icon: Icons.fitness_center_rounded,
                  iconColor: const Color(0xFF35C46C),
                  value: formatThousands(data.calories),
                  label: 'Total Calories',
                  delta: _deltaLabel(
                    formatSignedInt(data.caloriesDelta),
                    data.caloriesDelta,
                  ),
                ),
              ),
              Expanded(
                child: _MetricTile(
                  icon: Icons.emoji_events_rounded,
                  iconColor: const Color(0xFFA97BFF),
                  value: '${data.consistencyPercent}%',
                  label: 'Consistency',
                  // Not a delta: the fraction behind the percentage, which is
                  // what makes it mean anything.
                  delta: ('${data.activeDays}/${data.goalDays} days', null),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Pairs a delta's text with its direction, or drops the direction when the
  /// value did not move — a grey "+0" reads better than a green one.
  (String, int?) _deltaLabel(String text, int direction) =>
      (text, direction == 0 ? null : direction);
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.delta,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  /// The caption under the value, and which way it moved — positive, negative,
  /// or null for a caption that is not a movement at all.
  final (String, int?) delta;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (deltaText, direction) = delta;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Resolved here rather than at each call site so all four glyphs are
        // adjusted for the page together.
        Icon(icon, size: 18, color: palette.accent(iconColor)),
        const SizedBox(height: 8),
        // Scaled down rather than wrapped or clipped: four tiles across a
        // phone leaves no room for "5h 32m" to find a second line.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              color: palette.text,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: palette.muted, fontSize: 10),
        ),
        const SizedBox(height: 4),
        Text(
          deltaText,
          style: TextStyle(
            color: switch (direction) {
              null => palette.muted,
              final d when d > 0 => palette.success,
              _ => palette.danger,
            },
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// The heart hue the Health & Devices grid uses, so a heart rate reads as the
/// same measurement wherever it appears.
const _kHeartRateHue = Color(0xFFFF4D6D);

/// Every session inside the window, newest first.
class _SessionList extends ConsumerWidget {
  const _SessionList({required this.window});

  final ProgressWindow window;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final sessions = ref.watch(windowSessionsProvider(window));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
          child: Text(
            window.isCurrent ? window.period.listTitle : 'Sessions',
            style: TextStyle(
              color: palette.text,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
        sessions.when(
          data: (items) => items.isEmpty
              ? _EmptySessions(window: window)
              : Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      _SessionRow(session: items[i]),
                      if (i != items.length - 1)
                        const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                ),
          loading: () => const _SessionsNotice(label: 'Loading sessions...'),
          error: (_, __) =>
              const _SessionsNotice(label: 'Sessions unavailable'),
        ),
      ],
    );
  }
}

class _EmptySessions extends StatelessWidget {
  const _EmptySessions({required this.window});

  final ProgressWindow window;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final period = window.period.label.toLowerCase();

    return DarkCard(
      child: Column(
        children: [
          Icon(Icons.self_improvement_rounded, size: 30, color: palette.muted),
          const SizedBox(height: AppSpacing.sm),
          Text(
            window.isCurrent
                ? 'Nothing logged this $period yet'
                : 'Nothing was logged then',
            style: TextStyle(
              color: palette.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (window.isCurrent) ...[
            const SizedBox(height: 4),
            Text(
              'Log a run or a workout and it will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _SessionsNotice extends StatelessWidget {
  const _SessionsNotice({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DarkCard(
      child: Text(
        label,
        style: TextStyle(color: context.palette.muted),
      ),
    );
  }
}

/// One logged session, with the chevron that opens it.
class _SessionRow extends ConsumerWidget {
  const _SessionRow({required this.session});

  final ActivitySession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    return DarkCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 12,
      ),
      child: Row(
        children: [
          _SessionIcon(kind: session.kind),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _whenLabel(session.startedAt),
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                // Wrapped rather than a Row: a long duration next to a
                // four-figure calorie count has nowhere to go on a narrow
                // phone, and a second line beats an overflow stripe.
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _SessionStat(
                      icon: Icons.schedule_rounded,
                      label: formatSessionDuration(session.duration),
                    ),
                    _SessionStat(
                      icon: Icons.local_fire_department_rounded,
                      iconColor: palette.brand,
                      label: '${formatThousands(session.calories)} kcal',
                      // Runs have no recorded calories, so theirs are worked
                      // out from distance — said plainly rather than shown as
                      // if it had been measured.
                      tooltip: session.caloriesAreEstimated
                          ? 'Estimated from distance'
                          : null,
                    ),
                    // Only for sessions a strap actually recorded. Average on
                    // the face because that is the figure that describes a run;
                    // the peak is a detail, and the row has room for one more
                    // stat rather than two.
                    if (session.heartRate case final heartRate?)
                      _SessionStat(
                        icon: Icons.monitor_heart_rounded,
                        iconColor: _kHeartRateHue,
                        label: '${heartRate.averageBpm} bpm',
                        tooltip: 'Max ${heartRate.maxBpm} bpm',
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Both trailing controls are held to a tight box: at their default
          // size the pair claims nearly a third of a phone's width, and every
          // pixel they take comes off the title.
          SessionMenu(session: session),
          IconButton(
            onPressed: () => openSession(context, ref, session),
            icon: const Icon(Icons.chevron_right_rounded),
            iconSize: 24,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            color: palette.muted,
            tooltip: session.postId != null ? 'Open post' : 'Open log',
          ),
        ],
      ),
    );
  }

  /// "8 May • 18:45", dropping to "Today"/"Yesterday" for the recent ones.
  static String _whenLabel(DateTime when) {
    final day = ActivityCalendar.dateOnly(when);
    final today = ActivityCalendar.dateOnly(DateTime.now());
    final time = '${when.hour.toString().padLeft(2, '0')}:'
        '${when.minute.toString().padLeft(2, '0')}';

    final difference = ActivityCalendar.daysBetween(day, today);
    final date = switch (difference) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => '${when.day} ${_months[when.month - 1]}',
    };
    return '$date  •  $time';
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

class _SessionIcon extends StatelessWidget {
  const _SessionIcon({required this.kind});

  final ActivityKind kind;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: palette.brandSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        kind.descriptor.icon,
        color: palette.brand,
        size: 22,
      ),
    );
  }
}

class _SessionStat extends StatelessWidget {
  const _SessionStat({
    required this.icon,
    required this.label,
    this.iconColor,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final Color? iconColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: iconColor ?? palette.muted),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: palette.muted, fontSize: 12),
        ),
        if (tooltip != null) ...[
          const SizedBox(width: 3),
          Icon(Icons.info_outline_rounded, size: 11, color: palette.muted),
        ],
      ],
    );

    return tooltip == null ? row : Tooltip(message: tooltip!, child: row);
  }
}
