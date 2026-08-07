/**
 * Nutrition database - the food composition table the meal analyzer resolves
 * against.
 *
 * The vision model's job is to say WHAT is on the plate and HOW MUCH of it.
 * The macros themselves come from here: per-100 g composition values scaled to
 * the estimated portion. That split matters, because models are decent at
 * recognising food and poor at recalling nutrition tables - asking one to do
 * both is where the wildly wrong calorie numbers came from.
 *
 * Lookup order for each item:
 *   1. Firestore `nutritionFoods` (editable without a redeploy)
 *   2. The bundled data/nutrition_foods.json (always present, works offline
 *      and on a cold project before anything has been seeded)
 *   3. USDA FoodData Central, if FDC_API_KEY is configured
 *   4. The model's own estimate, flagged as such
 */

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const BUNDLED_PATH = path.join(__dirname, "data", "nutrition_foods.json");
const COLLECTION = "nutritionFoods";

/** How long a warm instance may reuse the loaded table before re-reading. */
const CACHE_TTL_MS = 10 * 60 * 1000;

/** Below this a match is discarded in favour of the model's own estimate. */
const MATCH_THRESHOLD = 0.55;

let cache = null;
let cacheLoadedAt = 0;

function ensureAdmin() {
  if (admin.apps.length === 0) {
    admin.initializeApp();
  }
  return admin;
}

