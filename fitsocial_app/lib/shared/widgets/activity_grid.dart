import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/main/application/content_providers.dart';
import '../../features/main/domain/app_models.dart';
import 'dark_card.dart';

/// The activity grid wired to its data.
///
/// Pass [fixedRange] to pin the card to one window and hide the range picker —
/// what the home feed wants, where the card is a glance at the current week
/// rather than something to explore. Leave it null for the switchable card on
/// the Progress tab.
class ActivityGridCard extends ConsumerStatefulWidget {
  const ActivityGridCard({this.fixedRange, this.expanded = false, super.key});

  final ActivityRange? fixedRange;

  /// The full Progress-tab treatment rather than the compact home one — see
  /// [ActivityGrid.expanded].
  final bool expanded;

  @override
  ConsumerState<ActivityGridCard> createState() => _ActivityGridCardState();
}

class _ActivityGridCardState extends ConsumerState<ActivityGridCard> {
  /// Where the switchable card opens, every time.
  ///
  /// Deliberately not remembered: the full 53-week wall is the view worth
  /// landing on, so a trip to Progress starts there even if the user drilled
  /// into 7D last time.
  static const _openingRange = ActivityRange.year;

  ActivityRange _range = _openingRange;

  /// Whether the tab this card lives on was on screen at the last dependency
  /// change — see [didChangeDependencies].
  bool _wasOnScreen = false;

  ActivityRange get _activeRange => widget.fixedRange ?? _range;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Switching sections within the Activity screen rebuilds this widget, so
    // that route back to Progress resets on its own. Switching *tabs* does
    // not: the shell parks every branch rather than disposing it, precisely so
    // scroll positions and forms survive, which means this State would come
    // back still holding whatever range was last picked.
    //
    // TickerMode is what the shell toggles as a branch parks and wakes, so
    // reading it here both registers the dependency and gives us the "this tab
    // is being entered" edge. A rebuild follows this callback, so assigning
    // without setState is correct.
    final onScreen = TickerMode.valuesOf(context).enabled;
    if (onScreen && !_wasOnScreen) _range = _openingRange;
    _wasOnScreen = onScreen;
  }

  @override
  Widget build(BuildContext context) {
    final range = _activeRange;
    final calendar = ref.watch(activityCalendarProvider(range));

    // The grid is always rendered, never swapped out for a placeholder: an
    // empty week of squares is itself the answer to "have I trained?", and it
    // keeps the range picker reachable while data loads or a read fails.
    final data = calendar.valueOrNull ??
        ActivityCalendar.fromLoggedDays(range: range, logged: const []);

    return ActivityGrid(
      calendar: data,
      range: range,
      onRangeChanged: widget.fixedRange != null
          ? null
          : (next) => setState(() => _range = next),
      expanded: widget.expanded,
      notice: calendar.hasError ? "Couldn't load your activity" : null,
    );
  }
}

/// A GitHub-contribution-graph-style view of logged training.
///
/// The layout follows GitHub's graph closely: one small square per calendar
/// day, days of the week as rows, weeks as columns, an empty square for days
/// with nothing logged and progressively stronger fill for busier days, with
/// month labels above and a Less/More legend below.
///
/// Two things are deliberately different. GitHub scales its five shades by
/// quartiles of the user's own commit counts; here the thresholds are fixed
/// (see [ActivityDay.level]) because training volume has a natural ceiling of
/// a few sessions a day. And GitHub reveals the per-day detail on hover, which
/// does not exist on a phone — tapping a square selects it instead, and the
/// detail replaces the summary line underneath.
///
/// Only runs and workouts fill a square.
class ActivityGrid extends StatefulWidget {
  const ActivityGrid({
    required this.calendar,
    required this.range,
    required this.onRangeChanged,
    this.expanded = false,
    this.notice,
    super.key,
  });

  final ActivityCalendar calendar;
  final ActivityRange range;

  /// Null pins the card to [range] and hides the picker entirely.
  final ValueChanged<ActivityRange>? onRangeChanged;

  /// The full Progress-tab treatment — the "N active days" headline and the
  /// key explaining the two square states — rather than the compact variant
  /// the home feed shows.
  ///
  /// One flag rather than two because the pieces belong together: on the feed
  /// the card is a glance at the streak, and both the headline and the key
  /// restate what the squares already say.
  final bool expanded;

