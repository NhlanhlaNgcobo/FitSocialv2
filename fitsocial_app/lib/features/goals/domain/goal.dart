/// Personal goals, as the app reads them.
///
/// The goal is written by `functions/goals.js`, which owns every number here:
/// the app asks for a goal through the createGoal callable, shows what the
/// server says about it, and may archive it. Nothing on this side decides
/// whether a goal was hit.
library;

import '../../main/domain/progress_models.dart' show formatThousands;

/// What a goal counts. The wire names match METRICS in goals.js.
enum GoalMetric {
  steps('steps', 'Steps', 'steps'),
  activeMinutes('active_minutes', 'Active minutes', 'min'),
  workouts('workouts', 'Sessions', 'sessions'),
  mealsLogged('meals_logged', 'Meals logged', 'meals'),
  streak('streak', 'Active-day streak', 'days');

  const GoalMetric(this.key, this.label, this.unit);

  final String key;
  final String label;

  /// Short unit shown after a number, e.g. "4 / 5 sessions".
  final String unit;

  /// What the server counts, in words, for the create sheet.
  String get explanation => switch (this) {
        GoalMetric.steps => 'Every step your phone or watch counts.',
        GoalMetric.activeMinutes =>
          'Minutes of runs, walks, rides and logged workouts.',
        GoalMetric.workouts =>
          'Each run, walk, ride or workout you log counts as one.',
        GoalMetric.mealsLogged => 'Each meal you log counts as one.',
        GoalMetric.streak =>
          'Days in a row with at least one session. Your longest run of '
              'days in the period counts.',
      };

  /// A sensible starting target for [period], so the sheet never opens blank.
  int suggestedTarget(GoalPeriod period) => switch ((this, period)) {
        (GoalMetric.steps, GoalPeriod.weekly) => 50000,
        (GoalMetric.steps, GoalPeriod.monthly) => 200000,
        (GoalMetric.steps, GoalPeriod.annual) => 2500000,
        (GoalMetric.steps, GoalPeriod.custom) => 100000,
        (GoalMetric.activeMinutes, GoalPeriod.weekly) => 150,
        (GoalMetric.activeMinutes, GoalPeriod.monthly) => 600,
        (GoalMetric.activeMinutes, GoalPeriod.annual) => 7500,
        (GoalMetric.activeMinutes, GoalPeriod.custom) => 300,
        (GoalMetric.workouts, GoalPeriod.weekly) => 3,
        (GoalMetric.workouts, GoalPeriod.monthly) => 12,
        (GoalMetric.workouts, GoalPeriod.annual) => 150,
        (GoalMetric.workouts, GoalPeriod.custom) => 8,
        (GoalMetric.mealsLogged, GoalPeriod.weekly) => 14,
        (GoalMetric.mealsLogged, GoalPeriod.monthly) => 60,
        (GoalMetric.mealsLogged, GoalPeriod.annual) => 700,
        (GoalMetric.mealsLogged, GoalPeriod.custom) => 30,
        (GoalMetric.streak, GoalPeriod.weekly) => 3,
        (GoalMetric.streak, GoalPeriod.monthly) => 7,
        (GoalMetric.streak, GoalPeriod.annual) => 30,
        (GoalMetric.streak, GoalPeriod.custom) => 5,
      };

  static GoalMetric? byKey(Object? key) {
    for (final value in values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// How long one round of a goal lasts. Weekly, monthly and annual goals
/// repeat; a custom goal runs once between two dates.
enum GoalPeriod {
  weekly('weekly', 'Weekly', 'this week'),
  monthly('monthly', 'Monthly', 'this month'),
  annual('annual', 'Yearly', 'this year'),
  custom('custom', 'Custom dates', 'by the end date');

  const GoalPeriod(this.key, this.label, this.currentLabel);

  final String key;
  final String label;

  /// How the current period is named in a sentence: "4 of 5 this week".
  final String currentLabel;

  bool get repeats => this != GoalPeriod.custom;

  /// Said under the period choice, so nobody has to guess where a week starts.
  String get repeatNote => switch (this) {
        GoalPeriod.weekly => 'Repeats every week. Weeks run Monday to Sunday.',
        GoalPeriod.monthly => 'Repeats every month.',
        GoalPeriod.annual => 'Repeats every year.',
        GoalPeriod.custom => 'Runs once, between the dates you choose.',
      };

  static GoalPeriod? byKey(Object? key) {
    for (final value in values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

enum GoalStatus {
  active('active'),
  completed('completed'),
  expired('expired'),
  archived('archived');

  const GoalStatus(this.key);

  final String key;

  static GoalStatus byKey(Object? key) {
    for (final value in values) {
      if (value.key == key) return value;
    }
    return GoalStatus.active;
  }
}

class Goal {
  const Goal({
    required this.id,
    required this.metric,
    required this.period,
    required this.target,
    required this.status,
    this.progress = 0,
    this.completedCurrent = false,
    this.completions = 0,
    this.currentStartDayKey,
    this.currentEndDayKey,
    this.startDayKey,
    this.endDayKey,
    this.createdAt,
  });

  /// [createdAt] is passed separately so this file stays free of Firestore's
  /// Timestamp type.
  ///
  /// Null when the document is not a goal this build understands — a metric
  /// or period added by a later build. Skipped rather than shown wrongly.
  static Goal? fromMap(
    String id,
    Map<String, dynamic> data, {
    DateTime? createdAt,
  }) {
    final metric = GoalMetric.byKey(data['metric']);
    final period = GoalPeriod.byKey(data['period']);
    final target = (data['target'] as num?)?.toInt() ?? 0;
    if (metric == null || period == null || target <= 0) return null;
    return Goal(
      id: id,
      metric: metric,
      period: period,
      target: target,
      status: GoalStatus.byKey(data['status']),
      progress: (data['progress'] as num?)?.toInt() ?? 0,
      completedCurrent: data['completedCurrent'] == true,
      completions: (data['completions'] as num?)?.toInt() ?? 0,
      currentStartDayKey: data['currentStartDayKey'] as String?,
      currentEndDayKey: data['currentEndDayKey'] as String?,
      startDayKey: data['startDayKey'] as String?,
      endDayKey: data['endDayKey'] as String?,
      createdAt: createdAt,
    );
  }

  final String id;
  final GoalMetric metric;
  final GoalPeriod period;
  final int target;
  final GoalStatus status;

  /// This period's figure, as the server last worked it out.
  final int progress;

  /// Whether this period has been hit. Stays true for the rest of the period
  /// even if a log is later deleted, as the server keeps it.
  final bool completedCurrent;

  /// Periods hit, all time.
  final int completions;

  final String? currentStartDayKey;
  final String? currentEndDayKey;

  /// Custom goals only.
  final String? startDayKey;
  final String? endDayKey;

  final DateTime? createdAt;

  /// How far along this period is, 0 to 1. Never NaN, never above 1.
  double get fraction {
    if (target <= 0) return 0;
    final value = progress / target;
    return value.clamp(0.0, 1.0);
  }

  bool get isHit => completedCurrent || progress >= target;

  /// What is left, never negative.
  int get remaining => progress >= target ? 0 : target - progress;

  /// "4,200 / 5,000 steps".
  String get progressLabel =>
      '${formatThousands(progress)} / ${formatThousands(target)} ${metric.unit}';

  /// "50,000 steps weekly", as a title.
  String get title => '${formatThousands(target)} ${metric.unit} '
      '${period == GoalPeriod.custom ? 'by $endDayKey' : period.label.toLowerCase()}';
}
