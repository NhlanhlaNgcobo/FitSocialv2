import 'app_models.dart';

/// How balanced a meal is, scored 0–10 from what is on the plate.
///
/// Separate from the calorie count on purpose: 600 kcal of chicken, rice and
/// broccoli and 600 kcal of cake are the same number and very different meals.
/// The score rewards the things a plate is easy to judge on, and nothing it
/// would need a lab for:
///
///   protein   0–3  share of the meal's calories that comes from protein
///   plants    0–3  share of the plate's weight that is veg, fruit or legumes
///   treats    0–3  starts full, lost as dessert, snacks and sugary drinks
///                  take over the calories
///   fat       0–1  fat under 40% of the calories
///
/// Each item's food group comes from the nutrition table
/// ([MealFoodItem.category]). Items without one — the model's own estimates,
/// USDA matches, and meals analysed before the group was sent — are placed by
/// their name instead, which is rougher but right for the obvious cases.
///
/// functions/meal_quality.js holds a second copy of these rules, which the
/// healthy-eating challenge ranks on. Change both together and bump [version];
/// the two test files score the same plates so a drift shows up.
class MealQuality {
  const MealQuality._({
    required this.score,
    required this.proteinPoints,
    required this.plantPoints,
    required this.treatPoints,
    required this.fatPoints,
  });

  /// Bump when the rules change, so a stored score can be told apart from
  /// one the current rules would give.
  static const int version = 1;

  /// Below this the meal is a drink or a bite, and a score would say more
  /// about rounding than about the food.
  static const int minimumCalories = 50;

  /// 0–10.
  final int score;

  final int proteinPoints;
  final int plantPoints;
  final int treatPoints;
  final int fatPoints;

  MealQualityBand get band => MealQualityBand.of(score);

  /// Scores the items, or null when there is too little food to judge.
  static MealQuality? of(Iterable<MealFoodItem> items) {
    var calories = 0.0;
    var proteinCalories = 0.0;
    var fatCalories = 0.0;
    var treatCalories = 0.0;
    var plateGrams = 0.0;
    var plantGrams = 0.0;

    for (final item in items) {
      final group = MealFoodGroup.of(item);
      final itemCalories = _caloriesOf(item);
      calories += itemCalories;
      proteinCalories += item.protein * 4;
      fatCalories += item.fat * 9;
      if (_isTreat(group, item)) treatCalories += itemCalories;

      // Plate weight leaves drinks out: a can of cooldrink would otherwise
      // count as a third of the plate and drown the veg next to it.
      final grams = item.grams ?? 0;
      if (group != MealFoodGroup.drink && grams > 0) {
        plateGrams += grams;
        if (group.isPlant) plantGrams += grams;
      }
    }

    if (calories < minimumCalories) return null;

    final proteinShare = proteinCalories / calories;
    final plantShare = plateGrams <= 0 ? 0.0 : plantGrams / plateGrams;
    final treatShare = treatCalories / calories;
    final fatShare = fatCalories / calories;

    final proteinPoints = proteinShare >= 0.25
        ? 3
        : proteinShare >= 0.18
            ? 2
            : proteinShare >= 0.12
                ? 1
                : 0;
    final plantPoints = plantShare >= 0.35
        ? 3
        : plantShare >= 0.20
            ? 2
            : plantShare >= 0.08
                ? 1
                : 0;
    final treatPoints = treatShare <= 0.05
        ? 3
        : treatShare <= 0.15
            ? 2
            : treatShare <= 0.30
                ? 1
                : 0;
    final fatPoints = fatShare <= 0.40 ? 1 : 0;

    return MealQuality._(
      score: proteinPoints + plantPoints + treatPoints + fatPoints,
      proteinPoints: proteinPoints,
      plantPoints: plantPoints,
      treatPoints: treatPoints,
      fatPoints: fatPoints,
    );
  }

  /// Up to three short notes on why the meal scored what it did, the good
  /// ones first. Worded as observations, never as instructions.
  List<String> get notes {
    return [
      if (proteinPoints == 3) 'Plenty of protein',
      if (plantPoints == 3) 'Lots of veg or fruit',
      if (proteinPoints <= 1) 'Light on protein',
      if (plantPoints == 0) 'No veg or fruit',
      if (treatPoints <= 1) 'Mostly treats',
      if (fatPoints == 0) 'High in fat',
    ].take(3).toList();
  }

  /// The item's calories, or its macros' worth when the figure is missing.
  static double _caloriesOf(MealFoodItem item) {
    if (item.calories > 0) return item.calories.toDouble();
    return (item.protein * 4 + item.carbs * 4 + item.fat * 9).toDouble();
  }