  /// Shown in place of the per-day detail when the squares cannot be trusted —
  /// a failed read, say. The grid still draws, so the message has to say why
  /// it is empty rather than leaving the user to assume they did not train.
  final String? notice;

  @override
  State<ActivityGrid> createState() => _ActivityGridState();
}

class _ActivityGridState extends State<ActivityGrid> {
  /// The scroller for the year view, which is far wider than a phone.
  final _yearScroll = ScrollController();

  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _scrollToMostRecent();
  }

  @override
  void didUpdateWidget(ActivityGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.range != widget.range) {
      // The selected day almost certainly falls outside the new window.
      _selectedDate = null;
      _scrollToMostRecent();
    }
  }

  @override
  void dispose() {
    _yearScroll.dispose();
    super.dispose();
  }

  /// Parks the year view at today rather than 52 weeks ago, so the first thing
  /// on screen is the most recent training.
  void _scrollToMostRecent() {
    if (widget.range != ActivityRange.year) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_yearScroll.hasClients) return;
      _yearScroll.jumpTo(_yearScroll.position.maxScrollExtent);
    });
  }

  ActivityDay? get _selectedDay {
    final date = _selectedDate;
    if (date == null) return null;
    for (final day in widget.calendar.days) {
      if (day.date == date) return day;
    }
    return null;
  }

  void _select(ActivityDay day) {
    setState(() {
      _selectedDate = _selectedDate == day.date ? null : day.date;
    });
  }

  @override
  Widget build(BuildContext context) {
    final calendar = widget.calendar;

    return DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(calendar: calendar, showHeadline: widget.expanded),
          const SizedBox(height: AppSpacing.md),
          if (widget.onRangeChanged case final onRangeChanged?) ...[
            _RangePicker(
              selected: widget.range,
              onSelected: onRangeChanged,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (widget.range == ActivityRange.year)
            _YearGrid(
              calendar: calendar,
              scrollController: _yearScroll,
              selectedDate: _selectedDate,
              onSelected: _select,
            )
          else
            _WeekRowsGrid(
              calendar: calendar,
              selectedDate: _selectedDate,
              onSelected: _select,
            ),
          const SizedBox(height: AppSpacing.md),
          _DetailLine(
            day: _selectedDay,
            isFuture: _selectedDay != null && calendar.isFuture(_selectedDay!),
            notice: widget.notice,
          ),
          if (widget.expanded) ...[
            const SizedBox(height: AppSpacing.sm),
            const _Legend(),
          ],
        ],
      ),
    );
  }
}

// The four cell colours are resolved per theme rather than taken from the
// palette, because the grid needs finer steps than the app's surfaces provide:
// empty and future have to be distinguishable from each other *and* from the
// card behind them, which is three shades inside one card. Keeping them local
// also pins the dark values to exactly what the app shipped with.

/// A day with nothing logged.
Color _emptyCellColor(AppPalette p) =>
    p.isDark ? const Color(0xFF1B1B1B) : const Color(0xFFE8E4DB);

/// Outline on empty squares, so a quiet stretch still reads as a grid.
Color _emptyCellBorder(AppPalette p) =>
    p.isDark ? const Color(0xFF272727) : const Color(0xFFD7D2C8);

/// A day still to come. Quieter than an empty past day so an untrained
/// Wednesday is not mistaken for a Saturday that has not arrived — which means
/// *darker* on the dark theme and *lighter* on the light one.
Color _futureCellColor(AppPalette p) =>
    p.isDark ? const Color(0xFF141414) : const Color(0xFFF5F3EE);

Color _futureCellBorder(AppPalette p) =>
    p.isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE7E3DA);


/// Corner radius for a square of [size].
///
/// Proportional rather than fixed so a 12px year cell and a 43px week cell
/// look equally rounded — one shared radius would leave the small ones nearly
/// square and the big ones barely softened.
BorderRadius _cellRadius(double size) =>
    BorderRadius.circular((size * 0.28).clamp(4.0, 14.0));

/// Square size for the year view, where 53 columns have to fit a scrollable
/// strip. GitHub's own geometry, near enough.
const _yearCellSize = 12.0;

/// Gutter between squares in the week and month grids.
const _cellGap = 6.0;

