/**
 * Weekly Insights (Build 11, F2): a short AI-written read of somebody's last
 * week, built from their stats, goals and meal logging.
 *
 *   users/{uid}/insights/{weekId}   one per finished week. Server-written,
 *                                   owner-read (firestore.rules).
 *   insightFeedback/{uid}_{weekId}  the owner's rating of it. Client-written.
 *
 * What the model sees is the whole privacy design. [buildPayload] hands it
 * aggregates and nothing else: no uid, name, email, photo, place, or anything
 * the user typed. Meal calories are read to decide one thing on the server
 * (see [lowIntakeSignal]) and are never put in the payload, so the model has
 * no number to build a calorie target out of even if it wanted to.
 *
 * Cost. One generation per user per finished week, cached in the insight
 * document and keyed on uid + weekId + PROMPT_VERSION: a second request for the
 * same week returns what is stored. A week with too little in it never reaches
 * the model at all. Regenerating on demand is capped per user per day. The
 * f2_weekly_insights flag is the kill switch: off, nothing here calls out.
 *
 * Safety. The model's answer must parse, match the output contract, and pass
 * [forbiddenIn] -- no diet targets, restriction, medical claims or moralising
 * food words. Anything that fails is retried a bounded number of times and
 * otherwise stored as `failed`, which the app shows as nothing at all. An
 * unchecked answer never reaches a phone.
 *
 * Neither prompts nor answers are logged: both are about somebody's week.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret, defineString } = require("firebase-functions/params");
const admin = require("firebase-admin");
const OpenAI = require("openai");

const {
  db,
  dayKeyOf,
  dayRange,
  activityInDay,
  offsetFor,
} = require("./challenges")._internals;
const periods = require("./period_keys");
const remoteConfig = require("./remote_config");
const stats = require("./stats")._internals;

const FLAG = "f2_weekly_insights";

/**
 * Bumped whenever the prompt or the output contract changes. Part of the
 * cache key, so a new version regenerates a week once rather than serving an
 * answer written to the old rules.
 */
const PROMPT_VERSION = "2026-10-02.1";

// The same OpenRouter key the meal analyzer uses.
const openrouterApiKey = defineSecret("OPENROUTER_API_KEY");

// The cheapest model that writes this well, by Bear's choice. Changed in
// functions/.env (INSIGHTS_MODEL) without a code change.
const insightsModel = defineString("INSIGHTS_MODEL", {
  default: "anthropic/claude-haiku-4.5",
});

/** Fewer days with anything logged than this, and there is nothing to say. */
const MIN_DAYS_WITH_DATA = 2;

/** Days with data below this make a week `partial` rather than `full`. */
const FULL_WEEK_DAYS = 5;

/** Model calls per generation, the first included. */
const MAX_ATTEMPTS = 3;

/** On-demand regenerations one person may ask for in a day. */
const MAX_REGENERATIONS_PER_DAY = 2;

/** A claim older than this is taken to have died with its instance. */
const CLAIM_STALE_MS = 3 * 60 * 1000;

const MODEL_TIMEOUT_MS = 30 * 1000;

/** How many people the weekly job writes for at once. */
const BATCH_CONCURRENCY = 5;

// --- Pure: what the model is told ------------------------------------------

function count(value) {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.round(n) : 0;
}

/** The figures of one week the model may see. */
function weekFigures(week) {
  if (!week) return null;
  const daysWithSteps = count(week.daysWithSteps);
  return {
    daysWithData: count(week.daysWithData),
    activeDays: count(week.activeDays),
    sessions: count(week.sessions),
    activeMinutes: count(week.activeMinutes),
    steps: count(week.steps),
    averageDailySteps:
      daysWithSteps > 0 ? Math.round(count(week.steps) / daysWithSteps) : null,
    daysWithSteps,
    longestStreakDays: count(week.longestStreak),
    averageHeartRate: week.avgHeartRate == null ? null : count(week.avgHeartRate),
    mealsLogged: count(week.meals),
  };
}

