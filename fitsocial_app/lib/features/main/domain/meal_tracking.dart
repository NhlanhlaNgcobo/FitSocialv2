import 'app_models.dart';
import 'progress_models.dart';

/// One meal as it was logged.
///
/// The stored `meals` document, read back for the tracking page. Distinct from
/// [MealLogDraft], which is what a half-filled form holds on the way in: this
/// carries an id and a real timestamp, and its macros are numbers rather than
/// the strings a text field produces.
class LoggedMeal {
  const LoggedMeal({
    required this.id,
    required this.name,
    required this.loggedAt,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.imageUrl,
    this.itemCount = 0,
    this.sharedToFeed = false,
    this.postId,
  });

  final String id;
  final String name;

  /// When the meal was eaten, in local time.
  final DateTime loggedAt;

  final int calories;
  final int protein;
  final int carbs;
  final int fat;

  final String? imageUrl;

  /// How many foods the analyser identified. Zero for a meal typed by hand.
  final int itemCount;

  final bool sharedToFeed;

  /// The post this meal created, when it was shared. Null otherwise, and for
  /// meals logged before the id was recorded.
  final String? postId;

  /// Local midnight of the day this meal belongs to.
  DateTime get day => ActivityCalendar.dateOnly(loggedAt);

  /// "08:15" — the time under the meal's name.
  String get timeLabel {
    final hour = loggedAt.hour.toString().padLeft(2, '0');
    final minute = loggedAt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// A name to show when the meal was saved without one.
  ///
  /// Named for the time of day rather than left as "Meal", because that is the
  /// distinction the list is actually making between four rows.
  String get displayName {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final hour = loggedAt.hour;
    if (hour < 11) return 'Breakfast';
    if (hour < 15) return 'Lunch';
    if (hour < 18) return 'Snack';
    return 'Dinner';
  }
}

/// Which macro a number is. Drives the colour it is drawn in, everywhere.
enum MacroKind {
  calories,
  protein,
  carbs,
  fat;

  String get label => switch (this) {
        MacroKind.calories => 'Calories',
        MacroKind.protein => 'Protein',
        MacroKind.carbs => 'Carbs',
        MacroKind.fat => 'Fats',
      };

  /// The short letter on a meal row's chip — P / C / F. Calories has none;
  /// they are printed as a figure with its unit instead.
  String get shortLabel => switch (this) {
        MacroKind.calories => '',
        MacroKind.protein => 'P',
        MacroKind.carbs => 'C',
        MacroKind.fat => 'F',
      };

  String get unit => this == MacroKind.calories ? 'kcal' : 'g';
}

/// Daily targets for each macro.
///
/// Defaults are a rough middle for an adult rather than anything derived — the
/// app knows a height and a weight, but not an activity level, a goal or a
/// body composition, and a number invented from two of the five inputs would
/// read as advice it has no business giving. The user can set their own.
class MacroGoals {
  const MacroGoals({
    this.calories = defaultCalories,
    this.protein = defaultProtein,
    this.carbs = defaultCarbs,
    this.fat = defaultFat,
  });

  factory MacroGoals.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const MacroGoals();
    int read(String key, int fallback) =>
        (data[key] as num?)?.toInt() ?? fallback;
    return MacroGoals(
      calories: read('calorieGoal', defaultCalories),
      protein: read('proteinGoal', defaultProtein),
      carbs: read('carbsGoal', defaultCarbs),
      fat: read('fatGoal', defaultFat),
    );
  }

  static const int defaultCalories = 2300;
  static const int defaultProtein = 150;
  static const int defaultCarbs = 260;
  static const int defaultFat = 80;

  final int calories;
  final int protein;
  final int carbs;
  final int fat;

  int of(MacroKind kind) => switch (kind) {
        MacroKind.calories => calories,
        MacroKind.protein => protein,
        MacroKind.carbs => carbs,
        MacroKind.fat => fat,
      };

  /// The target across a whole window.
  ///
  /// A daily goal times the days in the window: a week of eating is judged
  /// against seven days of target, not one. The current week is *not* prorated
  /// to the days elapsed — a Monday-afternoon reading of "14% of your week"
  /// is correct, and pretending otherwise would flatter every partial window.
  int overWindow(MacroKind kind, ProgressWindow window) =>
      of(kind) * window.dayCount;

  MacroGoals copyWith({int? calories, int? protein, int? carbs, int? fat}) {
    return MacroGoals(
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
    );
  }