/// The year grid keeps a tighter gutter: at 53 columns the wider one costs a
/// lot of scrolling and the strip stops reading as a single block.
const _yearCellGap = 4.0;

/// Ceiling for the 7-day and 30-day views, which size their squares to the
/// available width. Without a cap a week of squares becomes seven big slabs.
const _maxCellSize = 44.0;

class _Header extends StatelessWidget {
  const _Header({required this.calendar, required this.showHeadline});

  final ActivityCalendar calendar;

  /// Whether to draw the "N active days <window>" line above the totals.
  final bool showHeadline;

  @override
  Widget build(BuildContext context) {
    final activeDays = calendar.activeDays;
    final streak = calendar.currentStreak;

    // Run and workout counts used to sit here too. They are per-day detail,
    // and the grid already answers that on tap, so the line carries only the
    // one figure no square can show: the streak across them.
    //
    // "Day" stays singular whatever the count — "5 Day Streak" is the compound
    // form, not a plural.
    final streakLine = Text(
      streak > 0 ? '$streak Day Streak' : 'No streak yet',
      style: TextStyle(color: context.palette.muted, fontSize: 13),
    );

    // Returned bare rather than as a one-child Column, so the card loses the
    // headline's height outright instead of keeping an empty row where it was.
    if (!showHeadline) return streakLine;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$activeDays active ${activeDays == 1 ? 'day' : 'days'} '
          '${calendar.range.windowLabel}',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        streakLine,
      ],
    );
  }
}

class _RangePicker extends StatelessWidget {
  const _RangePicker({required this.selected, required this.onSelected});