const GOAL_METRICS = new Set([
  "steps",
  "active_minutes",
  "workouts",
  "meals_logged",
  "streak",
]);

/**
 * Everything the model is told about somebody's week. Aggregates only, by
 * construction: each field is copied out by name, so nothing a stats or goal
 * document gains later reaches the model without being added here.
 */
function buildPayload({ weekId, week, previousWeek, goals = [], mealDays = 0 }) {
  const figures = weekFigures(week);
  return {
    weekId,
    daysInWeek: 7,
    thisWeek: figures,
    daysWithMealsLogged: count(mealDays),
    previousWeek: weekFigures(previousWeek),
    goals: goals
      .filter((goal) => GOAL_METRICS.has(goal.metric))
      .slice(0, 5)
      .map((goal) => ({
        metric: goal.metric,
        period: goal.period === "weekly" ? "weekly" : "longer",
        target: count(goal.target),
        progress: count(goal.progress),
        reached: count(goal.progress) >= count(goal.target) && count(goal.target) > 0,
      })),
  };
}

/** `full`, `partial` or `insufficient`, decided here rather than by the model. */
function dataQualityOf(week) {
  const days = count(week?.daysWithData);
  if (days < MIN_DAYS_WITH_DATA) return "insufficient";
  return days >= FULL_WEEK_DAYS ? "full" : "partial";
}

/**
 * Whether the week's logging looks like very low intake, which puts a gentle
 * "talk to a professional" note on the insight instead of anything about food.
 *
 * Deliberately narrow, because a false positive on someone who simply forgot
 * to log dinner is its own harm: it needs at least four days that each have
 * two or more meals logged, and an average under 1,000 kcal on those days.
 * Days with one meal logged are read as incomplete logging, not as eating
 * once. The threshold and the wording the app shows are Bear's to sign off.
 */
const LOW_INTAKE_MIN_DAYS = 4;
const LOW_INTAKE_KCAL = 1000;

function lowIntakeSignal(mealsByDay) {
  const fullDays = Object.values(mealsByDay).filter((day) => day.meals >= 2);
  if (fullDays.length < LOW_INTAKE_MIN_DAYS) return false;
  const average =
    fullDays.reduce((sum, day) => sum + day.calories, 0) / fullDays.length;
  return average > 0 && average < LOW_INTAKE_KCAL;
}

const SYSTEM_PROMPT = `You write a short weekly check-in for a user of FitSocial, a South African fitness app. You are given aggregate numbers about their last week. Write in plain, warm, everyday English, as a supportive friend who knows fitness, speaking to them as "you".

RULES (all of them, always):
- Celebrate consistency and effort. Notice what they did, not what they failed to do.
- Never give medical advice, diagnoses, or claims about health conditions or treatment.
- Never mention calories, kilojoules, weight, body size, BMI, or losing or gaining weight.
- Never suggest eating less, skipping meals, fasting, restricting food, or "burning off" food.
- Never call food or eating good, bad, clean, junk, or a cheat. Do not moralise about food.
- Never invent numbers or facts. Use only what is in the data. If something is missing (null), do not mention it.
- Heart rate, if present, is context only: do not interpret it medically.
- Meals: you may mention how consistently they logged meals. Nothing about what or how much they ate.
- The suggestion is one small, concrete, achievable thing for next week about movement, consistency, rest, or logging.
- Use metric units and South African spelling.

Return ONLY a JSON object, no markdown or code fences, with exactly this shape:
{
  "headline": "<at most 80 characters>",
  "summary": "<2 to 4 sentences>",
  "wins": ["<short win>", "... up to 3"],
  "trends": [{"metric": "<steps | active_minutes | sessions | streak | meals_logged | heart_rate>", "direction": "<up | down | flat>", "note": "<short note>"}],
  "suggestion": "<one concrete next step>"
}
Trends compare this week with previousWeek. Leave "trends" empty when previousWeek is null.`;

