import 'challenge_points.dart';

/// How a task's number reaches the app.
enum TaskTracking {
  /// Read from data the app already records — the workout log, GPS, Health
  /// Connect, the meal log, the Pulse feed. The user cannot set these by hand,
  /// which is the whole reason the challenge means anything.
  automatic,

  /// Counted by the user, a tap at a time. Water and reading have no sensor
  /// behind them, and inventing one would be worse than admitting it.
  manual,
}

/// What a task's number is measured in. Drives how it prints, nothing else.
enum TaskUnit {
  minutes,
  kilometres,
  glasses,
  steps,
  meals,
  pages,
  posts,
}

/// One of the seven things a Pulse 75 day asks for.
///
/// Ordered as the tracker lists them: the two big physical asks first, then
/// the counters, then the post that makes the day public.
enum ChallengeTask {
  workout(
    key: 'workout',
    label: 'Workout',
    detail: '45 minutes of training',
    target: 45,
    unit: TaskUnit.minutes,
    tracking: TaskTracking.automatic,
  ),
  runWalk(
    key: 'runWalk',
    label: 'Run / Walk',
    detail: '10 km on foot',
    target: 10,
    unit: TaskUnit.kilometres,
    tracking: TaskTracking.automatic,
  ),
  steps(
    key: 'steps',
    label: 'Steps',
    detail: '12,000 steps',
    target: 12000,
    unit: TaskUnit.steps,
    tracking: TaskTracking.automatic,
  ),
  nutrition(
    key: 'nutrition',
    label: 'Nutrition',
    detail: '3 meals logged',
    target: 3,
    unit: TaskUnit.meals,
    tracking: TaskTracking.automatic,
  ),
  water(
    key: 'water',
    label: 'Water',
    detail: '8 glasses',
    target: 8,
    unit: TaskUnit.glasses,
    tracking: TaskTracking.manual,
  ),
  reading(
    key: 'reading',
    label: 'Reading',
    detail: '10 pages',
    target: 10,
    unit: TaskUnit.pages,
    tracking: TaskTracking.manual,
  ),
  pulse(
    key: 'pulse',
    label: 'Pulse',
    detail: '1 progress post',
    target: 1,
    unit: TaskUnit.posts,
    tracking: TaskTracking.automatic,
  );

  const ChallengeTask({
    required this.key,
    required this.label,
    required this.detail,
    required this.target,
    required this.unit,
    required this.tracking,
  });

  /// The stored field name. Never derive this from [name] — a rename of the
  /// enum constant would silently orphan every document already written.
  final String key;

  /// The row title on the tracker.
  final String label;

  /// The one-line restatement under it, for the detail screen.
  final String detail;

  /// What the day asks for.
  final double target;

  final TaskUnit unit;
  final TaskTracking tracking;

  static ChallengeTask? byKey(String key) {
    for (final task in values) {
      if (task.key == key) return task;
    }
    return null;
  }

  /// The tasks the user updates themselves, in tracker order.
  static List<ChallengeTask> get manual => values
      .where((task) => task.tracking == TaskTracking.manual)
      .toList(growable: false);

  bool get isManual => tracking == TaskTracking.manual;

  /// What completing this task is worth. Automatic tasks pay more than manual
  /// ones on purpose: effort the app can verify is worth more than effort it
  /// has to take the user's word for.
  int get points => taskPoints[this]!;

  /// Whether [value] clears the bar.
  bool isMetBy(double value) => value >= target;

  /// The target as it prints — "45 min", "10 km", "12 000 steps".
  String get targetLabel => formatTaskValue(target, unit);

  /// "8.4 / 10 km" — the pair the tracker row shows on the right.
  ///
  /// The unit is carried once, on the target. Printing it on both sides turns
  /// a glanceable pair into a sentence.
  String progressLabel(double current) =>
      '${formatTaskAmount(current, unit)} / $targetLabel';
}

/// One task's state within a single day.
class TaskProgress {
  const TaskProgress({required this.task, required this.current});

  const TaskProgress.empty(this.task) : current = 0;

  final ChallengeTask task;

  /// How much of the target has been done. Not clamped: a 14 km run is a 14 km
  /// run, and flattening it to 10 would hide the effort on a day the user is
  /// looking for a reason to keep going.
  final double current;

  bool get completed => task.isMetBy(current);

  /// 0..1 for the bar. Clamped, because a bar is a bar.
  double get fraction =>
      task.target <= 0 ? 0 : (current / task.target).clamp(0.0, 1.0);

  /// What is still owed, in the task's own unit. Zero once done.
  double get remaining =>
      completed ? 0 : (task.target - current).clamp(0.0, task.target);

  /// "2 glasses", "3.1 km" — the fragment a notification lists as outstanding.
  String get remainingLabel => formatTaskValue(remaining, task.unit);

  String get label => task.progressLabel(current);

  TaskProgress copyWith({double? current}) =>
      TaskProgress(task: task, current: current ?? this.current);
}

/// A task figure on its own, at the precision that unit deserves.
///
/// Distance keeps one decimal because a run is rarely a round number and
/// rounding 9.6 km up to "10 km" would show a task as met when it is not.
/// Everything else is a whole count.
String formatTaskAmount(double value, TaskUnit unit) => switch (unit) {
      TaskUnit.kilometres => _trimDecimal(value),
      TaskUnit.steps => _grouped(value.round()),
      _ => value.round().toString(),
    };

/// A task figure with its unit — "45 min", "10 km", "8 glasses", "1 post".
String formatTaskValue(double value, TaskUnit unit) {
  final amount = formatTaskAmount(value, unit);
  final plural = value.round() != 1;
  final noun = switch (unit) {
    TaskUnit.minutes => 'min',
    TaskUnit.kilometres => 'km',
    TaskUnit.steps => 'steps',
    TaskUnit.glasses => plural ? 'glasses' : 'glass',
    TaskUnit.meals => plural ? 'meals' : 'meal',
    TaskUnit.pages => plural ? 'pages' : 'page',
    TaskUnit.posts => plural ? 'posts' : 'post',
  };
  return '$amount $noun';
}

/// One decimal, with a trailing `.0` dropped: 8.42 -> "8.4", 10.0 -> "10".
String _trimDecimal(double value) {
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

/// 12000 -> "12 000". A narrow no-break space rather than a comma or a full
/// stop: those two swap meanings between locales, and this app ships to both.
String _grouped(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
