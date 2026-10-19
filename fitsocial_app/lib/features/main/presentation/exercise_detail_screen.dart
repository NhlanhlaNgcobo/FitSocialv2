import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/premium/premium.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../auth/application/body_metrics_providers.dart';
import '../../auth/domain/body_metrics.dart';
import '../application/content_providers.dart';
import '../application/workout_library_providers.dart';
import '../domain/exercise_insights.dart';
import '../domain/exercise_library.dart';
import '../domain/workout_models.dart';
import 'insight_line_chart.dart';

/// One movement, over time: a chart of how it is going, every session it was
/// in, and the bests it has reached.
///
/// Reached from the info button in the exercise picker, the exercise card's
/// menu in a live session, and the records on the celebration screen. Built
/// from the workout history already loaded, so it needs no query of its own.
class ExerciseDetailScreen extends ConsumerStatefulWidget {
  const ExerciseDetailScreen({
    required this.exerciseKey,
    this.name,
    super.key,
  });

  /// The id the movement is tracked under — see `exerciseKeyFor`.
  final String exerciseKey;

  /// Its name, for a free-text or custom exercise the library cannot name.
  final String? name;

  @override
  ConsumerState<ExerciseDetailScreen> createState() =>
      _ExerciseDetailScreenState();
}

enum _Tab { summary, history, records }

class _ExerciseDetailScreenState extends ConsumerState<ExerciseDetailScreen> {
  _Tab _tab = _Tab.summary;
  ExerciseMetric? _metric;
  InsightWindow _window = InsightWindow.threeMonths;
  int? _selected;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _date(DateTime at, {bool year = false}) =>
      '${at.day} ${_months[at.month - 1]}${year ? ' ${at.year}' : ''}';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final history = ref.watch(workoutHistoryItemsProvider);
    final custom = ref.watch(customExercisesProvider).valueOrNull ?? const [];
    final imperial = ref.watch(bodyMetricsProvider).valueOrNull?.units ==
        MeasurementUnits.imperial;

