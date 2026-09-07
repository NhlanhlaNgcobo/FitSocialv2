# FitSocial Cloud Functions

| Function | Auth | What it does |
| --- | --- | --- |
| `analyzeMeal` | Signed in | Takes a meal photo URL, identifies the foods with a vision model, and returns macros looked up from the nutrition database. |
| `searchFoods` | Signed in | Text search over the nutrition database, for adding or correcting a food by hand. |
| `signInWithUsername` | **None** | Trades a username and password for a Firebase custom token, so the app can offer a "username or email" login field. |

## Why username login needs a function

Firebase Auth only understands email/password, so signing in with a username
means resolving it to an email first. Doing that in the client would require
publishing a username→email map readable by anyone — every user's address, free
for the scraping.

`signInWithUsername` does the lookup under Admin credentials and verifies the
password against Identity Toolkit itself. **The email never crosses back over
the wire.** The caller receives a custom token or an error, and learns nothing
about the account either way — including whether the username exists, since
every failure returns the same message.

It is intentionally callable without a session, which is the one thing that
makes it worth hardening further: turn on **App Check** for this function before
you have real users. Brute-force protection today is Identity Toolkit's own
per-IP rate limiting. A per-username attempt counter was deliberately left out —
it would let anyone lock a named account out of its own login just by failing at
it repeatedly.

## How the meal analyzer works

The vision model and the macros are deliberately separated:

1. **The model identifies and portions.** It returns each food it can see plus an estimated weight in grams. Models are good at recognising food and bad at recalling nutrition tables, so it is never trusted for the macros themselves.
2. **The database supplies the macros.** Each item is matched against a food-composition table and its macros are computed as `per-100 g values × grams ÷ 100`.
3. **Totals are the sum of the items.** Nothing is taken from the model's own totals, so the headline number always equals its own breakdown.

Each item comes back tagged with where its numbers came from:

- `database` — matched the curated table in `data/nutrition_foods.json`
- `usda` — matched USDA FoodData Central (only when a key is configured)
- `estimate` — no match; the model's own guess, shown as such in the app

Lookup order per item: Firestore `nutritionFoods` → bundled JSON → USDA → model estimate.

## Setup

### 1. OpenRouter key (required)

```bash
firebase functions:secrets:set OPENROUTER_API_KEY
```

Paste the key when prompted. It is never committed — `firebase-functions/params` reads it from Secret Manager at runtime.

### 2. Web API key (required for username login)

`functions/.env`:

```
WEB_API_KEY="AIza..."
```

Already set for this project. It is the same value as `web.apiKey` in
`lib/firebase_options.dart` — or Firebase console → Project settings → General →
**Web API Key**. Not a secret: it ships inside every copy of the client app,
which is why it lives in `.env` rather than Secret Manager.

`signInWithUsername` uses it to verify a password against Identity Toolkit;
without it that function returns `failed-precondition` and username login stops
working while email login carries on.

Note the name. The Functions runtime reserves the `FIREBASE_` prefix and will
refuse to load a `.env` containing `FIREBASE_WEB_API_KEY`, failing the deploy
before it starts.

### 3. Choose a vision model (optional)

`functions/.env`:

```
VISION_MODEL="anthropic/claude-sonnet-5"
```

Any vision-capable OpenRouter model id works — they are vendor-prefixed. Changing this needs no code change, which is what makes comparing models on real photos cheap.

The database changed what the model is for: it no longer recalls nutrition values, it only identifies foods and estimates their weight in grams. So this is a pure vision task now, and **portion estimation is the largest remaining source of error** — that, not food naming, is what to judge a model on.

Approximate cost per scan assumes ~3,000 input tokens (photo plus prompt) and ~600 output. Measure your own once a model is live.

Prices below are OpenRouter's standard rates, checked 2026-09-07. Do not copy a
`:batch` price into this table — batch requests queue with no latency guarantee,
which is the wrong trade for a user standing there holding their phone up.

