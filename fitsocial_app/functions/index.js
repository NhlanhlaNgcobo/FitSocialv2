const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const { defineSecret, defineString } = require("firebase-functions/params");
const { OpenAI } = require("openai");
const admin = require("firebase-admin");
const nutrition = require("./nutrition_db");

// Everything runs in Johannesburg, beside the database.
//
// This is not a preference. Second-generation Firestore triggers must run in
// the same region as the database they listen to, and this project's Firestore
// lives in africa-south1 — so the eight challenge triggers were always going to
// be here. What was left behind was the rest: callables and scheduled jobs
// default to us-central1 when nothing says otherwise, and nothing did.
//
// That split cost two things. Every callable made a round trip to Iowa, about a
// quarter-second of pure travel on operations that otherwise answer instantly —
// food search most visibly. And the nightly finalisation swept a Johannesburg
// database from Iowa, reading across a continent to close days.
//
// It also put South African users' health data — meals, weight, workouts —
// through a region they do not live in, which for an app handling this kind of
// data is worth avoiding on its own.
//
// This must be called before any function is defined below, and before
// ./challenges is required at the foot of this file: the v2 API reads the
// global options at definition time, so a function declared earlier would keep
// the old default.
//
// Moving a callable's region changes the URL clients call. See
// `functionsForRegion` in lib/features/auth/data/firebase_auth_repository.dart
// — the Dart side must point at the same region or every call 404s.
setGlobalOptions({ region: "africa-south1" });

// The Firebase Web API key, used to verify a password against Identity
// Toolkit. Not a secret — it ships inside every copy of the client app, and is
// the same value as `web.apiKey` in lib/firebase_options.dart — which is why it
// is read from functions/.env rather than declared with defineSecret.
//
// Deliberately not called FIREBASE_WEB_API_KEY: the Functions runtime reserves
// the FIREBASE_ prefix and refuses to load a .env file that uses it.
const webApiKey = () => process.env.WEB_API_KEY || "";

// Set with: firebase functions:secrets:set OPENROUTER_API_KEY
const openrouterApiKey = defineSecret("OPENROUTER_API_KEY");

// Optional USDA FoodData Central fallback, for foods the local table doesn't
// cover. Free key: https://fdc.nal.usda.gov/api-key-signup — put it in
// functions/.env as FDC_API_KEY. Read from the environment rather than
// declared as a secret on purpose: a declared-but-missing secret fails the
// deploy, and this fallback has to stay genuinely optional.
const fdcApiKey = () => process.env.FDC_API_KEY || "";

// Any OpenRouter vision-capable model id — they are vendor-prefixed, e.g.
// "openai/gpt-5.6-luna", "anthropic/claude-sonnet-5", "google/gemini-3.6-flash".
// Override with the VISION_MODEL env var (functions/.env) — no code change
// needed, which is what makes comparing models on real photos cheap.
const visionModel = defineString("VISION_MODEL", {
  default: "openai/gpt-5.6-luna",
});

/**
 * The model is asked for identification and portion size ONLY — plus a rough
 * macro estimate used as a last-resort fallback. The authoritative macros come
 * from the nutrition database, which is why `grams` is the field that matters
 * most here.
 */
const RESPONSE_SHAPE = `Return ONLY a valid JSON object with this exact shape:
{
  "name": "<short meal name>",
  "confidence": "<low | medium | high>",
  "notes": "<one short sentence on portion assumptions, or empty string>",
  "foodItems": [
    {
      "name": "<plain food name, e.g. 'grilled chicken breast', 'pap', 'chips'>",
      "grams": <estimated edible weight of this item in grams, as a NUMBER>,
      "quantity": "<human-readable portion, e.g. '1 cup', '2 slices', 'half a plate'>",
      "estimatedCalories": <your own rough kcal estimate as a NUMBER>,
      "estimatedProtein": <grams as a NUMBER>,
      "estimatedCarbs": <grams as a NUMBER>,
      "estimatedFat": <grams as a NUMBER>
    }
  ]
}

Return ONLY the JSON object, no markdown formatting, no explanation, no code fences.`;