/** Lowercase, strip accents and punctuation, collapse whitespace. */
function normalize(value) {
  return String(value ?? "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Words that describe serving or packaging rather than the food itself.
 *
 * Cooking methods are deliberately NOT in here: "fried" vs "grilled" changes
 * the macros enough that the table carries separate entries, and dropping the
 * word would collapse them.
 */
const NOISE_WORDS = new Set([
  "a", "an", "the", "of", "with", "and", "in", "on", "some", "fresh",
  "homemade", "cooked", "raw", "plain", "sliced", "chopped", "diced",
  "serving", "portion", "piece", "pieces", "side", "small", "medium",
  "large", "half", "whole", "cup", "bowl", "plate", "glass",
]);

function tokenize(value) {
  return normalize(value)
    .split(" ")
    .map(singularize)
    .filter((token) => token.length > 1 && !NOISE_WORDS.has(token));
}

/** Crude but adequate: the table is English and mostly regular plurals. */
function singularize(token) {
  if (token.length > 4 && token.endsWith("ies")) {
    return `${token.slice(0, -3)}y`;
  }
  if (token.length > 4 && (token.endsWith("ses") || token.endsWith("hes"))) {
    return token.slice(0, -2);
  }
  if (token.length > 3 && token.endsWith("s") && !token.endsWith("ss")) {
    return token.slice(0, -1);
  }
  return token;
}

function coerceFood(raw, id) {
  const per100g = raw.per100g ?? {};
  const num = (v) => {
    const n = Number(v);
    return Number.isFinite(n) && n >= 0 ? n : 0;
  };
  return {
    id: raw.id ?? id,
    name: String(raw.name ?? id),
    aliases: Array.isArray(raw.aliases) ? raw.aliases.map(String) : [],
    category: String(raw.category ?? "other"),
    per100g: {
      calories: num(per100g.calories),
      protein: num(per100g.protein),
      carbs: num(per100g.carbs),
      fat: num(per100g.fat),
    },
    unitGrams: Number.isFinite(Number(raw.unitGrams))
      ? Number(raw.unitGrams)
      : null,
    unitName: raw.unitName ? String(raw.unitName) : null,
    defaultPortionGrams: Number.isFinite(Number(raw.defaultPortionGrams))
      ? Number(raw.defaultPortionGrams)
      : 150,
  };
}

function readBundled() {
  try {
    const raw = JSON.parse(fs.readFileSync(BUNDLED_PATH, "utf8"));
    return raw.map((entry) => coerceFood(entry, entry.id));
  } catch (error) {
    console.error("Failed to read bundled nutrition table:", error);
    return [];
  }
}

async function readFirestore() {
  const db = ensureAdmin().firestore();
  const snapshot = await db.collection(COLLECTION).get();
  return snapshot.docs.map((doc) => coerceFood(doc.data(), doc.id));
}

/**
 * Inverse document frequency per token, counted once per food.
 *
 * "sauce" and "chicken" appear all over the table and identify almost nothing;
 * "pilchard" appears once and identifies its food outright. Weighting shared
 * tokens by rarity is what stops "pilchards in tomato sauce" resolving to
 * tomato sauce, which two matching common words would otherwise win.
 */
function buildIdf(entries) {
  const documentFrequency = new Map();
  for (const { tokenSets } of entries) {
    const seen = new Set();
    for (const { tokens } of tokenSets) {
      for (const token of tokens) seen.add(token);
    }
    for (const token of seen) {
      documentFrequency.set(token, (documentFrequency.get(token) ?? 0) + 1);
    }
  }

  const total = Math.max(entries.length, 1);
  const idf = new Map();
  for (const [token, frequency] of documentFrequency) {
    idf.set(token, Math.log(total / frequency) + 1);
  }
  return idf;
}

/** Alias index, token sets and IDF weights, built once per load. */
function buildIndex(foods) {
  const byAlias = new Map();
  const entries = [];

  for (const food of foods) {
    const labels = [food.name, ...food.aliases];
    const tokenSets = [];
    for (const label of labels) {
      const key = normalize(label);
      if (key && !byAlias.has(key)) byAlias.set(key, food);
      // The singularised form too, so "eggs" hits an "egg" alias.
      const singular = tokenize(label).join(" ");
      if (singular && !byAlias.has(singular)) byAlias.set(singular, food);
      tokenSets.push({ label, tokens: new Set(tokenize(label)) });
    }
    entries.push({ food, tokenSets });
  }

  return { byAlias, entries, foods, idf: buildIdf(entries) };
}

/**
 * The loaded table, preferring Firestore and falling back to the bundled file.
 *
 * A Firestore read failure is not fatal: the bundled table is the same data the
 * seed script uploads, so analysis keeps working on a project where the
 * collection was never seeded or rules are still being sorted out.
 */
async function loadFoodIndex() {
  const now = Date.now();
  if (cache && now - cacheLoadedAt < CACHE_TTL_MS) return cache;

  let foods = [];
  let source = "bundled";
  try {
    foods = await readFirestore();
    source = "firestore";
  } catch (error) {
    console.warn(
      "nutritionFoods read failed, using bundled table:",
      error.message
    );
  }
  if (foods.length === 0) {
    foods = readBundled();
    source = "bundled";
  }

  cache = { ...buildIndex(foods), source };
  cacheLoadedAt = now;
  console.log(`Nutrition table loaded: ${foods.length} foods from ${source}.`);
  return cache;
}

function idfOf(index, token) {
  // An unseen token is maximally distinctive, so treat it as rarer than
  // anything in the table rather than as free.
  return index.idf?.get(token) ?? Math.log(Math.max(index.foods.length, 1)) + 1;
}

function weightOf(index, tokens) {
  let total = 0;
  for (const token of tokens) total += idfOf(index, token);
  return total;
}

/**
 * Best match for a free-text food name, or null when nothing is close enough.
 *
 * Scoring is deliberately conservative - a wrong match produces confidently
 * wrong macros, which is worse than falling through to the model's estimate.
 */
function matchFood(index, query) {
  const key = normalize(query);
  if (!key) return null;

  const queryTokenList = tokenize(query);
  const direct =
    index.byAlias.get(key) ?? index.byAlias.get(queryTokenList.join(" "));
  if (direct) return { food: direct, score: 1, method: "exact" };

  const queryTokens = new Set(queryTokenList);
  if (queryTokens.size === 0) return null;

  // The rarest word in the description is the one that names the food:
  // in "tinned pilchards in tomato sauce" that is "pilchard", not "sauce".
  let rarestToken = null;
  let rarestWeight = -1;
  for (const token of queryTokens) {
    const weight = idfOf(index, token);
    if (weight > rarestWeight) {
      rarestWeight = weight;
      rarestToken = token;
    }
  }

  const queryWeight = weightOf(index, queryTokens);

  let best = null;
  for (const { food, tokenSets } of index.entries) {
    for (const { tokens } of tokenSets) {
      if (tokens.size === 0) continue;

      let sharedWeight = 0;
      for (const token of tokens) {
        if (queryTokens.has(token)) sharedWeight += idfOf(index, token);
      }
      if (sharedWeight === 0) continue;

      // Reward covering the alias fully ("chicken breast" both present) and
      // penalise query words the alias doesn't account for, so a long
      // description doesn't match a one-word alias by accident. Both sides are
      // weighted by rarity rather than counted.
      const aliasCoverage = sharedWeight / weightOf(index, tokens);
      const queryCoverage = queryWeight > 0 ? sharedWeight / queryWeight : 0;
      const namesFood = rarestToken && tokens.has(rarestToken) ? 0.15 : 0;
      const score = aliasCoverage * 0.7 + queryCoverage * 0.3 + namesFood;

      if (!best || score > best.score) {
        best = { food, score, method: "fuzzy" };
      }
    }
  }

  if (!best || best.score < MATCH_THRESHOLD) return null;
  return best;
}

/** Scales a food's per-100 g composition to [grams]. */
function macrosForGrams(food, grams) {
  const factor = (Number(grams) || 0) / 100;
  return {
    calories: Math.round(food.per100g.calories * factor),
    protein: Math.round(food.per100g.protein * factor),
    carbs: Math.round(food.per100g.carbs * factor),
    fat: Math.round(food.per100g.fat * factor),
  };
}

const FDC_NUTRIENT_IDS = {
  calories: 1008,
  protein: 1003,
  fat: 1004,
  carbs: 1005,
};

/**
 * USDA FoodData Central fallback for foods missing from the local table.
 *
 * Optional: without FDC_API_KEY nothing is called and the caller falls back to
 * the model's own estimate. Free keys: https://fdc.nal.usda.gov/api-key-signup
 */
async function lookupUsda(query, apiKey) {
  if (!apiKey) return null;
  try {
    const url =
      "https://api.nal.usda.gov/fdc/v1/foods/search" +
      `?api_key=${encodeURIComponent(apiKey)}` +
      `&query=${encodeURIComponent(query)}` +
      "&pageSize=1&dataType=Foundation,SR%20Legacy";

    const response = await fetch(url, { signal: AbortSignal.timeout(6000) });
    if (!response.ok) {
      console.warn(`FDC search failed (${response.status}) for "${query}".`);
      return null;
    }

    const body = await response.json();
    const hit = body?.foods?.[0];
    if (!hit) return null;

    const per100g = { calories: 0, protein: 0, carbs: 0, fat: 0 };
    for (const nutrient of hit.foodNutrients ?? []) {
      for (const [macro, id] of Object.entries(FDC_NUTRIENT_IDS)) {
        if (nutrient.nutrientId === id) {
          per100g[macro] = Number(nutrient.value) || 0;
        }
      }
    }
    if (per100g.calories === 0 && per100g.protein === 0) return null;

    return {
      id: `fdc-${hit.fdcId}`,
      name: String(hit.description ?? query),
      aliases: [],
      category: "usda",
      per100g,
      unitGrams: null,
      unitName: null,
      defaultPortionGrams: 100,
    };
  } catch (error) {
    console.warn(`FDC lookup error for "${query}":`, error.message);
    return null;
  }
}

/** Text search over the local table, for the client's food picker. */
async function searchFoods(query, limit = 20) {
  const index = await loadFoodIndex();
  const tokens = new Set(tokenize(query));
  const key = normalize(query);

  const scored = index.foods
    .map((food) => {
      const labels = [food.name, ...food.aliases];
      let score = 0;
      for (const label of labels) {
        const normalized = normalize(label);
        if (normalized === key) score = Math.max(score, 1);
        else if (key && normalized.startsWith(key)) score = Math.max(score, 0.9);
        else if (key && normalized.includes(key)) score = Math.max(score, 0.75);
        else {
          const labelTokens = new Set(tokenize(label));
          let shared = 0;
          for (const token of labelTokens) {
            if (tokens.has(token)) shared += 1;
          }
          if (shared > 0 && labelTokens.size > 0) {
            score = Math.max(score, (shared / labelTokens.size) * 0.6);
          }
        }
      }
      return { food, score };
    })
    .filter((entry) => entry.score > 0.2)
    .sort((a, b) => b.score - a.score)
    .slice(0, limit);

  return scored.map((entry) => entry.food);
}

/** Drops the cached table - used by tests and the seed script. */
function clearCache() {
  cache = null;
  cacheLoadedAt = 0;
}

module.exports = {
  loadFoodIndex,
  buildIndex,
  matchFood,
  macrosForGrams,
  lookupUsda,
  searchFoods,
  readBundled,
  normalize,
  tokenize,
  clearCache,
  COLLECTION,
};