| Model | $/MTok in / out | ~Cost/scan | Trade-off |
| --- | --- | --- | --- |
| `qwen/qwen3-vl-32b-instruct` | 0.10 / 0.42 | ~$0.0006 | Cheapest credible option. Trained for visual grounding, which is the portion problem specifically. Unvalidated here. |
| `openai/gpt-5.6-luna` | 0.20 / 1.20 | ~$0.0013 | Previous default. Cheap, but its gram estimates were never validated against scale weights. |
| `google/gemini-3.6-flash` | 0.75 / 3.75 | ~$0.0045 | Strong on multi-object scenes like a full plate, ~2.5x cheaper than Sonnet. The first thing to try if Sonnet's cost bites. |
| `anthropic/claude-sonnet-5` | 2.00 / 10.00 | ~$0.012 | **The current default.** High-resolution vision (2576px long edge), reliable JSON. Chosen for portion accuracy over cost. |
| `anthropic/claude-opus-5` | 5.00 / 25.00 | ~$0.030 | Best spatial reasoning; gains are largest when the model can crop and re-check its own work, which this single-shot pipeline doesn't do. |

### Comparing models

Photograph 8–10 meals and **weigh each component on a kitchen scale first**, so you have ground truth. Run the set through each candidate and compare estimated grams against actual. Food-identification errors are already visible in the app as `Estimated` badges; gram error is the number that isn't, and it drives every macro.

### Two request constraints

Both in `index.js`, and both deliberately provider-neutral so `VISION_MODEL` can be swapped freely:

- `max_tokens` is 4000. Reasoning models on both OpenAI and Anthropic draw thinking from the same budget as the response, so a tight cap truncates the JSON mid-object — which the code reports as a parse failure, not as truncation.
- `temperature` is not sent. Current Claude models reject non-default sampling parameters with a 400, and omitting it keeps the request valid on every provider.

### 4. Deploy

```bash
firebase deploy --only functions
```

### 5. Back-fill username reservations (required, once)

Run this **before** deploying the username security rules. Those rules refuse
any profile write whose handle the caller does not hold a reservation for, so
an account created before the `usernames` collection existed cannot save its own
profile — not even a bio edit — until it has one.

```bash
npm run backfill:usernames
```

Reports only. Re-run with `--commit` to write:

```bash
node scripts/backfill_usernames.js --commit
```

Accounts already sharing a handle are reported, never silently resolved — the
oldest profile keeps the name and the report names who else needs contacting.

### 6. Firestore rules

The new `meals` and `nutritionFoods` rules ship in `../firestore.rules`:

```bash
firebase deploy --only firestore:rules
```

## The nutrition database

`data/nutrition_foods.json` holds ~150 foods with per-100 g composition, aliases, and typical portion sizes — South African staples (pap, samp and beans, chakalaka, boerewors, vetkoek, kota, amasi, mageu) alongside common global foods, since those are what the vision model actually names on a plate here.

The file is bundled with the deployed function, so **analysis works without seeding anything**.

### Editing foods without redeploying

Seed the table into Firestore, then edit it there:

```bash
npm run seed:nutrition
```

Needs Application Default Credentials with write access:

```bash
gcloud auth application-default login
```

Once the `nutritionFoods` collection is non-empty the function reads from it instead of the bundled file, refreshing at most every 10 minutes per warm instance. Re-running the seed is safe — documents are merged by id.

### Checking the matcher

Matching is the part that breaks quietly: a wrong match produces confidently wrong macros. After editing the food table, run:

```bash
npm run check:nutrition
```

It asserts that the phrasings a vision model realistically returns ("grilled chicken breast", "slap chips", "umngqusho", "tinned pilchards in tomato sauce") land on the right entries, and that non-food text matches nothing. No network or credentials needed.

Matching is alias-based with an IDF-weighted fallback, so the rarest word in a description decides the food — "pilchards in tomato sauce" resolves to pilchards, not ketchup. Anything scoring below the threshold falls through to the model's estimate rather than guessing.

### Adding a food

Append to `data/nutrition_foods.json`:

```json
{
  "id": "unique-kebab-id",
  "name": "Display name",
  "aliases": ["what a vision model would call it", "regional name"],
  "category": "protein",
  "per100g": { "calories": 165, "protein": 31, "carbs": 0, "fat": 3.6 },
  "unitGrams": 50,
  "unitName": "slice",
  "defaultPortionGrams": 150
}
```

`per100g` values are for the food **as eaten** (cooked, if it is cooked). Aliases matter more than the name — they are what the model's wording is matched against. `unitGrams` is optional and only for countable items.

Add a case to `scripts/check_nutrition_matching.js` for anything with tricky phrasing.

### USDA fallback (optional)

For foods outside the local table, add a free key from <https://fdc.nal.usda.gov/api-key-signup> to `functions/.env`:

```
FDC_API_KEY="your-key"
```

Without it nothing is called and unmatched items simply stay estimates. It is read from the environment rather than declared as a secret so a missing key can never fail a deploy.