function userPrompt(payload, dataQuality) {
  const partial =
    dataQuality === "partial"
      ? "\nOnly part of the week has data. Say so lightly, and do not treat missing days as inactivity."
      : "";
  return `Here is the week, as JSON:\n${JSON.stringify(payload)}${partial}`;
}

// --- Pure: checking what came back -----------------------------------------

const TREND_METRICS = new Set([
  "steps",
  "active_minutes",
  "sessions",
  "streak",
  "meals_logged",
  "heart_rate",
]);
const DIRECTIONS = new Set(["up", "down", "flat"]);

/**
 * Words and phrases no insight may contain. Matched case-insensitively on
 * word boundaries across every string in the answer. Broad on purpose: a
 * false rejection costs one retry; a false pass reaches somebody's phone.
 */
const FORBIDDEN = [
  /\bcalori/i,
  /\bkcal\b/i,
  /\bkilojoule/i,
  /\bkj\b/i,
  /\bweight\s*loss\b/i,
  /\blos(e|ing)\s+(some\s+)?weight\b/i,
  /\bgain(ing)?\s+weight\b/i,
  /\bweigh\b/i,
  /\bbmi\b/i,
  /\bbody\s*fat\b/i,
  /\bdeficit\b/i,
  /\bfast(ing|ed)\b/i,
  /\bskip(ped|ping|s)?\s+(a\s+|your\s+)?(meals?|breakfast|lunch|dinner|supper)\b/i,
  /\beat(ing)?\s+less\b/i,
  /\bcut(ting)?\s+(back|down)\b/i,
  /\brestrict/i,
  /\bburn(ed|t|s|ing)?\s+((it|that|them)\s+)?off\b/i,
  /\bcheat\b/i,
  /\bjunk\b/i,
  /\b(good|bad|clean|guilty)\s+(food|foods|eating|meal|meals)\b/i,
  /\bguilt/i,
  /\bdiagnos/i,
  /\bdisorder\b/i,
  /\bdisease\b/i,
  /\bprescri/i,
  /\bmedication\b/i,
  /\bdoctor\b/i,
  /\bpurg/i,
  /\bslim\b/i,
  /\bskinny\b/i,
  /\bfat\b/i,
];

function forbiddenIn(text) {
  return FORBIDDEN.some((pattern) => pattern.test(text));
}

function cleanString(value, maxLength) {
  if (typeof value !== "string") return null;
  const text = value.replace(/\s+/g, " ").trim();
  if (!text || text.length > maxLength) return null;
  return text;
}

function sentenceCount(text) {
  return text.split(/(?<=[.!?])\s+/).filter((s) => s.trim()).length;
}

/**
 * The model's raw reply as a valid insight, or null. Strict: one bad field
 * fails the whole answer, because a half-checked insight is an unchecked one.
 */
function parseInsight(raw) {
  if (typeof raw !== "string") return null;
  const unfenced = raw
    .trim()
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/, "");
  let data;
  try {
    data = JSON.parse(unfenced);
  } catch {
    return null;
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) return null;

  const headline = cleanString(data.headline, 80);
  const summary = cleanString(data.summary, 600);
  const suggestion = cleanString(data.suggestion, 220);
  if (!headline || !summary || !suggestion) return null;
  const sentences = sentenceCount(summary);
  if (sentences < 1 || sentences > 4) return null;

  if (!Array.isArray(data.wins) || data.wins.length > 3) return null;
  const wins = data.wins.map((win) => cleanString(win, 140));
  if (wins.some((win) => win == null)) return null;

  const rawTrends = data.trends ?? [];
  if (!Array.isArray(rawTrends) || rawTrends.length > 4) return null;
  const trends = [];
  for (const trend of rawTrends) {
    if (!trend || typeof trend !== "object") return null;
    const note = cleanString(trend.note, 140);
    if (
      !TREND_METRICS.has(trend.metric) ||
      !DIRECTIONS.has(trend.direction) ||
      !note
    ) {
      return null;
    }
    trends.push({ metric: trend.metric, direction: trend.direction, note });
  }

  const insight = { headline, summary, wins, trends, suggestion };
  const allText = [
    headline,
    summary,
    suggestion,
    ...wins,
    ...trends.map((t) => t.note),
  ].join("\n");
  if (forbiddenIn(allText)) return null;
  return insight;
}

