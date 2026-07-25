const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret, defineString } = require("firebase-functions/params");
const { OpenAI } = require("openai");

// Set with: firebase functions:secrets:set OPENROUTER_API_KEY
const openrouterApiKey = defineSecret("OPENROUTER_API_KEY");

// Any OpenRouter vision-capable model id, e.g. "openai/gpt-4o" or
// "google/gemini-2.5-flash". Override with the VISION_MODEL env var
// (functions/.env) — no code change needed.
const visionModel = defineString("VISION_MODEL", {
  default: "google/gemini-2.5-flash",
});

const RESPONSE_SHAPE = `Return ONLY a valid JSON object with this exact shape:
{
  "name": "<short meal name>",
  "calories": "<estimated total calories as a number string>",
  "protein": "<total grams of protein as a number string>",
  "carbs": "<total grams of carbohydrates as a number string>",
  "fat": "<total grams of fat as a number string>",
  "confidence": "<low | medium | high>",
  "notes": "<one short sentence on portion assumptions, or empty string>",
  "foodItems": [
    {
      "name": "<food item name>",
      "quantity": "<estimated portion with grams, e.g. '1 cup (250g)' or '150g'>",
      "calories": "<calories for this item as a number string>",
      "protein": "<grams of protein as a number string>",
      "carbs": "<grams of carbohydrates as a number string>",
      "fat": "<grams of fat as a number string>"
    }
  ]
}

Return ONLY the JSON object, no markdown formatting, no explanation, no code fences.`;

const PROMPT = `You are a registered dietitian analysing a meal photo for a South African fitness app. Estimate each food item's portion and macros as accurately as possible.

METHOD — follow in order:
1. Identify every distinct food and drink item visible.
2. Estimate each item's portion in grams using visual reference cues: a standard dinner plate is ~26 cm across, a fork is ~19 cm, an adult fist ≈ 1 cup ≈ 250 ml, a matchbox ≈ 30 g of meat/cheese, a golf ball ≈ 2 tablespoons.
3. For each item, compute macros from standard food-composition values per 100 g (SAFOODS / USDA style), scaled to the estimated portion.
4. Adjust for visible cooking method: deep-fried items absorb ~10-15 g oil per 100 g; creamy sauces add fat; grilled/boiled need no adjustment.
5. Totals MUST equal the sum of the per-item values.

SOUTH AFRICAN FOODS — recognise these correctly when present (typical values per 100 g cooked):
- Pap / stywe pap (maize porridge): ~120 kcal, 2.5g P, 26g C, 0.5g F. Krummelpap is denser (~180 kcal).
- Samp and beans (umngqusho): ~130 kcal, 6g P, 22g C, 1.5g F.
- Boerewors, grilled: ~300 kcal, 14g P, 3g C, 26g F.
- Biltong: ~250 kcal, 45g P, 2g C, 7g F.
- Chakalaka: ~80 kcal, 2g P, 10g C, 4g F.
- Morogo / imifino (wild greens): ~45 kcal, 4g P, 6g C, 0.5g F.
- Vetkoek (fried): ~330 kcal, 7g P, 40g C, 16g F each (~80g).
- Bunny chow: count the bread hollow (~200g bread) plus the curry filling separately.
- Kota / sphatlo: itemise the bread, chips, polony/russian, cheese, atchar separately.
- Bobotie: ~180 kcal, 12g P, 10g C, 11g F.
- Boerie roll, gatsby, russians, walkie talkies, amasi (~60 kcal/100ml), mageu, koeksister (~400 kcal each), melktert, rooibos (0 kcal unless milk/sugar visible).

RULES:
- Be realistic, not conservative: restaurant and township portions are typically 1.5-2x textbook servings.
- If an item is partially hidden, estimate what is plausible and mention it in "notes".
- If the image contains NO food or drink at all, return all zeros, name "Not a meal", confidence "low", and say why in "notes".
- Round every number to the nearest whole number.

${RESPONSE_SHAPE}`;

/**
 * analyzeMeal — Callable Cloud Function.
 *
 * Receives { imageUrl } from the client, forwards the image to a
 * vision-capable model via OpenRouter (GPT-4o, Gemini, etc.), and returns
 * structured nutritional data.
 *
 * Returns: { name, calories, protein, carbs, fat, foodItems: [...] }
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
      const response = await openrouter.chat.completions.create({
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
        max_tokens: 800,
        temperature: 0.3,
      });

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

      // --- Validate required fields ---
      const requiredFields = ["name", "calories", "protein", "carbs", "fat"];
      for (const field of requiredFields) {
        if (parsed[field] === undefined || parsed[field] === null) {
          throw new HttpsError(
            "internal",
            `Model response missing required field: ${field}`
          );
        }
      }

      const toNum = (v) => {
        const n = parseFloat(String(v ?? "").replace(/[^\d.-]/g, ""));
        return Number.isFinite(n) && n >= 0 ? n : 0;
      };

      const foodItems = Array.isArray(parsed.foodItems)
        ? parsed.foodItems.map((item) => ({
            name: String(item.name ?? ""),
            quantity: String(item.quantity ?? ""),
            calories: String(Math.round(toNum(item.calories))),
            protein: String(Math.round(toNum(item.protein))),
            carbs: String(Math.round(toNum(item.carbs))),
            fat: String(Math.round(toNum(item.fat))),
          }))
        : [];

      // --- Reconcile totals against the per-item breakdown ---
      // Vision models frequently return totals that don't match the sum of
      // their own items. The itemised estimates are the more deliberate
      // figures, so when items exist, totals are recomputed from them.
      let totals = {
        calories: Math.round(toNum(parsed.calories)),
        protein: Math.round(toNum(parsed.protein)),
        carbs: Math.round(toNum(parsed.carbs)),
        fat: Math.round(toNum(parsed.fat)),
      };
      if (foodItems.length > 0) {
        totals = foodItems.reduce(
          (acc, item) => ({
            calories: acc.calories + toNum(item.calories),
            protein: acc.protein + toNum(item.protein),
            carbs: acc.carbs + toNum(item.carbs),
            fat: acc.fat + toNum(item.fat),
          }),
          { calories: 0, protein: 0, carbs: 0, fat: 0 }
        );
      }

      // Sanity bound: kcal should roughly match 4P + 4C + 9F (Atwater).
      // A wild mismatch means the model hallucinated one side; trust the
      // macro-derived figure in that case.
      const atwater =
        4 * totals.protein + 4 * totals.carbs + 9 * totals.fat;
      if (atwater > 0 && (totals.calories < atwater * 0.5 || totals.calories > atwater * 2)) {
        console.warn(
          `Calorie/macro mismatch: model said ${totals.calories} kcal, ` +
          `Atwater gives ${atwater}. Using Atwater.`
        );
        totals.calories = atwater;
      }

      return {
        name: String(parsed.name),
        calories: String(Math.round(totals.calories)),
        protein: String(Math.round(totals.protein)),
        carbs: String(Math.round(totals.carbs)),
        fat: String(Math.round(totals.fat)),
        confidence: ["low", "medium", "high"].includes(parsed.confidence)
          ? parsed.confidence
          : "medium",
        notes: String(parsed.notes ?? ""),
        foodItems,
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