  Map<String, dynamic> toMap() => {
        'calorieGoal': calories,
        'proteinGoal': protein,
        'carbsGoal': carbs,
        'fatGoal': fat,
      };
}

/// One macro's number against its target.
class MacroProgress {
  const MacroProgress({
    required this.kind,
    required this.total,
    required this.goal,
  });

  final MacroKind kind;
  final int total;
  final int goal;

  /// 0..1, clamped — the bar is a bar, and a 140% day must not paint past its
  /// track. [percent] keeps the real figure for the label.
  double get fraction {
    if (goal <= 0) return 0;
    return (total / goal).clamp(0.0, 1.0);
  }

  /// The percentage as shown, unclamped, so going over is visible.
  int get percent {
    if (goal <= 0) return 0;
    return (total / goal * 100).round();
  }

  bool get isOver => total > goal;
}

/// Everything the tracking page reports for one window.
class MealWindowSummary {
  const MealWindowSummary({
    required this.window,
    required this.meals,
    required this.goals,
  });

  /// Builds a summary from every logged meal, keeping the ones inside [window].
  factory MealWindowSummary.from({
    required List<LoggedMeal> meals,
    required ProgressWindow window,
    required MacroGoals goals,
  }) {
    final inside = meals
        .where((meal) => window.contains(meal.loggedAt))
        .toList(growable: false)
      // Newest last reads as a day in order — breakfast at the top, dinner at
      // the bottom, which is how the meals actually happened.
      ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));

    return MealWindowSummary(window: window, meals: inside, goals: goals);
  }

  final ProgressWindow window;

  /// The meals inside the window, oldest first.
  final List<LoggedMeal> meals;

  final MacroGoals goals;

  bool get isEmpty => meals.isEmpty;

  int total(MacroKind kind) {
    var sum = 0;
    for (final meal in meals) {
      sum += switch (kind) {
        MacroKind.calories => meal.calories,
        MacroKind.protein => meal.protein,
        MacroKind.carbs => meal.carbs,
        MacroKind.fat => meal.fat,
      };
    }
    return sum;
  }

  MacroProgress progress(MacroKind kind) => MacroProgress(
        kind: kind,
        total: total(kind),
        goal: goals.overWindow(kind, window),
      );

  List<MacroProgress> get allProgress =>
      MacroKind.values.map(progress).toList(growable: false);

  /// A sentence about how the window is going.
  ///
  /// Reports the most useful single thing rather than praising unconditionally:
  /// the balance is only worth commending when the numbers support it, and a
  /// day that is well under target should say so.
  String get insight {
    if (isEmpty) return 'Nothing logged yet. Scan a meal to start tracking.';

    final calories = progress(MacroKind.calories);
    final protein = progress(MacroKind.protein);

    if (calories.percent >= 115) {
      return 'Well past your calorie target for this period.';
    }
    if (calories.percent < 50) {
      return "You're well under your calorie target so far.";
    }
    if (protein.percent < 60) {
      return 'Calories are on track — protein is the one lagging.';
    }
    if (calories.percent >= 85 && protein.percent >= 85) {
      return "You're doing great! Keep balancing your macros.";
    }
    return 'On track. Keep the macros balanced.';
  }
}

/// The character separating thousands: a narrow no-break space.
///
/// A space rather than a comma or a full stop, because those two swap meanings
/// between locales and this app ships to both. *No-break*, because a grouped
/// number is one number and must never wrap across two lines. Written as an
/// escape rather than typed literally: an invisible character in a string
/// literal is something the next person cannot see to maintain.
const String thousandsSeparator = '\u202F';

/// A macro figure with its thousands grouped, e.g. 1842 -> "1 842".
String formatMacroValue(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(thousandsSeparator);
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// The date line over the summary, e.g. "Today, 8 May" or "May 2026".
String mealWindowLabel(ProgressWindow window) {
  if (window.period != ProgressPeriod.day) return window.label;

  final start = window.start;
  final date = '${start.day} ${_shortMonth(start)}';
  return switch (window.offset) {
    0 => 'Today, $date',
    -1 => 'Yesterday, $date',
    _ => '${_shortWeekday(start)}, $date',
  };
}

String _shortMonth(DateTime date) => const [
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
    ][date.month - 1];

String _shortWeekday(DateTime date) => const [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ][date.weekday - 1];
