#!/usr/bin/env node
/**
 * Offline check of the food matcher against the bundled table — no Firebase,
 * no network, no API key.
 *
 * Run it after editing data/nutrition_foods.json to confirm the phrasings a
 * vision model actually produces still resolve:
 *
 *   npm run check:nutrition
 */

const {
  readBundled,
  buildIndex,
  matchFood,
  macrosForGrams,
} = require("../nutrition_db");

// Phrasings a vision model realistically returns -> the food id it must hit.
const CASES = [
  ["grilled chicken breast", "chicken-breast"],
  ["chicken breast, skinless", "chicken-breast"],
  ["pap", "pap-stiff"],
  ["stywe pap", "pap-stiff"],
  ["maize porridge", "pap-stiff"],
  ["samp and beans", "samp-and-beans"],
  ["umngqusho", "samp-and-beans"],
  ["boerewors", "boerewors"],
  ["grilled boerewors sausage", "boerewors"],
  ["chakalaka", "chakalaka"],
  ["morogo", "morogo"],
  ["french fries", "chips-fries"],
  ["slap chips", "chips-fries"],
  ["hot chips", "chips-fries"],
  ["white rice", "rice-white"],
  ["steamed white rice", "rice-white"],
  ["brown rice", "rice-brown"],
  ["fried eggs", "egg-fried"],
  ["scrambled egg", "egg-fried"],
  ["boiled eggs", "egg-boiled"],
  ["two slices of white bread", "bread-white"],
  ["brown bread", "bread-brown"],
  ["vetkoek", "vetkoek"],
  ["magwinya", "vetkoek"],
  ["beef mince", "beef-mince"],
  ["mashed potato", "potato-mash"],
  ["green salad", "salad-green"],
  ["avocado", "avocado"],
  ["cheddar cheese", "cheddar"],
  ["full cream milk", "milk-full-cream"],
  ["amasi", "amasi"],
  ["greek yoghurt", "yoghurt-greek"],
  ["banana", "banana"],
  ["bananas", "banana"],
  ["coca cola", "soft-drink"],
  ["mango atchar", "atchar"],
  ["mrs balls chutney", "chutney"],
  ["droëwors", "droewors"],
  ["russian sausage", "russian-sausage"],
  ["tinned pilchards in tomato sauce", "pilchards"],
  ["peanut butter", "peanut-butter"],
  ["cheeseburger", "burger-beef"],
  ["pizza slice", "pizza"],
  ["samoosa", "samoosa"],
  ["whey protein powder", "whey-protein"],
  ["baked beans", "baked-beans"],
  ["sweet potato", "sweet-potato"],
  ["grilled hake", "hake-grilled"],
  ["battered fried fish", "hake-fried"],
];

// Things that must NOT match anything, so a bad match never invents macros.
const NON_MATCHES = ["car keys", "a wooden table", "cutlery", "napkin"];

function run() {
  const foods = readBundled();
  const index = buildIndex(foods);

  let failures = 0;

  for (const [query, expectedId] of CASES) {
    const match = matchFood(index, query);
    const actual = match?.food.id ?? null;
    if (actual !== expectedId) {
      failures += 1;
      console.log(
        `FAIL  "${query}" -> ${actual ?? "no match"} (expected ${expectedId})`
      );
    }
  }

  for (const query of NON_MATCHES) {
    const match = matchFood(index, query);
    if (match) {
      failures += 1;
      console.log(
        `FAIL  "${query}" matched ${match.food.id} — should not match anything`
      );
    }
  }

  // Spot-check the macro maths: 200 g of white rice.
  const rice = foods.find((food) => food.id === "rice-white");
  const macros = macrosForGrams(rice, 200);
  if (macros.calories !== 260 || macros.carbs !== 56) {
    failures += 1;
    console.log(
      `FAIL  200g white rice -> ${JSON.stringify(macros)} (expected 260 kcal, 56 g carbs)`
    );
  }

  const total = CASES.length + NON_MATCHES.length + 1;
  if (failures === 0) {
    console.log(`All ${total} nutrition matching checks passed (${foods.length} foods).`);
  } else {
    console.log(`\n${failures}/${total} checks failed.`);
    process.exitCode = 1;
  }
}

run();