  /// Sugary condiments count as treats; fatty ones (mayo, dressing) are
  /// already caught by the fat share and are not counted twice.
  static bool _isTreat(MealFoodGroup group, MealFoodItem item) {
    return switch (group) {
      MealFoodGroup.dessert || MealFoodGroup.snack || MealFoodGroup.drink =>
        true,
      MealFoodGroup.condiment => item.carbs * 4 > item.fat * 9,
      _ => false,
    };
  }
}

/// The four labels a score is shown under. "Treat" rather than "Poor": a
/// slice of cake is not a failure, and the label is seen by everyone a meal
/// is shared with.
enum MealQualityBand {
  great('Great'),
  good('Good'),
  fair('Fair'),
  treat('Treat');

  const MealQualityBand(this.label);

  final String label;

  static MealQualityBand of(int score) {
    if (score >= 8) return MealQualityBand.great;
    if (score >= 6) return MealQualityBand.good;
    if (score >= 4) return MealQualityBand.fair;
    return MealQualityBand.treat;
  }
}

/// The nutrition table's food groups, as the score sees them.
enum MealFoodGroup {
  vegetable,
  fruit,
  legume,
  protein,
  starch,
  dairy,
  fat,
  dish,
  dessert,
  snack,
  condiment,
  drink,
  supplement,
  other;

  bool get isPlant =>
      this == MealFoodGroup.vegetable ||
      this == MealFoodGroup.fruit ||
      this == MealFoodGroup.legume;

  /// The item's group from the table, or from its name when the table did
  /// not say. "usda" is a source, not a group, so it is placed by name too.
  static MealFoodGroup of(MealFoodItem item) {
    final category = item.category?.trim().toLowerCase();
    if (category != null && category != 'usda') {
      for (final group in MealFoodGroup.values) {
        if (group.name == category) return group;
      }
    }
    return fromName(item.matchedFood ?? item.name);
  }

  /// Rough placement by keyword. Checked in order, so "fruit yoghurt" lands
  /// on dairy, "carrot cake" on dessert and "tomato sauce" on condiment
  /// before any of them reaches the plants.
  static MealFoodGroup fromName(String name) {
    final words = name.toLowerCase();
    bool has(List<String> keys) => keys.any(words.contains);

    if (has(_dessertWords)) return MealFoodGroup.dessert;
    if (has(_drinkWords)) return MealFoodGroup.drink;
    if (has(_snackWords)) return MealFoodGroup.snack;
    if (has(_condimentWords)) return MealFoodGroup.condiment;
    if (has(_dairyWords)) return MealFoodGroup.dairy;
    if (has(_legumeWords)) return MealFoodGroup.legume;
    if (has(_vegetableWords)) return MealFoodGroup.vegetable;
    if (has(_fruitWords)) return MealFoodGroup.fruit;
    return MealFoodGroup.other;
  }

  static const _dessertWords = [
    'cake', 'chocolate', 'ice cream', 'cookie', 'biscuit', 'doughnut',
    'donut', 'muffin', 'pudding', 'koeksister', 'melktert', 'brownie',
    'candy', 'sweets', 'pastry', 'tart', 'custard',
  ];
  static const _drinkWords = [
    'soda', 'coke', 'cola', 'fanta', 'sprite', 'juice', 'soft drink',
    'cooldrink', 'energy drink', 'beer', 'wine', 'cider', 'milkshake',
  ];
  static const _snackWords = [
    'crisps', 'nachos', 'popcorn', 'samoosa', 'samosa', 'spring roll',
  ];
  static const _condimentWords = [
    'sauce', 'ketchup', 'mayo', 'dressing', 'chutney', 'atchar', 'gravy',
    'jam', 'honey', 'syrup', 'sugar',
  ];
  static const _dairyWords = ['yoghurt', 'yogurt', 'cheese', 'milk', 'amasi'];
  static const _legumeWords = ['lentil', 'chickpea', 'beans', 'hummus'];
  static const _vegetableWords = [
    'salad', 'spinach', 'broccoli', 'cabbage', 'carrot', 'tomato', 'lettuce',
    'morogo', 'chakalaka', 'butternut', 'pumpkin', 'peas', 'cucumber',
    'pepper', 'onion', 'mushroom', 'beetroot', 'vegetable', 'veg', 'kale',
    'courgette', 'zucchini', 'cauliflower', 'asparagus', 'coleslaw',
  ];
  static const _fruitWords = [
    'apple', 'banana', 'orange', 'grape', 'mango', 'pineapple', 'berry',
    'berries', 'watermelon', 'melon', 'pear', 'peach', 'kiwi', 'papaya',
    'fruit', 'naartjie', 'litchi', 'guava',
  ];
}
