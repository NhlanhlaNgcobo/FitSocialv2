import 'app_models.dart';
import 'meal_tracking.dart';

/// A meal the user eats on a schedule, logged for them on the days it falls.
///
/// A copy of the meal rather than a pointer to it: the meal it was made from
/// can be deleted, and a repeat that quietly stopped working when its source
/// went would be worse than one that carries its own numbers.
///
/// Logged by the app when it is opened ([MealRepeatSync]), for today only. A
/// day the app was never opened is not filled in afterwards — nobody can say
/// whether the meal was eaten that day, and a guess would sit in the user's
/// totals looking like a fact.
class MealRepeat {
  const MealRepeat({
    required this.id,
    required this.name,
    required this.weekdays,
    required this.hour,
    required this.minute,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.items = const [],
    this.imageUrl,
    this.lastLoggedDay,
  });

  /// A repeat made from a logged meal, due at the time that meal was eaten.
  ///
  /// It starts tomorrow: [lastLoggedDay] is stamped with today, because the
  /// meal it is made from is normally today's, and logging it a second time
  /// the moment the schedule is saved would double it.
  factory MealRepeat.fromMeal(
    LoggedMeal meal, {
    required String id,
    required Set<int> weekdays,
    required DateTime today,
  }) {
    return MealRepeat(
      id: id,
      name: meal.displayName,
      weekdays: weekdays,
      hour: meal.loggedAt.hour,
      minute: meal.loggedAt.minute,
      calories: meal.calories,
      protein: meal.protein,
      carbs: meal.carbs,
      fat: meal.fat,
      items: meal.items,
      imageUrl: meal.imageUrl,
      lastLoggedDay: dayKey(today),
    );
  }

  /// How many repeats one user can keep. A schedule list longer than this is
  /// a meal plan, which is a different feature.
  static const int limit = 12;

  final String id;
  final String name;

  /// [DateTime.weekday] values: 1 is Monday, 7 is Sunday.
  final Set<int> weekdays;

  /// When on those days the meal is logged, in local time.
  final int hour;
  final int minute;

  final int calories;
  final int protein;
  final int carbs;
  final int fat;
  final List<MealFoodItem> items;
  final String? imageUrl;

  /// [dayKey] of the last day this was logged, so a day is never logged
  /// twice however often the app is opened.
  final String? lastLoggedDay;

  /// "2026-10-02" — a calendar day in local time.
  static String dayKey(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}';
  }

  /// When the meal falls on [day]'s date.
  DateTime timeOn(DateTime day) =>
      DateTime(day.year, day.month, day.day, hour, minute);

  /// Whether it should be logged now: one of its days, its time has passed,
  /// and today has not been logged yet.
  bool isDueAt(DateTime now) {
    return weekdays.contains(now.weekday) &&
        !now.isBefore(timeOn(now)) &&
        lastLoggedDay != dayKey(now);
  }

  /// "08:15"
  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// "Every day", "Weekdays", "Weekends" or "Mon, Wed, Fri".
  String get daysLabel => describeWeekdays(weekdays);

  /// "Weekdays at 08:15"
  String get scheduleLabel => '$daysLabel at $timeLabel';

  static String describeWeekdays(Set<int> days) {
    if (days.length == 7) return 'Every day';
    if (days.length == 5 && days.containsAll(const {1, 2, 3, 4, 5})) {
      return 'Weekdays';
    }
    if (days.length == 2 && days.containsAll(const {6, 7})) return 'Weekends';
    final sorted = days.toList()..sort();
    return sorted.map((day) => weekdayShortNames[day - 1]).join(', ');
  }

  static const List<String> weekdayShortNames = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  MealRepeat copyWith({
    Set<int>? weekdays,
    int? hour,
    int? minute,
    String? lastLoggedDay,
  }) {
    return MealRepeat(
      id: id,
      name: name,
      weekdays: weekdays ?? this.weekdays,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      items: items,
      imageUrl: imageUrl,
      lastLoggedDay: lastLoggedDay ?? this.lastLoggedDay,
    );
  }

  static MealRepeat? fromMap(Object? value) {
    if (value is! Map) return null;
    final id = (value['id'] ?? '').toString();
    if (id.isEmpty) return null;
    int readInt(String key) => (value[key] as num?)?.round() ?? 0;
    final days = <int>{
      for (final day in (value['weekdays'] as List?) ?? const [])
        if (day is num && day >= 1 && day <= 7) day.toInt(),
    };
    // A schedule with no days would never fire; reading one back as such is
    // safer than guessing which days were meant.
    if (days.isEmpty) return null;
    return MealRepeat(
      id: id,
      name: (value['name'] ?? '').toString(),
      weekdays: days,
      hour: readInt('hour').clamp(0, 23),
      minute: readInt('minute').clamp(0, 59),
      calories: readInt('calories'),
      protein: readInt('protein'),
      carbs: readInt('carbs'),
      fat: readInt('fat'),
      items: [
        for (final item in (value['items'] as List?) ?? const [])
          if (MealFoodItem.fromMap(item) case final parsed?) parsed,
      ],
      imageUrl: value['imageUrl'] as String?,
      lastLoggedDay: value['lastLoggedDay'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'weekdays': weekdays.toList()..sort(),
        'hour': hour,
        'minute': minute,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'items': items.map((item) => item.toMap()).toList(),
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (lastLoggedDay != null) 'lastLoggedDay': lastLoggedDay,
      };
}