    final library = ExerciseLibrary.byId(widget.exerciseKey);
    final customMatch = custom
        .where((c) => customExerciseId(c.id) == widget.exerciseKey)
        .firstOrNull;
    final sessions = exerciseSessions(
      history.valueOrNull ?? const [],
      widget.exerciseKey,
    );
    final name = library?.name ??
        customMatch?.name ??
        widget.name ??
        (widget.exerciseKey.startsWith('name:')
            ? widget.exerciseKey.substring(5)
            : widget.exerciseKey);
    final type = sessions.isNotEmpty
        ? sessions.first.type
        : ExerciseLibrary.trackingTypeFor(widget.exerciseKey, custom: custom);
    final muscles = library?.muscles ?? customMatch?.muscles ?? const [];
    final equipment = library?.equipment ?? customMatch?.equipment;

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          if (equipment != null || muscles.isNotEmpty)
            Text(
              [
                if (equipment != null) _capitalised(equipment),
                if (muscles.isNotEmpty) muscles.map(_capitalised).join(', '),
              ].join(' · '),
              style: TextStyle(color: palette.muted, fontSize: 13.5),
            ),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<_Tab>(
            segments: const [
              ButtonSegment(value: _Tab.summary, label: Text('Summary')),
              ButtonSegment(value: _Tab.history, label: Text('History')),
              ButtonSegment(value: _Tab.records, label: Text('Records')),
            ],
            selected: {_tab},
            onSelectionChanged: (v) => setState(() => _tab = v.first),
          ),
          const SizedBox(height: AppSpacing.md),
          if (history.isLoading && sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (sessions.isEmpty)
            _Empty(name: name)
          else
            switch (_tab) {
              _Tab.summary => _summary(sessions, type, imperial),
              _Tab.history => _history(sessions, type, imperial),
              _Tab.records => _records(sessions, type, imperial),
            },
        ],
      ),
    );
  }

  Widget _summary(
    List<ExerciseSession> sessions,
    TrackingType type,
    bool imperial,
  ) {
    final palette = context.palette;
    final metrics = metricsFor(type);
    final metric = metrics.contains(_metric) ? _metric! : metrics.first;
    final points = metricSeries(sessions, metric, window: _window);
    final index = points.isEmpty
        ? null
        : (_selected ?? points.length - 1).clamp(0, points.length - 1);
    final shown = index == null ? null : points[index];
    final change = points.length < 2 || shown == null
        ? null
        : shown.value - points.first.value;

    String? changeText() {
      if (change == null || change.abs() < 1e-9) return null;
      final better = metric.lowerIsBetter ? change < 0 : change > 0;
      final amount =
          describeMetricValue(metric, change.abs(), imperial: imperial);
      return '${better ? '▲' : '▼'} $amount since '
          '${_date(points.first.at, year: _window == InsightWindow.all)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in metrics)
              ChoiceChip(
                label: Text(m.label),
                selected: m == metric,
                onSelected: (_) => setState(() {
                  _metric = m;
                  _selected = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                shown == null
                    ? '—'
                    : describeMetricValue(metric, shown.value,
                        imperial: imperial),
                style: TextStyle(
                  color: palette.text,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                shown == null
                    ? 'Nothing in this window'
                    : _date(shown.at, year: true),
                style: TextStyle(color: palette.muted, fontSize: 13),
              ),
              if (changeText() case final text?)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    text,
                    style: TextStyle(
                      color: palette.brandText,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              InsightLineChart(
                points: points,
                selected: index,
                onSelect: (i) => setState(() => _selected = i),
              ),
              if (metric == ExerciseMetric.oneRepMax)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Estimated with the Epley formula, from sets of 12 reps '
                    'or fewer.',
                    style: TextStyle(color: palette.muted, fontSize: 11.5),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 8,
          children: [
            for (final w in InsightWindow.values)
              ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(w.label),
                    // Three months is free; further back is Premium.
                    if (w != InsightWindow.threeMonths)
                      const PremiumLock(
                        feature: PremiumFeature.longRangeCharts,
                      ),
                  ],
                ),
                selected: w == _window,
                onSelected: (_) {
                  if (w != InsightWindow.threeMonths &&
                      requiresPremium(
                          context, ref, PremiumFeature.longRangeCharts)) {
                    return;
                  }
                  setState(() {
                    _window = w;
                    _selected = null;
                  });
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _history(
    List<ExerciseSession> sessions,
    TrackingType type,
    bool imperial,
  ) {
    final palette = context.palette;
    // Which sessions set an all-time best on any of this movement's metrics.
    final bests = {
      for (final m in metricsFor(type))
        if (bestOf(sessions, m) case final b?) b.at,
    };
    return Column(
      children: [
        for (final s in sessions)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _date(s.loggedAt, year: true),
                          style: TextStyle(
                            color: palette.text,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (bests.contains(s.loggedAt))
                        Tooltip(
                          message: 'Set a best',
                          child: Icon(Icons.emoji_events_rounded,
                              size: 18, color: palette.brand),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final line in _setLines(s, type, imperial))
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        line,
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 13.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  List<String> _setLines(ExerciseSession s, TrackingType type, bool imperial) {
    String kg(double v) =>
        describeMetricValue(ExerciseMetric.heaviest, v, imperial: imperial);
    String time(int? seconds) =>
        describeMetricValue(ExerciseMetric.time, (seconds ?? 0).toDouble());
    if (s.sets.isEmpty) {
      // Typed in as totals, with no sets behind them.
      return [
        [
          if (s.durationSeconds != null) time(s.durationSeconds),
          if (s.distanceKm != null)
            describeMetricValue(ExerciseMetric.distance, s.distanceKm!),
        ].join(' · '),
      ];
    }
    var n = 0;
    return [
      for (final set in s.sets)
        '${switch (set.type) {
          SetType.warmup => 'W',
          SetType.dropset => 'D',
          SetType.failure => 'F',
          SetType.normal => '${++n}',
        }}   ${switch (type) {
          TrackingType.weightReps => '${kg(set.weightKg)} × ${set.reps}',
          TrackingType.weightedBodyweight =>
            '+${kg(set.weightKg)} × ${set.reps}',
          TrackingType.assistedBodyweight =>
            '−${kg(set.weightKg)} × ${set.reps}',
          TrackingType.bodyweightReps => '× ${set.reps}',
          TrackingType.duration => time(set.durationSeconds),
          TrackingType.weightDuration =>
            '${kg(set.weightKg)} · ${time(set.durationSeconds)}',
          TrackingType.cardio => [
              time(set.durationSeconds),
              if ((set.distanceKm ?? 0) > 0)
                describeMetricValue(ExerciseMetric.distance, set.distanceKm!),
            ].join(' · '),
        }}',
    ];
  }

  Widget _records(
    List<ExerciseSession> sessions,
    TrackingType type,
    bool imperial,
  ) {
    final palette = context.palette;
    final table =
        type == TrackingType.weightReps ? setRecordsTable(sessions) : const {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          child: Column(
            children: [
              for (final m in metricsFor(type))
                if (bestOf(sessions, m) case final b?)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.emoji_events_rounded,
                            size: 18, color: palette.brand),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            m.label,
                            style: TextStyle(
                              color: palette.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              describeMetricValue(m, b.value,
                                  imperial: imperial),
                              style: TextStyle(
                                color: palette.text,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              _date(b.at, year: true),
                              style: TextStyle(
                                color: palette.muted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        if (table.isNotEmpty &&
            ref.watch(premiumLockedProvider(PremiumFeature.setRecords))) ...[
          const SizedBox(height: AppSpacing.md),
          InkWell(
            onTap: () => showPremiumSheet(context, PremiumFeature.setRecords),
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: _Panel(
              child: Row(
                children: [
                  Icon(Icons.lock_rounded, color: palette.muted, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Set records: your heaviest at every rep count',
                      style: TextStyle(color: palette.text),
                    ),
                  ),
                  Text(
                    'Premium',
                    style: TextStyle(
                      color: palette.brandText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else if (table.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'SET RECORDS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: palette.muted,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _Panel(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('REPS',
                          style: TextStyle(
                              color: palette.muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ),
                    Text('HEAVIEST',
                        style: TextStyle(
                            color: palette.muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                for (final MapEntry(key: reps, value: kg) in table.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$reps',
                            style: TextStyle(
                              color: palette.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          describeMetricValue(ExerciseMetric.heaviest, kg,
                              imperial: imperial),
                          style: TextStyle(
                            color: palette.text,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _capitalised(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.card);
    return LiquidGlass(
      borderRadius: radius,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: context.palette.stroke),
        ),
        child: child,
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _Panel(
      child: Text(
        'No $name logged yet. Once it is in a saved workout, its progress, '
        'history and records show here.',
        style: TextStyle(color: palette.muted, fontSize: 14, height: 1.4),
      ),
    );
  }
}
