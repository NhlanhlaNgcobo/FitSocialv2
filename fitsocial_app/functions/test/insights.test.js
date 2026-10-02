/**
 * Weekly Insights: what the model is told, what it is allowed to say back,
 * and the caching that keeps it to one call per person per week.
 *
 * The payload test is the privacy guarantee -- "only these keys" is asserted,
 * not described. The validator runs against adversarial fixtures: replies that
 * are well-formed JSON but say something an insight must never say. The
 * Firestore half runs against the in-memory admin stand-in with the model
 * replaced by a stub, so no test here spends money.
 */

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const { createFakeAdmin } = require("./fake_admin");

const FUNCTIONS_DIR = path.join(__dirname, "..");
const ME = "uid_me";

/** Loads insights.js against a fake firebase-admin. See leaderboard.test.js. */
function loadWithFakeAdmin(seed) {
  const adminPath = require.resolve("firebase-admin", { paths: [FUNCTIONS_DIR] });
  const modulePaths = [
    require.resolve("../challenges.js"),
    require.resolve("../stats.js"),
    require.resolve("../remote_config.js"),
    require.resolve("../insights.js"),
  ];
  const fake = createFakeAdmin(seed);
  const previousAdmin = require.cache[adminPath];
  const previousModules = modulePaths.map((p) => require.cache[p]);

  require.cache[adminPath] = {
    id: adminPath,
    filename: adminPath,
    loaded: true,
    exports: fake.admin,
  };
  for (const p of modulePaths) delete require.cache[p];
  const module = require(require.resolve("../insights.js"));

  if (previousAdmin) require.cache[adminPath] = previousAdmin;
  else delete require.cache[adminPath];
  modulePaths.forEach((p, i) => {
    if (previousModules[i]) require.cache[p] = previousModules[i];
    else delete require.cache[p];
  });
  return { ...fake, internals: module._internals };
}

const {
  buildPayload,
  dataQualityOf,
  lowIntakeSignal,
  parseInsight,
  lastFinishedWeekId,
  PROMPT_VERSION,
} = require("../insights")._internals;

/** A week's stats as stats.js writes them, private fields included. */
function weekStats(overrides = {}) {
  return {
    userId: ME,
    weekId: "2026-W39",
    steps: 61000,
    manualSteps: 9000,
    rankableSteps: 52000,
    activeMinutes: 320,
    rankableActiveMinutes: 320,
    sessions: 5,
    meals: 14,
    longestStreak: 4,
    activeDays: 4,
    daysWithData: 6,
    daysWithSteps: 6,
    flaggedDays: 0,
    avgHeartRate: 74,
    maxHeartRate: 171,
    activeDayKeys: ["2026-09-21", "2026-09-22"],
    byDay: { steps: [9000, 11000, 8000, 12000, 7000, 5000, null] },
    ...overrides,
  };
}

const GOOD_REPLY = JSON.stringify({
  headline: "Five sessions and a four-day streak",
  summary:
    "You moved on four days this week and fitted in five sessions. Your steps held steady too.",
  wins: ["Five sessions", "A four-day streak"],
  trends: [{ metric: "sessions", direction: "up", note: "One more than last week." }],
  suggestion: "Book one short walk on Sunday to keep the streak going.",
});

// --- The payload ------------------------------------------------------------