// --- The model -------------------------------------------------------------

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Asks the model until it returns a valid insight, up to [MAX_ATTEMPTS] calls
 * with exponential backoff between them. Returns `{ insight, attempts }`,
 * with a null insight when every attempt failed.
 */
async function generate(payload, dataQuality, { complete, backoffMs = 1000 }) {
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      const reply = await complete(SYSTEM_PROMPT, userPrompt(payload, dataQuality));
      const insight = parseInsight(reply);
      if (insight) return { insight, attempts: attempt };
      console.warn("weekly insight failed validation", { attempt });
    } catch (error) {
      // The message only: an API error can echo the request back.
      console.warn("weekly insight call failed", {
        attempt,
        status: error?.status,
        code: error?.code,
      });
    }
    if (attempt < MAX_ATTEMPTS) await sleep(backoffMs * 2 ** (attempt - 1));
  }
  return { insight: null, attempts: MAX_ATTEMPTS };
}

/** The real model call, through OpenRouter. */
function openRouterCompletion() {
  const client = new OpenAI({
    apiKey: openrouterApiKey.value(),
    baseURL: "https://openrouter.ai/api/v1",
    timeout: MODEL_TIMEOUT_MS,
    maxRetries: 0,
    defaultHeaders: {
      "HTTP-Referer": "https://fitsocialv2.web.app",
      "X-Title": "FitSocial",
    },
  });
  return async (system, user) => {
    const response = await client.chat.completions.create({
      model: insightsModel.value(),
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
      max_tokens: 1200,
    });
    return response.choices?.[0]?.message?.content ?? "";
  };
}

// --- Firestore --------------------------------------------------------------

const serverTimestamp = () => admin.firestore.FieldValue.serverTimestamp();

const insightRef = (uid, weekId) =>
  db().collection("users").doc(uid).collection("insights").doc(weekId);

/** The week before the one [now] falls in, on the user's own calendar. */
function lastFinishedWeekId(now, offsetMinutes) {
  return periods.previousWeekId(periods.isoWeekIdOf(dayKeyOf(now, offsetMinutes)));
}

async function readGoals(uid) {
  const snap = await db()
    .collection("users")
    .doc(uid)
    .collection("goals")
    .where("status", "==", "active")
    .get();
  return snap.docs.map((doc) => doc.data());
}

/** Meals and their calories per day of [weekId], for [lowIntakeSignal]. */
async function readMealDays(uid, weekId, offsetMinutes) {
  const dayKeys = periods.weekDayKeys(weekId);
  const { start } = dayRange(dayKeys[0], offsetMinutes);
  const { end } = dayRange(dayKeys[dayKeys.length - 1], offsetMinutes);
  const docs = await activityInDay(
    "meals",
    uid,
    ["loggedAt", "createdAt"],
    start,
    end
  );
  const byDay = {};
  for (const doc of docs) {
    const data = doc.data();
    const raw = data.loggedAt ?? data.createdAt;
    const at = typeof raw?.toDate === "function" ? raw.toDate() : raw;
    if (!(at instanceof Date)) continue;
    const key = dayKeyOf(at, offsetMinutes);
    const day = (byDay[key] ??= { meals: 0, calories: 0 });
    day.meals += 1;
    day.calories += count(String(data.calories ?? "").replace(/[^\d.]/g, ""));
  }
  return byDay;
}

