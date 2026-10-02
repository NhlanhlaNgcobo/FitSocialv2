import 'app_models.dart';
import 'meal_quality.dart';
import 'meal_repeat.dart';

/// What to buy for the week ahead, worked out from the user's repeating meals.
///
/// The repeats are the closest thing the app has to a meal plan: they say what
/// is eaten and on which days. Seven days of them, foods added up across every
/// meal they appear in, is a list somebody can take to a shop.
///
/// Amounts are the edible weight the meal analysis estimated, so they are a
/// guide to what to buy rather than pack sizes.
class ShoppingList {
  const ShoppingList({required this.sections, required this.from});

  /// The list for the seven days starting [today].
  ///
  /// Today counts only for repeats that have not been logged yet today; the
  /// breakfast already eaten does not need buying again.
  factory ShoppingList.fromRepeats(
    Iterable<MealRepeat> repeats, {
    required DateTime today,
    int days = 7,
  }) {
    final start = DateTime(today.year, today.month, today.day);
    final todayKey = MealRepeat.dayKey(start);
    final lines = <String, _Tally>{};

    for (var offset = 0; offset < days; offset++) {
      final day = DateTime(start.year, start.month, start.day + offset);
      for (final repeat in repeats) {
        if (!repeat.weekdays.contains(day.weekday)) continue;
        if (offset == 0 && repeat.lastLoggedDay == todayKey) continue;
        for (final item in repeat.items) {
          final name = (item.matchedFood ?? item.name).trim();
          if (name.isEmpty || _notBought.contains(name.toLowerCase())) continue;
          final tally = lines.putIfAbsent(
            name.toLowerCase(),
            () => _Tally(name, ShoppingSection.of(MealFoodGroup.of(item))),
          );
          tally.add(item);
        }
      }
    }

    final sections = <ShoppingSection, List<ShoppingItem>>{};
    for (final tally in lines.values) {
      sections.putIfAbsent(tally.section, () => []).add(tally.toItem());
    }
    for (final items in sections.values) {
      items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return ShoppingList(
      from: start,
      sections: {
        for (final section in ShoppingSection.values)
          if (sections[section] case final items?) section: items,
      },
    );
  }

  /// Nothing to buy: tap water, mostly.
  static const _notBought = {'water', 'tap water', 'still water'};

  final DateTime from;

  /// Sections in shop order, each sorted by name. Empty sections are absent.
  final Map<ShoppingSection, List<ShoppingItem>> sections;

  bool get isEmpty => sections.isEmpty;

  int get itemCount =>
      sections.values.fold(0, (sum, items) => sum + items.length);

  /// The list as plain text, for the clipboard or a message.
  String toText() {
    final buffer = StringBuffer('FitSocial shopping list, the week from '
        '${from.day} ${_months[from.month - 1]}\n');
    for (final entry in sections.entries) {
      buffer
        ..writeln()
        ..writeln(entry.key.label);
      for (final item in entry.value) {
        buffer.writeln('- ${item.name}, ${item.amountLabel}');
      }
    }
    return buffer.toString().trimRight();
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

/// One food and how much of it the week needs.
class ShoppingItem {
  const ShoppingItem({
    required this.name,
    required this.grams,
    required this.servings,
  });

  /// Capitalised for the list, e.g. "Broccoli".
  final String name;

  /// Total edible weight across the week; zero when the meals gave none.
  final int grams;

  /// How many meals it appears in.
  final int servings;

  /// "1.2 kg", "450 g", or "3 servings" when no weight was estimated.
  String get amountLabel {
    if (grams >= 1000) {
      final kg = (grams / 100).round() / 10;
      final text = kg == kg.roundToDouble()
          ? kg.toStringAsFixed(0)
          : kg.toStringAsFixed(1);
      return '$text kg';
    }
    if (grams > 0) return '$grams g';
    return servings == 1 ? '1 serving' : '$servings servings';
  }
}

/// The aisles a list is grouped into, in the order most shops lay them out.
enum ShoppingSection {
  produce('Fruit, veg & legumes'),
  protein('Meat, fish & eggs'),
  dairy('Dairy'),
  starch('Bread, grains & starches'),
  other('Everything else');

  const ShoppingSection(this.label);

  final String label;

  static ShoppingSection of(MealFoodGroup group) => switch (group) {
        MealFoodGroup.vegetable ||
        MealFoodGroup.fruit ||
        MealFoodGroup.legume =>
          ShoppingSection.produce,
        MealFoodGroup.protein => ShoppingSection.protein,
        MealFoodGroup.dairy => ShoppingSection.dairy,
        MealFoodGroup.starch => ShoppingSection.starch,
        _ => ShoppingSection.other,
      };
}

class _Tally {
  _Tally(String name, this.section)
      : name = name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);

  final String name;
  final ShoppingSection section;
  int grams = 0;
  int servings = 0;

  void add(MealFoodItem item) {
    grams += item.grams ?? 0;
    servings += 1;
  }

  ShoppingItem toItem() =>
      ShoppingItem(name: name, grams: grams, servings: servings);
}