  final ActivityRange selected;
  final ValueChanged<ActivityRange> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        // The page colour, inside a card: an inset well in either theme.
        color: palette.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.stroke),
      ),
      child: Row(
        children: [
          for (final range in ActivityRange.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(range),
                child: Container(
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: range == selected
                        ? palette.brandSoft
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    range.label,
                    style: TextStyle(
                      color: range == selected
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
    );
  }
}

/// GitHub's exact arrangement: seven rows of weekdays, one column per week,
/// scrolled horizontally because 53 columns will never fit a phone.
class _YearGrid extends StatelessWidget {
  const _YearGrid({
    required this.calendar,
    required this.scrollController,
    required this.selectedDate,
    required this.onSelected,
  });

  final ActivityCalendar calendar;
  final ScrollController scrollController;
  final DateTime? selectedDate;
  final ValueChanged<ActivityDay> onSelected;

  @override
  Widget build(BuildContext context) {
    final weeks = _chunkIntoWeeks(calendar.days);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _WeekdayLabels(cellSize: _yearCellSize, gap: _yearCellGap),
        const SizedBox(width: 6),
        Expanded(
          child: SingleChildScrollView(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MonthLabels(weeks: weeks),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var w = 0; w < weeks.length; w++)
                      Padding(
                        padding: EdgeInsets.only(
                          right: w == weeks.length - 1 ? 0 : _yearCellGap,
                        ),
                        child: Column(
                          children: [
                            for (var d = 0; d < 7; d++)
                              Padding(
                                padding: EdgeInsets.only(
                                    bottom: d == 6 ? 0 : _yearCellGap),
                                child: _DayCell(
                                  day: weeks[w][d],
                                  size: _yearCellSize,
                                  selected: weeks[w][d] != null &&
                                      weeks[w][d]!.date == selectedDate,
                                  isFuture: weeks[w][d] != null &&
                                      calendar.isFuture(weeks[w][d]!),
                                  onTap: onSelected,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Weeks as rows instead of columns, for the 7-day and 30-day views.
///
/// GitHub only ever draws a year, so it has no equivalent. Rotating the short
/// ranges lets the squares grow to fill the card's width — a five-column
/// sliver on the left of an otherwise empty card would be the alternative.
class _WeekRowsGrid extends StatelessWidget {
  const _WeekRowsGrid({
    required this.calendar,
    required this.selectedDate,
    required this.onSelected,
  });

  final ActivityCalendar calendar;
  final DateTime? selectedDate;
  final ValueChanged<ActivityDay> onSelected;

  @override
  Widget build(BuildContext context) {
    final rows = _chunkIntoWeeks(calendar.days);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellSize = ((constraints.maxWidth - _cellGap * 6) / 7)
            .clamp(0.0, _maxCellSize);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WeekdayHeader(cellSize: cellSize),
            const SizedBox(height: 6),
            for (var r = 0; r < rows.length; r++)
              Padding(
                padding:
                    EdgeInsets.only(bottom: r == rows.length - 1 ? 0 : _cellGap),
                child: Row(
                  children: [
                    for (var d = 0; d < 7; d++)
                      Padding(
                        padding: EdgeInsets.only(right: d == 6 ? 0 : _cellGap),
                        child: _DayCell(
                          day: rows[r][d],
                          size: cellSize,
                          selected: rows[r][d] != null &&
                              rows[r][d]!.date == selectedDate,
                          isFuture: rows[r][d] != null &&
                              calendar.isFuture(rows[r][d]!),
                          onTap: onSelected,
                          // Short ranges have room to name the day inside the
                          // square, which spares the user counting columns.
                          showDayNumber: true,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One square. A null [day] is a slot past the end of the data at the tail of
/// the last week, held open so the grid keeps its shape but never drawn.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.size,
    required this.selected,
    required this.isFuture,
    required this.onTap,
    this.showDayNumber = false,
  });

  final ActivityDay? day;
  final double size;
  final bool selected;
  final bool isFuture;
  final ValueChanged<ActivityDay> onTap;
  final bool showDayNumber;

  @override
  Widget build(BuildContext context) {
    final day = this.day;
    if (day == null) return SizedBox.square(dimension: size);

    final palette = context.palette;
    final description = _describeDay(day, isFuture: isFuture);
    final color = day.isActive
        ? palette.brand
        : isFuture
            ? _futureCellColor(palette)
            : _emptyCellColor(palette);

    return Semantics(
      label: description,
      button: true,
      selected: selected,
      child: Tooltip(
        message: description,
        child: GestureDetector(
          onTap: () => onTap(day),
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: _cellRadius(size),
              border: Border.all(
                color: selected
                    ? palette.text
                    : day.isActive
                        ? Colors.transparent
                        : isFuture
                            ? _futureCellBorder(palette)
                            : _emptyCellBorder(palette),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: showDayNumber && size >= 24
                ? Text(
                    '${day.date.day}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: day.isActive
                          ? AppColors.onBrandInk
                          : palette.muted
                              .withValues(alpha: isFuture ? 0.3 : 0.55),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// Mon / Wed / Fri down the left of the year grid — the same three GitHub
/// labels, chosen because a label on every row would not fit the row pitch.
///
/// Rows are Monday-first, so Monday is row 0.
class _WeekdayLabels extends StatelessWidget {
  const _WeekdayLabels({required this.cellSize, required this.gap});

  final double cellSize;
  final double gap;

  static const _labels = <int, String>{0: 'Mon', 2: 'Wed', 4: 'Fri'};

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Clears the month labels above the grid so the rows line up.
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var d = 0; d < 7; d++)
            Container(
              height: cellSize,
              margin: EdgeInsets.only(bottom: d == 6 ? 0 : gap),
              alignment: Alignment.centerRight,
              child: Text(
                _labels[d] ?? '',
                style: TextStyle(color: context.palette.muted, fontSize: 9),
              ),
            ),
        ],
      ),
    );
  }
}

/// M T W T F S S above the short grids, matching their Monday-first columns.
class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader({required this.cellSize});

  final double cellSize;

  static const _initials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var d = 0; d < 7; d++)
          Padding(
            padding: EdgeInsets.only(right: d == 6 ? 0 : _cellGap),
            child: SizedBox(
              width: cellSize,
              child: Text(
                _initials[d],
                textAlign: TextAlign.center,
                style: TextStyle(color: context.palette.muted, fontSize: 10),
              ),
            ),
          ),
      ],
    );
  }
}

/// Month abbreviations above the year grid.
///
/// GitHub labels the first column of each month, which is why its labels sit
/// at uneven intervals. A month whose first column is also its last is skipped
/// so two labels never collide.
class _MonthLabels extends StatelessWidget {
  const _MonthLabels({required this.weeks});

  final List<List<ActivityDay?>> weeks;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var w = 0; w < weeks.length; w++)
          Padding(
            padding:
                EdgeInsets.only(right: w == weeks.length - 1 ? 0 : _yearCellGap),
            child: SizedBox(
              width: _yearCellSize,
              height: 14,
              child: _labelFor(w) == null
                  ? null
                  : OverflowBox(
                      maxWidth: 40,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _labelFor(w)!,
                        style: TextStyle(
                          color: context.palette.muted,
                          fontSize: 10,
                        ),
                      ),
                    ),
            ),
          ),
      ],
    );
  }

  String? _labelFor(int index) {
    final month = _monthOf(weeks[index]);
    if (month == null) return null;
    final previous = index == 0 ? null : _monthOf(weeks[index - 1]);
    if (previous != null && previous == month) return null;
    // A one-column month would push its label into the next one's.
    final next = index + 1 < weeks.length ? _monthOf(weeks[index + 1]) : null;
    if (previous != null && next != null && next != month) return null;
    return _monthNames[month - 1];
  }

  /// The month a column belongs to — taken from its first real day.
  static int? _monthOf(List<ActivityDay?> week) {
    for (final day in week) {
      if (day != null) return day.date.month;
    }
    return null;
  }
}

/// The selected day's detail, or a prompt when nothing is selected.
///
/// This is the mobile stand-in for GitHub's hover tooltip, and its wording
/// follows the same shape: a count, then the date.
class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.day, this.isFuture = false, this.notice});

  final ActivityDay? day;
  final bool isFuture;
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final day = this.day;
    final notice = this.notice;
    final highlight = notice == null && day != null && day.isActive;
    final palette = context.palette;

    return ConstrainedBox(
      // A floor rather than a fixed height: it keeps the card from jumping as
      // the line appears and disappears, without clipping the text when the
      // user has scaled it up.
      constraints: const BoxConstraints(minHeight: 18),
      child: Row(
        children: [
          if (notice != null) ...[
            Icon(
              Icons.cloud_off_rounded,
              size: 14,
              color: palette.muted,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              notice ??
                  (day == null
                      ? 'Tap a square to see that day'
                      : _describeDay(day, isFuture: isFuture)),
              style: TextStyle(
                color: highlight ? palette.brandText : palette.muted,
                fontSize: 13,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the two square states mean.
///
/// GitHub's Less→More ramp does not apply here: the squares are binary, so the
/// key is too. [IntrinsicWidth] sizes the column to its widest row, which lines
/// the two swatches up under each other whatever the labels measure.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LegendRow(
            label: 'No login',
            color: _emptyCellColor(palette),
            borderColor: _emptyCellBorder(palette),
          ),
          const SizedBox(height: 6),
          _LegendRow(label: 'Logged in', color: palette.brand),
        ],
      ),
    );
  }
}

/// Legend swatches match the squares they stand for, so they are drawn at the
/// same proportions rather than as their own shape.
const _swatchSize = 16.0;

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.label,
    required this.color,
    this.borderColor,
  });

  final String label;
  final Color color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: context.palette.muted, fontSize: 12),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: _swatchSize,
          height: _swatchSize,
          decoration: BoxDecoration(
            color: color,
            borderRadius: _cellRadius(_swatchSize),
            border: Border.all(color: borderColor ?? Colors.transparent),
          ),
        ),
      ],
    );
  }
}

/// Splits a Sunday-aligned run of days into rows/columns of seven, padding the
/// final week with nulls for days that have not happened yet.
List<List<ActivityDay?>> _chunkIntoWeeks(List<ActivityDay> days) {
  final weeks = <List<ActivityDay?>>[];
  for (var i = 0; i < days.length; i += 7) {
    weeks.add([
      for (var d = 0; d < 7; d++) i + d < days.length ? days[i + d] : null,
    ]);
  }
  return weeks;
}

String _describeDay(ActivityDay day, {bool isFuture = false}) {
  final date = '${_weekdayNames[day.date.weekday - 1]}, '
      '${day.date.day} ${_monthNames[day.date.month - 1]}';
  if (isFuture) return 'Still to come: $date';
  if (!day.isActive) return 'No activity on $date';

  final parts = <String>[
    if (day.runs > 0) '${day.runs} ${day.runs == 1 ? 'run' : 'runs'}',
    if (day.workouts > 0)
      '${day.workouts} ${day.workouts == 1 ? 'workout' : 'workouts'}',
  ];
  return '${parts.join(' · ')} on $date';
}

const _weekdayNames = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const _monthNames = [
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