/**
 * Takes the right to generate [weekId] for [uid], inside a transaction, so the
 * weekly job and a tap on "regenerate" cannot both pay for the same week.
 *
 * Returns `{ claimed: true }` or `{ claimed: false, existing }`. A stored
 * insight on the current prompt version is kept unless [regenerate]; a claim
 * still being worked on is respected until it goes stale.
 */
async function claim(uid, weekId, { regenerate = false, todayKey, now = new Date() }) {
  const ref = insightRef(uid, weekId);
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const existing = snap.exists ? snap.data() : null;

    if (existing?.status === "generating") {
      const claimedAt = existing.claimedAt?.toDate?.() ?? existing.claimedAt;
      const age = claimedAt instanceof Date ? now - claimedAt : Infinity;
      if (age < CLAIM_STALE_MS) return { claimed: false, existing };
    }

    const current =
      existing &&
      existing.status !== "generating" &&
      existing.promptVersion === PROMPT_VERSION;
    if (current && !regenerate) return { claimed: false, existing };

    let regenerationDay = existing?.regenerationDay ?? null;
    let regenerationCount = existing?.regenerationCount ?? 0;
    if (current && regenerate) {
      if (regenerationDay !== todayKey) {
        regenerationDay = todayKey;
        regenerationCount = 0;
      }
      if (regenerationCount >= MAX_REGENERATIONS_PER_DAY) {
        return { claimed: false, existing, quotaReached: true };
      }
      regenerationCount += 1;
    }

    tx.set(
      ref,
      {
        weekId,
        status: "generating",
        claimedAt: now,
        regenerationDay,
        regenerationCount,
      },
      { merge: true }
    );
    return { claimed: true };
  });
}

/**
 * Builds and stores [uid]'s insight for [weekId]. Assumes the flag is on.
 * Returns the stored status.
 */
async function generateFor(uid, weekId, { complete, regenerate = false, now = new Date(), backoffMs } = {}) {
  const offset = await offsetFor(uid);
  const todayKey = dayKeyOf(now, offset);
  const claimed = await claim(uid, weekId, { regenerate, todayKey, now });
  if (!claimed.claimed) {
    return claimed.quotaReached ? "quota" : claimed.existing?.status ?? "none";
  }

  const ref = insightRef(uid, weekId);
  const base = {
    weekId,
    promptVersion: PROMPT_VERSION,
    generatedAt: serverTimestamp(),
    claimedAt: admin.firestore.FieldValue.delete(),
  };

  try {
    const [weekSnap, previousSnap, goals, mealDays] = await Promise.all([
      stats.weeklyRef(uid, weekId).get(),
      stats.weeklyRef(uid, periods.previousWeekId(weekId)).get(),
      readGoals(uid),
      readMealDays(uid, weekId, offset),
    ]);
    const week = weekSnap.exists ? weekSnap.data() : null;
    const dataQuality = dataQualityOf(week);
    const wellbeingNote = lowIntakeSignal(mealDays);

    if (dataQuality === "insufficient") {
      // Nothing to say, and nothing spent finding that out.
      await ref.set(
        { ...base, status: "insufficient", dataQuality, wellbeingNote: false, model: null, insight: null },
        { merge: true }
      );
      return "insufficient";
    }

    const payload = buildPayload({
      weekId,
      week,
      previousWeek: previousSnap.exists ? previousSnap.data() : null,
      goals,
      mealDays: Object.keys(mealDays).length,
    });
    const { insight, attempts } = await generate(payload, dataQuality, {
      complete: complete ?? openRouterCompletion(),
      backoffMs,
    });

    await ref.set(
      {
        ...base,
        status: insight ? "ready" : "failed",
        model: insightsModel.value(),
        dataQuality,
        wellbeingNote,
        attempts,
        insight: insight ? { weekId, ...insight, dataQuality } : null,
      },
      { merge: true }
    );
    return insight ? "ready" : "failed";
  } catch (error) {
    // Leave the week claimable again rather than stuck "generating".
    await ref.set({ ...base, status: "failed", insight: null }, { merge: true });
    throw error;
  }
}

