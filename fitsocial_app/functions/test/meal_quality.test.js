const { test } = require("node:test");
const assert = require("node:assert/strict");

const {
  scoreItems,
  dayPoints,
  groupOf,
  DAY_LOGGED_BONUS,
} = require("../meal_quality");
const { dayValue } = require("../activity_ranking");
const { dayStatsFrom } = require("../stats")._internals;

/**
 * The same plates as test/meal_quality_test.dart, with the same expected
 * scores. If one side's rules change and the other's do not, these disagree.
 */
const food = (name, grams, calories, protein, carbs, fat, category) => ({
  name, grams, calories, protein, carbs, fat, category,
});

const greatPlate = [
  food("chicken breast", 150, 248, 47, 0, 5, "protein"),
  food("broccoli", 150, 52, 4, 11, 1, "vegetable"),
  food("brown rice", 150, 185, 4, 39, 2, "starch"),
];
const papAndStew = [
  food("pap", 300, 360, 8, 78, 2, "starch"),
  food("beef stew", 250, 350, 33, 18, 15, "dish"),
  food("chakalaka", 100, 80, 2, 10, 4, "vegetable"),
];
const pizzaAndCoke = [
  food("pizza", 300, 798, 33, 90, 33, "dish"),
  food("coke", 330, 139, 0, 35, 0, "drink"),
];
const chocolate = [food("chocolate", 100, 535, 7, 59, 30, "dessert")];

test("scores the same plates the app does", () => {
  assert.equal(scoreItems(greatPlate), 9);
  assert.equal(scoreItems(papAndStew), 7);
  assert.equal(scoreItems(pizzaAndCoke), 4);
  assert.equal(scoreItems(chocolate), 0);
});

test("too little food, or none itemised, gives no score", () => {
  assert.equal(scoreItems([]), null);
  assert.equal(scoreItems(undefined), null);
  assert.equal(scoreItems([food("black coffee", 250, 5, 0, 0, 0, "drink")]), null);
});

test("a cooldrink does not count against the plate weight", () => {
  const plate = [
    food("grilled chicken", 150, 248, 47, 0, 5, "protein"),
    food("green salad", 100, 20, 1, 4, 0, "vegetable"),
    food("water", 500, 0, 0, 0, 0, "drink"),
  ];
  assert.equal(scoreItems(plate), 10);
});

test("macros written as strings are read like numbers", () => {
  const asStrings = greatPlate.map((item) => ({
    ...item,
    calories: String(item.calories),
    protein: String(item.protein),
  }));
  assert.equal(scoreItems(asStrings), 9);
});

test("items are placed by name when the table gave no usable group", () => {
  const groupOfName = (name, category) => groupOf({ name, category });
  assert.equal(groupOfName("Side salad"), "vegetable");
  assert.equal(groupOfName("tomato sauce"), "condiment");
  assert.equal(groupOfName("carrot cake"), "dessert");
  assert.equal(groupOfName("fruit yoghurt"), "dairy");
  assert.equal(groupOfName("orange juice"), "drink");
  assert.equal(groupOfName("kale", "usda"), "vegetable");
  assert.equal(groupOfName("mystery", "Fruit"), "fruit");
  // "other" is a real table group, not a reason to guess from the name.
  assert.equal(groupOfName("side salad", "other"), "other");
});

test("a day scores its best four meals plus the logging bonus", () => {
  const meals = [
    { items: greatPlate },
    { items: papAndStew },
    { items: pizzaAndCoke },
    { items: chocolate },
    { items: greatPlate },
    { name: "typed by hand", calories: 600 },
  ];
  // 9 + 9 + 7 + 4; the chocolate is the fifth and does not count.
  assert.equal(dayPoints(meals), 29 + DAY_LOGGED_BONUS);
});

test("a day with nothing scorable earns nothing, bonus included", () => {
  assert.equal(dayPoints([]), 0);
  assert.equal(dayPoints([{ name: "typed by hand", calories: 600 }]), 0);
});

test("daily stats carry the points, and the challenge metric reads them", () => {
  const day = dayStatsFrom(
    { meals: [{ items: greatPlate }, { qualityScore: 10 }] },
    { maxDailySteps: 100000, maxDailyActiveMinutes: 1440 }
  );
  // The stored qualityScore is ignored: only the rescored plate counts.
  assert.equal(day.mealQualityPoints, 9 + DAY_LOGGED_BONUS);
  assert.equal(dayValue(day, "meal_quality"), 9 + DAY_LOGGED_BONUS);
});