const PROMPT = `You are a registered dietitian analysing a meal photo for a South African fitness app.

Your ONE critical job is to identify every food item and estimate its WEIGHT IN GRAMS as accurately as possible. The app looks the macros up in a food-composition database from the weight you give, so the gram estimate drives everything.

METHOD — follow in order:
1. Identify every distinct food and drink item visible. Name each one plainly and specifically ("grilled chicken breast", not "protein"; "pap", not "starch"). Split composite dishes into their parts when they are visibly separate on the plate.
2. Estimate each item's edible weight in grams using visual reference cues: a standard dinner plate is ~26 cm across, a fork is ~19 cm, an adult fist is about 1 cup which is about 250 ml, a matchbox is about 30 g of meat or cheese, a golf ball is about 2 tablespoons, a deck of cards is about 100 g of cooked meat.
3. Note the cooking method in the item name when it changes the fat content — "fried", "grilled", "battered", "creamy". Say "fried chips" rather than "potatoes" when they are chips.
4. Include cooking oil, butter, sauces and dressings as their own items when they are clearly present, with their own gram estimate.
5. Also give your own rough macro estimate per item. It is only used when a food is missing from the database.

SOUTH AFRICAN FOODS — name these exactly when you see them so they resolve correctly: pap, krummelpap, samp and beans (umngqusho), chakalaka, morogo, boerewors, biltong, droëwors, vetkoek (magwinya), bunny chow, kota, gatsby, bobotie, russians, polony, atchar, amasi, mageu, chicken feet, tripe (mogodu), koeksister, melktert, malva pudding, braaibroodjie, slap chips.

RULES:
- Be realistic, not conservative: restaurant and township portions are typically 1.5 to 2 times textbook servings.
- If an item is partially hidden, estimate what is plausible and mention it in "notes".
- Every item MUST have a positive "grams" value.
- If the image contains NO food or drink at all, return an empty foodItems array, name "Not a meal", confidence "low", and say why in "notes".

${RESPONSE_SHAPE}`;

const toNum = (v) => {
  const n = parseFloat(String(v ?? "").replace(/[^\d.-]/g, ""));
  return Number.isFinite(n) && n >= 0 ? n : 0;
};

const EMPTY_TOTALS = { calories: 0, protein: 0, carbs: 0, fat: 0 };

/**
 * Turns one model-reported item into a resolved item with database-backed
 * macros where possible.
 *
 * `source` tells the user (and us) where each number came from:
 *   "database" — matched the curated food table, macros computed from grams
 *   "usda"     — matched USDA FoodData Central
 *   "estimate" — no match; the model's own numbers, used as-is
 */
async function resolveItem(item, index, usdaKey) {
  const name = String(item.name ?? "").trim();
  const estimate = {
    calories: Math.round(toNum(item.estimatedCalories ?? item.calories)),
    protein: Math.round(toNum(item.estimatedProtein ?? item.protein)),
    carbs: Math.round(toNum(item.estimatedCarbs ?? item.carbs)),
    fat: Math.round(toNum(item.estimatedFat ?? item.fat)),
  };

  if (!name) return null;

  const match = nutrition.matchFood(index, name);
  let food = match?.food ?? null;
  let source = match ? "database" : null;

  if (!food && usdaKey) {
    food = await nutrition.lookupUsda(name, usdaKey);
    if (food) source = "usda";
  }

  // Grams the model gave, or the matched food's typical portion when it left
  // the field out — better than dropping the item entirely.
  let grams = Math.round(toNum(item.grams));
  if (grams <= 0) grams = food?.defaultPortionGrams ?? 0;

  if (!food || grams <= 0) {
    return {
      name,
      matchedFood: null,
      grams: grams > 0 ? grams : null,
      quantity: String(item.quantity ?? (grams > 0 ? `${grams}g` : "")),
      source: "estimate",
      per100g: null,
      ...estimate,
    };
  }

  const macros = nutrition.macrosForGrams(food, grams);
  return {
    name,
    matchedFood: food.name,
    foodId: food.id,
    grams,
    quantity: String(item.quantity ?? "").trim() || `${grams}g`,
    source,
    // Sent to the client so it can recompute macros locally when the user
    // corrects a portion, without another round trip.
    per100g: food.per100g,
    ...macros,
  };
}