/** Whether [uid] turned Weekly Insights off. */
async function hasHidden(uid) {
  const user = await db().collection("users").doc(uid).get();
  return user.get("insightsHidden") === true;
}

/**
 * Last week's insight for everybody who had data in it and has not hidden the
 * feature. Bounded concurrency; one person's failure is logged and skipped.
 */
async function generateWeek(weekId, { complete, backoffMs } = {}) {
  const snap = await db().collection("weeklyStats").where("weekId", "==", weekId).get();
  const uids = snap.docs
    .map((doc) => doc.data())
    .filter((week) => dataQualityOf(week) !== "insufficient")
    .map((week) => week.userId)
    .filter(Boolean);

  const results = { ready: 0, skipped: 0, failed: 0 };
  for (let i = 0; i < uids.length; i += BATCH_CONCURRENCY) {
    await Promise.all(
      uids.slice(i, i + BATCH_CONCURRENCY).map(async (uid) => {
        try {
          if (await hasHidden(uid)) {
            results.skipped += 1;
            return;
          }
          const status = await generateFor(uid, weekId, { complete, backoffMs });
          if (status === "ready") results.ready += 1;
          else if (status === "failed") results.failed += 1;
          else results.skipped += 1;
        } catch (error) {
          results.failed += 1;
          console.error("weekly insight failed for a user", { message: error?.message });
        }
      })
    );
  }
  return results;
}

// --- Exports ----------------------------------------------------------------

/**
 * Monday 05:00 in South Africa: last week is over everywhere the app is used,
 * and the insight is waiting when people wake up. us-central1 because Cloud
 * Scheduler does not exist in africa-south1.
 */
exports.generateWeeklyInsights = onSchedule(
  {
    schedule: "0 5 * * 1",
    timeZone: "Africa/Johannesburg",
    region: "us-central1",
    timeoutSeconds: 540,
    secrets: [openrouterApiKey],
  },
  async () => {
    if (!(await remoteConfig.isOn(FLAG))) return;
    // South Africa's offset: the job runs on the SA calendar.
    const weekId = lastFinishedWeekId(new Date(), 120);
    const results = await generateWeek(weekId);
    console.log("weekly insights", { weekId, ...results });
  }
);

/**
 * The app asking for last week's insight: on first open after the flag goes
 * on, for somebody the job skipped, or with `regenerate: true` (capped).
 * Returns `{ weekId, status }`; the insight itself is read from Firestore.
 */
exports.requestWeeklyInsight = onCall(
  { secrets: [openrouterApiKey], timeoutSeconds: 120 },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in to see your Weekly Insights.");
    }
    if (!(await remoteConfig.isOn(FLAG))) {
      throw new HttpsError("failed-precondition", "Weekly Insights are switched off.");
    }
    if (await hasHidden(uid)) {
      throw new HttpsError("failed-precondition", "Weekly Insights are hidden.");
    }
    const weekId = lastFinishedWeekId(new Date(), await offsetFor(uid));
    const status = await generateFor(uid, weekId, {
      regenerate: request.data?.regenerate === true,
    });
    if (status === "quota") {
      throw new HttpsError(
        "resource-exhausted",
        "You've refreshed this week's insight as often as you can today. Try again tomorrow."
      );
    }
    return { weekId, status };
  }
);

exports._internals = {
  buildPayload,
  dataQualityOf,
  lowIntakeSignal,
  parseInsight,
  forbiddenIn,
  generate,
  generateFor,
  generateWeek,
  lastFinishedWeekId,
  insightRef,
  SYSTEM_PROMPT,
  PROMPT_VERSION,
  MAX_ATTEMPTS,
  MAX_REGENERATIONS_PER_DAY,
};
