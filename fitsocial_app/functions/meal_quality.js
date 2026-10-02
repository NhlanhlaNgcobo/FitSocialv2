/**
 * Meal quality, scored on the server.
 *
 * The rules are the app's (lib/features/main/domain/meal_quality.dart), kept
 * here as a second copy on purpose: the app stores the score it showed, but a
 * challenge ranks people against each other, and a number a phone wrote is not
 * one a ranking can take on trust. So stats.js scores every meal again from its
 * foods, here, and never reads the stored `qualityScore`.
 *
 * The two copies must agree. test/meal_quality.test.js runs the same plates
 * as test/meal_quality_test.dart, and a change to one set of rules belongs in
 * the other with MealQuality.version bumped.
 *
 *   protein   0-3  share of calories from protein
 *   plants    0-3  share of the plate's weight that is veg, fruit or legumes
 *   treats    0-3  starts full, lost as desserts, snacks and sugary drinks
 *                  take over the calories
 *   fat       0-1  fat under 40% of the calories
 */

const MINIMUM_CALORIES = 50;

const GROUPS = new Set([
  "vegetable", "fruit", "legume", "protein", "starch", "dairy", "fat", "dish",
  "dessert", "snack", "condiment", "drink", "supplement", "other",
]);

const PLANTS = new Set(["vegetable", "fruit", "legume"]);

/** Checked in this order, as in MealFoodGroup.fromName. */
const NAME_RULES = [
  ["dessert", [
    "cake", "chocolate", "ice cream", "cookie", "biscuit", "doughnut",
    "donut", "muffin", "pudding", "koeksister", "melktert", "brownie",
    "candy", "sweets", "pastry", "tart", "custard",
  ]],
  ["drink", [
    "soda", "coke", "cola", "fanta", "sprite", "juice", "soft drink",
    "cooldrink", "energy drink", "beer", "wine", "cider", "milkshake",
  ]],
  ["snack", [
    "crisps", "nachos", "popcorn", "samoosa", "samosa", "spring roll",
  ]],
  ["condiment", [
    "sauce", "ketchup", "mayo", "dressing", "chutney", "atchar", "gravy",
    "jam", "honey", "syrup", "sugar",
  ]],
  ["dairy", ["yoghurt", "yogurt", "cheese", "milk", "amasi"]],
  ["legume", ["lentil", "chickpea", "beans", "hummus"]],
  ["vegetable", [
    "salad", "spinach", "broccoli", "cabbage", "carrot", "tomato", "lettuce",
    "morogo", "chakalaka", "butternut", "pumpkin", "peas", "cucumber",
    "pepper", "onion", "mushroom", "beetroot", "vegetable", "veg", "kale",
    "courgette", "zucchini", "cauliflower", "asparagus", "coleslaw",
  ]],
  ["fruit", [
    "apple", "banana", "orange", "grape", "mango", "pineapple", "berry",
    "berries", "watermelon", "melon", "pear", "peach", "kiwi", "papaya",
    "fruit", "naartjie", "litchi", "guava",
  ]],
];

/** Lenient number read: the app has written macros as ints and as strings. */
function num(value) {
  const n = parseFloat(String(value ?? "").replace(/[^\d.-]/g, ""));
  return Number.isFinite(n) && n > 0 ? n : 0;
}

function groupFromName(name) {
  const words = String(name ?? "").toLowerCase();
  for (const [group, keys] of NAME_RULES) {
    if (keys.some((key) => words.includes(key))) return group;
  }
  return "other";
}

/** The item's food group: the table's when it gave one, else by name. */
function groupOf(item) {
  const category = String(item?.category ?? "").trim().toLowerCase();
  if (category && category !== "usda" && GROUPS.has(category)) return category;
  return groupFromName(item?.matchedFood ?? item?.name);
}

/** Whole numbers throughout, as MealFoodItem.fromMap reads them in the app. */
const whole = (value) => Math.round(num(value));

function caloriesOf(item) {
  const calories = whole(item.calories);
  if (calories > 0) return calories;
  return whole(item.protein) * 4 + whole(item.carbs) * 4 + whole(item.fat) * 9;
}

function isTreat(group, item) {
  if (group === "dessert" || group === "snack" || group === "drink") {
    return true;
  }
  if (group === "condiment") return whole(item.carbs) * 4 > whole(item.fat) * 9;
  return false;
}

function band(value, steps, points) {
  for (let i = 0; i < steps.length; i += 1) {
    if (value >= steps[i]) return points[i];
  }
  return 0;
}

/**
 * Scores a list of food items 0-10, or returns null when there is too little
 * food to judge -- including a meal typed in by hand, which has no items.
 */
function scoreItems(items) {
  if (!Array.isArray(items) || items.length === 0) return null;

  let calories = 0;
  let proteinCalories = 0;
  let fatCalories = 0;
  let treatCalories = 0;
  let plateGrams = 0;
  let plantGrams = 0;

  for (const item of items) {
    if (!item || typeof item !== "object") continue;
    const group = groupOf(item);
    const itemCalories = caloriesOf(item);
    calories += itemCalories;
    proteinCalories += whole(item.protein) * 4;
    fatCalories += whole(item.fat) * 9;
    if (isTreat(group, item)) treatCalories += itemCalories;

    const grams = whole(item.grams);
    if (group !== "drink" && grams > 0) {
      plateGrams += grams;
      if (PLANTS.has(group)) plantGrams += grams;
    }
  }

  if (calories < MINIMUM_CALORIES) return null;

  const proteinShare = proteinCalories / calories;
  const plantShare = plateGrams <= 0 ? 0 : plantGrams / plateGrams;
  const treatShare = treatCalories / calories;
  const fatShare = fatCalories / calories;

  const protein = band(proteinShare, [0.25, 0.18, 0.12], [3, 2, 1]);
  const plants = band(plantShare, [0.35, 0.2, 0.08], [3, 2, 1]);
  const treats =
    treatShare <= 0.05 ? 3 : treatShare <= 0.15 ? 2 : treatShare <= 0.3 ? 1 : 0;
  const fat = fatShare <= 0.4 ? 1 : 0;
  return protein + plants + treats + fat;
}

/** How many of a day's meals count towards its points. */
const MEALS_COUNTED_PER_DAY = 4;

/** Added for any day with at least one scored meal: the consistency part. */
const DAY_LOGGED_BONUS = 5;

/**
 * A day's healthy-eating points: its best four meal scores, plus a bonus for
 * having logged at all.
 *
 * Best four, so twenty snacks are not worth more than three good meals. The
 * bonus is what makes logging every day pay: a week of ordinary plates beats
 * two perfect days and five blank ones.
 */
function dayPoints(meals) {
  const scores = (meals ?? [])
    .map((meal) => scoreItems(meal?.items))
    .filter((score) => score != null)
    .sort((a, b) => b - a)
    .slice(0, MEALS_COUNTED_PER_DAY);
  if (scores.length === 0) return 0;
  return scores.reduce((sum, score) => sum + score, 0) + DAY_LOGGED_BONUS;
}

module.exports = {
  scoreItems,
  dayPoints,
  groupOf,
  MEALS_COUNTED_PER_DAY,
  DAY_LOGGED_BONUS,
};