function sumTotals(items) {
  return items.reduce(
    (acc, item) => ({
      calories: acc.calories + toNum(item.calories),
      protein: acc.protein + toNum(item.protein),
      carbs: acc.carbs + toNum(item.carbs),
      fat: acc.fat + toNum(item.fat),
    }),
    { ...EMPTY_TOTALS }
  );
}

/**
 * analyzeMeal — Callable Cloud Function.
 *
 * Receives { imageUrl }, sends the photo to a vision model via OpenRouter for
 * identification and portion estimation, then resolves every item against the
 * nutrition database to produce the macros.
 *
 * Returns:
 *   { name, calories, protein, carbs, fat, confidence, notes,
 *     foodItems: [{ name, matchedFood, grams, quantity, source, per100g,
 *                   calories, protein, carbs, fat }],
 *     databaseCoverage }
 */
exports.analyzeMeal = onCall(
  {
    secrets: [openrouterApiKey],
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async (request) => {
    // --- Auth guard ---
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to analyze a meal."
      );
    }

    // --- Validate input ---
    const { imageUrl } = request.data;
    if (!imageUrl || typeof imageUrl !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "A valid imageUrl string is required."
      );
    }

    // --- Verify API key is available ---
    const apiKey = openrouterApiKey.value();
    if (!apiKey) {
      throw new HttpsError(
        "failed-precondition",
        "OpenRouter API key is not configured. Run: firebase functions:secrets:set OPENROUTER_API_KEY"
      );
    }

    // --- Call the vision model via OpenRouter (OpenAI-compatible API) ---
    const openrouter = new OpenAI({
      apiKey,
      baseURL: "https://openrouter.ai/api/v1",
      defaultHeaders: {
        "HTTP-Referer": "https://fitsocialv2.web.app",
        "X-Title": "FitSocial",
      },
    });

    try {
      // The food table load runs alongside the vision call rather than after
      // it — a cold instance would otherwise add its Firestore read to the
      // user's wait.
      const [response, index] = await Promise.all([
        openrouter.chat.completions.create({
          model: visionModel.value(),
          messages: [
            {
              role: "user",
              content: [
                { type: "text", text: PROMPT },
                {
                  type: "image_url",
                  image_url: { url: imageUrl },
                },
              ],
            },
          ],
          // Headroom for reasoning as well as the answer. Current reasoning
          // models on both OpenAI and Anthropic draw their thinking from this
          // same budget, so a tight cap truncates the JSON mid-object — which
          // surfaces below as a parse failure rather than as truncation.
          max_tokens: 4000,
          // No `temperature` on purpose: current Claude models reject
          // non-default sampling parameters with a 400, and leaving it unset
          // keeps this request valid whichever model VISION_MODEL names.
          // Output shape is pinned by the response contract in the prompt.
        }),
        nutrition.loadFoodIndex(),
      ]);

      const content = response.choices?.[0]?.message?.content;
      if (!content) {
        throw new HttpsError(
          "internal",
          "The vision model returned an empty response."
        );
      }

      // --- Parse the JSON response ---
      let parsed;
      try {
        const cleaned = content
          .replace(/```json\s*/gi, "")
          .replace(/```\s*/g, "")
          .trim();
        parsed = JSON.parse(cleaned);
      } catch (parseError) {
        console.error("Failed to parse model response:", content);
        throw new HttpsError(
          "internal",
          "The vision model returned invalid JSON. Raw response: " + content
        );
      }

      if (!parsed.name) {
        throw new HttpsError(
          "internal",
          "Model response missing required field: name"
        );
      }

      // --- Resolve every item against the nutrition database ---
      const rawItems = Array.isArray(parsed.foodItems) ? parsed.foodItems : [];
      const usdaKey = fdcApiKey();
      const resolved = (
        await Promise.all(
          rawItems.map((item) => resolveItem(item, index, usdaKey))
        )
      ).filter(Boolean);

      // --- Totals are the sum of the resolved items ---
      // Nothing is taken from the model's own totals: the per-item figures are
      // database-derived, and a total that disagrees with its own breakdown is
      // what made the old numbers untrustworthy.
      let totals = sumTotals(resolved);

      // Sanity bound for an all-estimate meal: kcal should roughly match
      // 4P + 4C + 9F (Atwater). Database-backed items already satisfy this by
      // construction, so this only catches a model that hallucinated.
      const fromDatabase = resolved.filter(
        (item) => item.source !== "estimate"
      ).length;
      if (fromDatabase === 0 && resolved.length > 0) {
        const atwater =
          4 * totals.protein + 4 * totals.carbs + 9 * totals.fat;
        if (
          atwater > 0 &&
          (totals.calories < atwater * 0.5 || totals.calories > atwater * 2)
        ) {
          console.warn(
            `Calorie/macro mismatch: model said ${totals.calories} kcal, ` +
              `Atwater gives ${atwater}. Using Atwater.`
          );
          totals.calories = atwater;
        }
      }

      const coverage =
        resolved.length > 0 ? fromDatabase / resolved.length : 0;

      // A meal the database recognised end to end is worth more confidence
      // than the model alone claimed; one it barely recognised is worth less.
      let confidence = ["low", "medium", "high"].includes(parsed.confidence)
        ? parsed.confidence
        : "medium";
      if (resolved.length > 0) {
        if (coverage === 1 && confidence === "medium") confidence = "high";
        if (coverage < 0.5) confidence = "low";
      }

      return {
        name: String(parsed.name),
        calories: String(Math.round(totals.calories)),
        protein: String(Math.round(totals.protein)),
        carbs: String(Math.round(totals.carbs)),
        fat: String(Math.round(totals.fat)),
        confidence,
        notes: String(parsed.notes ?? ""),
        foodItems: resolved.map((item) => ({
          ...item,
          calories: String(item.calories),
          protein: String(item.protein),
          carbs: String(item.carbs),
          fat: String(item.fat),
        })),
        databaseCoverage: coverage,
        nutritionSource: index.source,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      console.error("OpenRouter API error:", error);
      throw new HttpsError(
        "internal",
        "Failed to analyze meal image: " + (error.message || "Unknown error")
      );
    }
  }
);