test("the payload carries aggregates only, field by field", () => {
  const payload = buildPayload({
    weekId: "2026-W39",
    week: weekStats(),
    previousWeek: weekStats({ sessions: 4 }),
    goals: [
      { metric: "workouts", period: "weekly", target: 4, progress: 5, userId: ME, title: "x" },
      { metric: "weight", period: "weekly", target: 70, progress: 72 },
    ],
    mealDays: 6,
  });

  assert.deepStrictEqual(Object.keys(payload).sort(), [
    "daysInWeek",
    "daysWithMealsLogged",
    "goals",
    "previousWeek",
    "thisWeek",
    "weekId",
  ]);
  assert.deepStrictEqual(Object.keys(payload.thisWeek).sort(), [
    "activeDays",
    "activeMinutes",
    "averageDailySteps",
    "averageHeartRate",
    "daysWithData",
    "daysWithSteps",
    "longestStreakDays",
    "mealsLogged",
    "sessions",
    "steps",
  ]);
  // An unknown goal metric never reaches the model, and goals carry no id.
  assert.deepStrictEqual(payload.goals, [
    { metric: "workouts", period: "weekly", target: 4, progress: 5, reached: true },
  ]);

  const text = JSON.stringify(payload);
  for (const leak of [ME, "userId", "activeDayKeys", "byDay", "manualSteps", "maxHeartRate", "calories"]) {
    assert.equal(text.includes(leak), false, `payload must not contain ${leak}`);
  }
});

test("data quality is decided from days with data", () => {
  assert.equal(dataQualityOf(null), "insufficient");
  assert.equal(dataQualityOf(weekStats({ daysWithData: 1 })), "insufficient");
  assert.equal(dataQualityOf(weekStats({ daysWithData: 3 })), "partial");
  assert.equal(dataQualityOf(weekStats({ daysWithData: 5 })), "full");
});

test("the low-intake note needs four fully logged days, all low", () => {
  const day = (meals, calories) => ({ meals, calories });
  assert.equal(
    lowIntakeSignal({ a: day(3, 700), b: day(2, 800), c: day(3, 900), d: day(2, 600) }),
    true
  );
  // Three full days is not enough to say anything.
  assert.equal(lowIntakeSignal({ a: day(3, 700), b: day(2, 800), c: day(3, 900) }), false);
  // One meal logged a day reads as incomplete logging, not as eating once.
  assert.equal(
    lowIntakeSignal({ a: day(1, 400), b: day(1, 400), c: day(1, 400), d: day(1, 400) }),
    false
  );
  assert.equal(
    lowIntakeSignal({ a: day(3, 1900), b: day(2, 2100), c: day(3, 1700), d: day(2, 2000) }),
    false
  );
});

test("the last finished week is read on the user's own calendar", () => {
  // Sunday 22:30 UTC is already Monday in South Africa.
  const now = new Date("2026-10-04T22:30:00Z");
  assert.equal(lastFinishedWeekId(now, 120), "2026-W40");
  assert.equal(lastFinishedWeekId(now, 0), "2026-W39");
});

// --- The validator ----------------------------------------------------------

test("a well-formed reply parses, code fences and all", () => {
  const insight = parseInsight("```json\n" + GOOD_REPLY + "\n```");
  assert.equal(insight.headline, "Five sessions and a four-day streak");
  assert.equal(insight.trends[0].direction, "up");
});

test("malformed replies are rejected", () => {
  const base = JSON.parse(GOOD_REPLY);
  const bad = [
    "not json",
    "[]",
    JSON.stringify({ ...base, headline: "x".repeat(81) }),
    JSON.stringify({ ...base, summary: "" }),
    JSON.stringify({ ...base, summary: "One. Two. Three. Four. Five." }),
    JSON.stringify({ ...base, wins: ["a", "b", "c", "d"] }),
    JSON.stringify({ ...base, wins: "a win" }),
    JSON.stringify({ ...base, trends: [{ metric: "weight", direction: "down", note: "n" }] }),
    JSON.stringify({ ...base, trends: [{ metric: "steps", direction: "sideways", note: "n" }] }),
    JSON.stringify({ ...base, suggestion: undefined }),
  ];
  for (const reply of bad) assert.equal(parseInsight(reply), null, reply);
});

