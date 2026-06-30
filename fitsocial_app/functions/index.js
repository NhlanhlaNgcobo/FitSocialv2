const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { OpenAI } = require("openai");

// Define the OpenAI API key as a Firebase secret.
// Set it with: firebase functions:secrets:set OPENAI_API_KEY
const openaiApiKey = defineSecret("OPENAI_API_KEY");

/**
 * analyzeMeal — Callable Cloud Function.
 *
 * Receives { imageUrl } from the client, forwards the image to OpenAI
 * GPT-4o Vision, and returns structured nutritional data.
 *
 * Returns: { name, calories, protein, carbs, fat }
 */
exports.analyzeMeal = onCall(
  {
    secrets: [openaiApiKey],
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
    const apiKey = openaiApiKey.value();
    if (!apiKey) {
      throw new HttpsError(
        "failed-precondition",
        "OpenAI API key is not configured. Run: firebase functions:secrets:set OPENAI_API_KEY"
      );
    }

    // --- Call OpenAI Vision ---
    const openai = new OpenAI({ apiKey });

    const prompt = `You are a professional nutritionist AI. Analyze the food in this image and return ONLY a valid JSON object with these exact keys:
{
  "name": "<meal name>",
  "calories": "<estimated total calories as a number string>",
  "protein": "<grams of protein as a number string>",
  "carbs": "<grams of carbohydrates as a number string>",
  "fat": "<grams of fat as a number string>"
}

Be as accurate as possible with your estimates. Return ONLY the JSON object, no markdown formatting, no explanation, no code fences.`;

    try {
      const response = await openai.chat.completions.create({
        model: "gpt-4o",
        messages: [
          {
            role: "user",
            content: [
              { type: "text", text: prompt },
              {
                type: "image_url",
                image_url: { url: imageUrl, detail: "low" },
              },
            ],
          },
        ],
        max_tokens: 300,
        temperature: 0.3,
      });

      const content = response.choices?.[0]?.message?.content;
      if (!content) {
        throw new HttpsError(
          "internal",
          "OpenAI returned an empty response."
        );
      }

      // --- Parse the JSON response ---
      let parsed;
      try {
        // Strip potential markdown code fences just in case
        const cleaned = content
          .replace(/```json\s*/gi, "")
          .replace(/```\s*/g, "")
          .trim();
        parsed = JSON.parse(cleaned);
      } catch (parseError) {
        console.error("Failed to parse OpenAI response:", content);
        throw new HttpsError(
          "internal",
          "OpenAI returned invalid JSON. Raw response: " + content
        );
      }

      // --- Validate required fields ---
      const requiredFields = ["name", "calories", "protein", "carbs", "fat"];
      for (const field of requiredFields) {
        if (parsed[field] === undefined || parsed[field] === null) {
          throw new HttpsError(
            "internal",
            `OpenAI response missing required field: ${field}`
          );
        }
      }

      return {
        name: String(parsed.name),
        calories: String(parsed.calories),
        protein: String(parsed.protein),
        carbs: String(parsed.carbs),
        fat: String(parsed.fat),
      };
    } catch (error) {
      // Re-throw HttpsErrors as-is
      if (error instanceof HttpsError) {
        throw error;
      }

      console.error("OpenAI API error:", error);
      throw new HttpsError(
        "internal",
        "Failed to analyze meal image: " + (error.message || "Unknown error")
      );
    }
  }
);