/**
 * Must agree exactly with normalizeUsername in
 * lib/features/auth/domain/username.dart. This decides which document id a
 * typed username maps to, and a second opinion about that would mean a name
 * resolving to one account at signup and another at login.
 */
function normalizeUsername(raw) {
  return String(raw ?? "")
    .trim()
    .replace(/^@+/, "")
    .trim()
    .toLowerCase();
}

/**
 * signInWithUsername — Callable Cloud Function.
 *
 * Trades a username and password for a Firebase custom token, so the app can
 * offer the same "username, or email" login field Instagram does. Firebase
 * Auth itself only knows email/password; something has to bridge the two, and
 * that bridge cannot live in the client.
 *
 * The reason is the email address. Resolving a username client-side would mean
 * publishing a username→email map to anyone who asked, which is a scraper's
 * dream and a straight privacy breach for every user. So the lookup happens
 * here, under Admin credentials, and the email NEVER crosses back over the
 * wire — the caller gets a token or an error, and learns nothing else.
 *
 * Deliberately not auth-gated: the whole point is that the caller has no
 * session yet.
 *
 * Brute-force protection is Identity Toolkit's, which rate-limits password
 * attempts per IP and returns TOO_MANY_ATTEMPTS_TRY_LATER. A per-username
 * counter was considered and rejected: it would let anyone lock a named
 * account out of its own login by failing at it repeatedly. Enabling App Check
 * on this function is the right next hardening step.
 */