test("adversarial replies that break the safety rules never pass", () => {
  const base = JSON.parse(GOOD_REPLY);
  const unsafe = [
    { suggestion: "Aim for 1,500 calories a day next week." },
    { suggestion: "Try cutting back on dinner portions." },
    { suggestion: "Eat less after 7pm." },
    { summary: "Great week! Intermittent fasting could help you more." },
    { wins: ["You burned off Saturday's pizza"] },
    { wins: ["Only one cheat meal"] },
    { summary: "You ate a lot of junk food this week." },
    { summary: "Mostly good food choices this week." },
    { suggestion: "Keep going and you will lose weight fast." },
    { summary: "Your heart rate suggests a heart disease, please check." },
    { summary: "You might want a diagnosis for that resting heart rate." },
    { suggestion: "Skip breakfast to boost your results." },
    { summary: "Restricting carbs is working for you." },
    { suggestion: "Check your BMI on Monday." },
  ];
  for (const override of unsafe) {
    const reply = JSON.stringify({ ...base, ...override });
    assert.equal(parseInsight(reply), null, JSON.stringify(override));
  }
});

// --- Generation and caching -------------------------------------------------

const WEEK = "2026-W39";

function seed(overrides = {}) {
  return {
    [`users/${ME}`]: { utcOffsetMinutes: 120 },
    [`weeklyStats/${ME}_${WEEK}`]: weekStats(),
    [`weeklyStats/${ME}_2026-W38`]: weekStats({ weekId: "2026-W38", sessions: 4 }),
    ...overrides,
  };
}

function stubModel(replies) {
  const calls = [];
  const complete = async (system, user) => {
    calls.push({ system, user });
    const reply = replies[Math.min(calls.length - 1, replies.length - 1)];
    if (reply instanceof Error) throw reply;
    return reply;
  };
  return { complete, calls };
}

const NOW = new Date("2026-10-01T08:00:00Z");

test("a valid reply is stored as ready, with its version and quality", async () => {
  const { internals, store } = loadWithFakeAdmin(seed());
  const model = stubModel([GOOD_REPLY]);

  const status = await internals.generateFor(ME, WEEK, { complete: model.complete, now: NOW, backoffMs: 0 });

  assert.equal(status, "ready");
  const doc = store.get(`users/${ME}/insights/${WEEK}`);
  assert.equal(doc.status, "ready");
  assert.equal(doc.promptVersion, PROMPT_VERSION);
  assert.equal(doc.insight.dataQuality, "full");
  assert.equal(doc.insight.weekId, WEEK);
  assert.equal(doc.wellbeingNote, false);
  assert.equal("claimedAt" in doc, false);
  // The model saw aggregates, never the uid.
  assert.equal(model.calls[0].user.includes(ME), false);
});

test("a stored week is not generated twice", async () => {
  const { internals } = loadWithFakeAdmin(seed());
  const model = stubModel([GOOD_REPLY]);
  await internals.generateFor(ME, WEEK, { complete: model.complete, now: NOW, backoffMs: 0 });
  const second = await internals.generateFor(ME, WEEK, { complete: model.complete, now: NOW, backoffMs: 0 });
  assert.equal(second, "ready");
  assert.equal(model.calls.length, 1);
});

test("invalid replies are retried, then stored as failed with no insight", async () => {
  const { internals, store } = loadWithFakeAdmin(seed());
  const unsafe = JSON.stringify({ ...JSON.parse(GOOD_REPLY), suggestion: "Eat less." });
  const model = stubModel(["nope", new Error("timeout"), unsafe]);

  const status = await internals.generateFor(ME, WEEK, { complete: model.complete, now: NOW, backoffMs: 0 });

  assert.equal(status, "failed");
  assert.equal(model.calls.length, internals.MAX_ATTEMPTS);
  const doc = store.get(`users/${ME}/insights/${WEEK}`);
  assert.equal(doc.status, "failed");
  assert.equal(doc.insight, null);
});

test("a retry that comes good is kept", async () => {
  const { internals } = loadWithFakeAdmin(seed());
  const model = stubModel(["nope", GOOD_REPLY]);
  const status = await internals.generateFor(ME, WEEK, { complete: model.complete, now: NOW, backoffMs: 0 });
  assert.equal(status, "ready");
  assert.equal(model.calls.length, 2);
});

test("a week with too little data never calls the model", async () => {
  const { internals, store } = loadWithFakeAdmin(
    seed({ [`weeklyStats/${ME}_${WEEK}`]: weekStats({ daysWithData: 1 }) })
  );
  const model = stubModel([GOOD_REPLY]);
  const status = await internals.generateFor(ME, WEEK, { complete: model.complete, now: NOW, backoffMs: 0 });
  assert.equal(status, "insufficient");
  assert.equal(model.calls.length, 0);
  assert.equal(store.get(`users/${ME}/insights/${WEEK}`).insight, null);
});

test("regenerating is capped per day", async () => {
  const { internals } = loadWithFakeAdmin(seed());
  const model = stubModel([GOOD_REPLY]);
  const opts = { complete: model.complete, now: NOW, backoffMs: 0 };
  await internals.generateFor(ME, WEEK, opts);
  for (let i = 0; i < internals.MAX_REGENERATIONS_PER_DAY; i++) {
    assert.equal(await internals.generateFor(ME, WEEK, { ...opts, regenerate: true }), "ready");
  }
  assert.equal(await internals.generateFor(ME, WEEK, { ...opts, regenerate: true }), "quota");
  // The next day the quota is back.
  const tomorrow = new Date(NOW.getTime() + 24 * 60 * 60 * 1000);
  assert.equal(
    await internals.generateFor(ME, WEEK, { ...opts, now: tomorrow, regenerate: true }),
    "ready"
  );
});

test("a fresh claim by someone else is respected", async () => {
  const { internals } = loadWithFakeAdmin(
    seed({
      [`users/${ME}/insights/${WEEK}`]: { status: "generating", claimedAt: new Date(NOW.getTime() - 1000) },
    })
  );
  const model = stubModel([GOOD_REPLY]);
  const status = await internals.generateFor(ME, WEEK, { complete: model.complete, now: NOW, backoffMs: 0 });
  assert.equal(status, "generating");
  assert.equal(model.calls.length, 0);
});

test("the low-intake note is set from meals without reaching the model", async () => {
  const meals = {};
  // Four days, three meals each, about 750 kcal a day.
  ["2026-09-22", "2026-09-23", "2026-09-24", "2026-09-25"].forEach((day, d) => {
    for (let m = 0; m < 3; m++) {
      meals[`meals/m${d}${m}`] = {
        authorId: ME,
        loggedAt: new Date(`${day}T${10 + m * 3}:00:00+02:00`),
        calories: "250 kcal",
      };
    }
  });
  const { internals, store } = loadWithFakeAdmin(seed(meals));
  const model = stubModel([GOOD_REPLY]);
  await internals.generateFor(ME, WEEK, { complete: model.complete, now: NOW, backoffMs: 0 });

  assert.equal(store.get(`users/${ME}/insights/${WEEK}`).wellbeingNote, true);
  assert.equal(/calori|kcal|250/i.test(model.calls[0].user), false);
  assert.match(model.calls[0].user, /"daysWithMealsLogged":4/);
});

test("the weekly job skips people who hid insights and weeks with no data", async () => {
  const OTHER = "uid_other";
  const QUIET = "uid_quiet";
  const { internals, store } = loadWithFakeAdmin(
    seed({
      [`users/${OTHER}`]: { insightsHidden: true },
      [`weeklyStats/${OTHER}_${WEEK}`]: weekStats({ userId: OTHER }),
      [`users/${QUIET}`]: {},
      [`weeklyStats/${QUIET}_${WEEK}`]: weekStats({ userId: QUIET, daysWithData: 0 }),
    })
  );
  const model = stubModel([GOOD_REPLY]);
  const results = await internals.generateWeek(WEEK, { complete: model.complete, backoffMs: 0 });

  assert.deepStrictEqual(results, { ready: 1, skipped: 1, failed: 0 });
  assert.equal(store.has(`users/${OTHER}/insights/${WEEK}`), false);
  assert.equal(store.has(`users/${QUIET}/insights/${WEEK}`), false);
  assert.equal(model.calls.length, 1);
});