exports.signInWithUsername = onCall(
  { timeoutSeconds: 20, memory: "256MiB" },
  async (request) => {
    const username = normalizeUsername(request.data?.username);
    const password = String(request.data?.password ?? "");

    if (!username || !password) {
      throw new HttpsError(
        "invalid-argument",
        "A username and password are both required."
      );
    }

    const apiKey = webApiKey();
    if (!apiKey) {
      console.error(
        "WEB_API_KEY is not set — username login cannot verify " +
          "passwords. Add it to functions/.env and redeploy."
      );
      throw new HttpsError(
        "failed-precondition",
        "Username sign-in is not configured on this server."
      );
    }

    if (admin.apps.length === 0) {
      admin.initializeApp();
    }

    // One error for every failure below this point. Saying "no such username"
    // separately from "wrong password" would turn this endpoint into an
    // oracle for which accounts exist, and it matches what the email path
    // already tells users, since Firebase collapses the same two cases into
    // invalid-credential.
    const rejectCredentials = () =>
      new HttpsError(
        "unauthenticated",
        "That username and password combination is incorrect."
      );

    const claim = await admin
      .firestore()
      .collection("usernames")
      .doc(username)
      .get();

    if (!claim.exists) throw rejectCredentials();

    const { uid, releaseAt } = claim.data() || {};
    if (!uid) throw rejectCredentials();

    // A vacated name still inside its grace period must not sign anyone in.
    // It is reserved so its previous owner can take it back, not so it keeps
    // working as their login after they have moved on.
    if (releaseAt) throw rejectCredentials();

    let email;
    try {
      email = (await admin.auth().getUser(uid)).email;
    } catch (error) {
      console.error(`Username @${username} points at missing uid ${uid}`, error);
      throw rejectCredentials();
    }

    // An account created through Google or Apple has no password to check.
    if (!email) throw rejectCredentials();

    // Admin SDK has no verify-password call, so the password goes to the same
    // Identity Toolkit endpoint the client SDK uses. Verifying here rather
    // than returning the email is what keeps the address private.
    let verification;
    try {
      verification = await fetch(
        `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${apiKey}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ email, password, returnSecureToken: false }),
        }
      );
    } catch (error) {
      console.error("Identity Toolkit unreachable:", error);
      throw new HttpsError(
        "unavailable",
        "Could not reach the sign-in service. Try again."
      );
    }

    if (!verification.ok) {
      const body = await verification.json().catch(() => ({}));
      const reason = body?.error?.message || "";

      // Passed through rather than flattened: these are about the account or
      // the service, not about whether the credentials were right, and a user
      // who is locked out or throttled needs to be told which.
      if (reason.startsWith("TOO_MANY_ATTEMPTS_TRY_LATER")) {
        throw new HttpsError(
          "resource-exhausted",
          "Too many attempts. Wait a minute and try again."
        );
      }
      if (reason === "USER_DISABLED") {
        throw new HttpsError(
          "permission-denied",
          "This account has been disabled. Contact support for help."
        );
      }
      throw rejectCredentials();
    }

    // The account exists and the password checked out. A custom token hands
    // the client a session for this uid without the email ever leaving here.
    const token = await admin.auth().createCustomToken(uid);
    return { token };
  }
);

/**
 * searchFoods — Callable Cloud Function.
 *
 * Text search over the nutrition table so the app can correct a misidentified
 * item or add one by hand and still get real macros. Returns entries with their
 * per-100 g composition; the client scales them to whatever portion the user
 * enters.
 */
exports.searchFoods = onCall(
  { timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to search foods."
      );
    }

    const query = String(request.data?.query ?? "").trim();
    if (query.length < 2) return { foods: [] };

    const limit = Math.min(Math.max(Number(request.data?.limit) || 20, 1), 50);
    const foods = await nutrition.searchFoods(query, limit);

    return {
      foods: foods.map((food) => ({
        id: food.id,
        name: food.name,
        category: food.category,
        per100g: food.per100g,
        unitGrams: food.unitGrams,
        unitName: food.unitName,
        defaultPortionGrams: food.defaultPortionGrams,
      })),
    };
  }
);

// --- Challenges -------------------------------------------------------------
//
// The challenge engine lives in its own module: it is a self-contained set of
// Firestore triggers and scheduled jobs with nothing in common with the meal
// analyser above, and keeping it here would have made this file the place where
// two unrelated systems are read at once.
// `_internals` is skipped deliberately: it is the module's test seam, and the
// Functions runtime treats every export of this file as something to deploy.
for (const [name, handler] of Object.entries(require("./challenges"))) {
  if (name === "_internals") continue;
  exports[name] = handler;
}
