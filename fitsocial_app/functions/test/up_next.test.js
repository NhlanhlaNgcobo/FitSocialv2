/**
 * Up Next: the rules, one by one, then the order they win places in, then the
 * Firestore round trip that keeps a dismissed card dismissed.
 *
 * Every suggestion's wording also goes through the Weekly Insights safety
 * filter: these are fixed sentences, but a future edit to one should fail
 * here rather than on somebody's phone.
 */

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const { createFakeAdmin } = require("./fake_admin");
const { suggestionsFor, streakBefore, goalSuggestion } = require("../up_next")._internals;
const { forbiddenIn } = require("../insights")._internals;

const FUNCTIONS_DIR = path.join(__dirname, "..");
const ME = "uid_me";

// Thursday 1 October 2026, in ISO week 2026-W40 (Monday 28 September).
const TODAY = "2026-10-01";

const active = (extra = {}) => ({ active: true, sessions: 1, hasSteps: true, meals: 0, ...extra });
const quiet = (extra = {}) => ({ active: false, sessions: 0, hasSteps: true, meals: 0, ...extra });

function weeklyGoal(metric, target, progress, extra = {}) {
  return {
    id: `g_${metric}`,
    metric,
    period: "weekly",
    target,
    progress,
    completedCurrent: false,
    currentEndDayKey: "2026-10-04",
    ...extra,
  };
}

const ids = (list) => list.map((s) => s.id);

// --- The rules --------------------------------------------------------------

test("nothing at all for somebody with no data in a fortnight", () => {
  assert.deepStrictEqual(
    suggestionsFor({ todayKey: TODAY, hour: 18, days: {}, goals: [weeklyGoal("workouts", 4, 3)] }),
    []
  );
});

test("a streak counts the active days that end yesterday", () => {
  const days = {
    "2026-09-27": active(),
    "2026-09-28": quiet(),
    "2026-09-29": active(),
    "2026-09-30": active(),
  };
  assert.equal(streakBefore(TODAY, days), 2);
});

test("a streak at risk shows from 15:00, not before, and not once today is active", () => {
  const days = { "2026-09-29": active(), "2026-09-30": active() };
  assert.deepStrictEqual(ids(suggestionsFor({ todayKey: TODAY, hour: 16, days })), ["streak"]);
  assert.deepStrictEqual(ids(suggestionsFor({ todayKey: TODAY, hour: 14, days })), []);
  assert.deepStrictEqual(
    ids(suggestionsFor({ todayKey: TODAY, hour: 16, days: { ...days, [TODAY]: active() } })),
    []
  );
  // A one-day streak is not worth protecting.
  assert.deepStrictEqual(
    ids(suggestionsFor({ todayKey: TODAY, hour: 16, days: { "2026-09-30": active() } })),
    []
  );
});

test("a step goal close enough suggests a walk of the right length", () => {
  const s = goalSuggestion(weeklyGoal("steps", 70000, 67700), TODAY);
  assert.equal(s.title, "2,300 steps to your weekly goal");
  assert.equal(s.reason, "A 25-minute walk gets you there.");
  assert.equal(s.route, "/goals");
});

test("goals that today cannot finish, or that are done, suggest nothing", () => {
  assert.equal(goalSuggestion(weeklyGoal("steps", 70000, 50000), TODAY), null);
  assert.equal(goalSuggestion(weeklyGoal("active_minutes", 300, 200), TODAY), null);
  assert.equal(goalSuggestion(weeklyGoal("workouts", 4, 2), TODAY), null);
  assert.equal(goalSuggestion(weeklyGoal("workouts", 4, 4), TODAY), null);
  assert.equal(
    goalSuggestion(weeklyGoal("workouts", 4, 3, { completedCurrent: true }), TODAY),
    null
  );
  assert.equal(
    goalSuggestion(weeklyGoal("workouts", 4, 3, { period: "monthly" }), TODAY),
    null
  );
  // A goal whose period ended is waiting for the nightly rollover.
  assert.equal(
    goalSuggestion(weeklyGoal("workouts", 4, 3, { currentEndDayKey: "2026-09-27" }), TODAY),
    null
  );
});

test("other goal metrics phrase their gap", () => {
  assert.equal(goalSuggestion(weeklyGoal("workouts", 4, 3), TODAY).title, "One session from your weekly goal");
  assert.equal(goalSuggestion(weeklyGoal("active_minutes", 150, 125), TODAY).title, "25 active minutes to your weekly goal");
  assert.equal(goalSuggestion(weeklyGoal("meals_logged", 21, 20), TODAY).title, "1 more meal to log this week");
});

test("the meal nudge needs a habit and the right time of day", () => {
  const habit = {
    "2026-09-30": quiet({ meals: 3 }),
    "2026-09-29": quiet({ meals: 2 }),
    "2026-09-27": quiet({ meals: 1 }),
  };
  assert.deepStrictEqual(ids(suggestionsFor({ todayKey: TODAY, hour: 13, days: habit })), ["meal"]);
  assert.deepStrictEqual(ids(suggestionsFor({ todayKey: TODAY, hour: 9, days: habit })), []);
  assert.deepStrictEqual(ids(suggestionsFor({ todayKey: TODAY, hour: 22, days: habit })), []);
  // Logged today already.
  assert.deepStrictEqual(
    ids(suggestionsFor({ todayKey: TODAY, hour: 13, days: { ...habit, [TODAY]: quiet({ meals: 1 }) } })),
    []
  );
  // Two days out of seven is not a habit to keep going.
  const { "2026-09-27": _, ...twoDays } = habit;
  assert.deepStrictEqual(ids(suggestionsFor({ todayKey: TODAY, hour: 13, days: twoDays })), []);
});

test("a quiet week is nudged by Wednesday, only for somebody who trains", () => {
  const trainedBefore = { "2026-09-24": active(), "2026-09-29": quiet() };
  assert.deepStrictEqual(ids(suggestionsFor({ todayKey: TODAY, hour: 10, days: trainedBefore })), ["week"]);
  // Tuesday is too early to call it.
  assert.deepStrictEqual(
    ids(suggestionsFor({ todayKey: "2026-09-29", hour: 10, days: trainedBefore })),
    []
  );
  // Never trained: nothing to get back to.
  assert.deepStrictEqual(
    ids(suggestionsFor({ todayKey: TODAY, hour: 10, days: { "2026-09-29": quiet() } })),
    []
  );
});

test("at most three, best first, and dismissed ones never come back", () => {
  const days = {
    "2026-09-29": active({ meals: 2 }),
    "2026-09-30": active({ meals: 3 }),
    "2026-09-27": active({ meals: 1 }),
  };
  const goals = [
    weeklyGoal("workouts", 4, 3),
    weeklyGoal("steps", 70000, 69000),
    weeklyGoal("active_minutes", 150, 140),
  ];
  const all = suggestionsFor({ todayKey: TODAY, hour: 16, days, goals });
  assert.equal(all.length, 3);
  assert.equal(all[0].id, "streak");
  // Closest goal (by share of the target left) next.
  assert.equal(all[1].id, "goal:g_steps");

  const after = suggestionsFor({ todayKey: TODAY, hour: 16, days, goals, dismissed: ["streak"] });
  assert.equal(after.some((s) => s.id === "streak"), false);
  assert.equal(after.length, 3);
});

test("every suggestion has a reason and a route, and passes the safety filter", () => {
  const days = {
    "2026-09-24": active({ meals: 2 }),
    "2026-09-26": active({ meals: 2 }),
    "2026-09-27": active({ meals: 2 }),
  };
  const goals = ["steps", "active_minutes", "workouts", "meals_logged"].map((metric, i) =>
    weeklyGoal(metric, [70000, 150, 4, 21][i], [69000, 140, 3, 20][i])
  );
  const all = [
    ...suggestionsFor({ todayKey: TODAY, hour: 16, days, goals }),
    ...goals.map((g) => goalSuggestion(g, TODAY)),
    ...suggestionsFor({ todayKey: TODAY, hour: 13, days }),
  ];
  assert.ok(all.length >= 6);
  for (const s of all) {
    assert.ok(s.title && s.reason && s.route.startsWith("/"), JSON.stringify(s));
    assert.equal(forbiddenIn(`${s.title}\n${s.reason}`), false, s.title);
  }
});

// --- Firestore --------------------------------------------------------------

function loadWithFakeAdmin(seed) {
  const adminPath = require.resolve("firebase-admin", { paths: [FUNCTIONS_DIR] });
  const modulePaths = [
    require.resolve("../challenges.js"),
    require.resolve("../stats.js"),
    require.resolve("../remote_config.js"),
    require.resolve("../up_next.js"),
  ];
  const fake = createFakeAdmin(seed);
  const previousAdmin = require.cache[adminPath];
  const previousModules = modulePaths.map((p) => require.cache[p]);
  require.cache[adminPath] = { id: adminPath, filename: adminPath, loaded: true, exports: fake.admin };
  for (const p of modulePaths) delete require.cache[p];
  const module = require(require.resolve("../up_next.js"));
  if (previousAdmin) require.cache[adminPath] = previousAdmin;
  else delete require.cache[adminPath];
  modulePaths.forEach((p, i) => {
    if (previousModules[i]) require.cache[p] = previousModules[i];
    else delete require.cache[p];
  });
  return { ...fake, internals: module._internals };
}

test("a rebuild writes today's suggestions and keeps what was dismissed", async () => {
  // 16:00 in South Africa on Thursday 1 October.
  const now = new Date("2026-10-01T14:00:00Z");
  const { internals, store } = loadWithFakeAdmin({
    [`users/${ME}`]: { utcOffsetMinutes: 120 },
    [`dailyStats/${ME}_2026-09-29`]: active(),
    [`dailyStats/${ME}_2026-09-30`]: active(),
    [`users/${ME}/goals/g1`]: { ...weeklyGoal("workouts", 4, 3), status: "active" },
    [`users/${ME}/upNext/${TODAY}`]: { dismissed: ["streak"] },
  });

  assert.equal(await internals.refreshFor(ME, now), TODAY);

  const doc = store.get(`users/${ME}/upNext/${TODAY}`);
  assert.deepStrictEqual(doc.dismissed, ["streak"]);
  assert.deepStrictEqual(doc.suggestions.map((s) => s.id), ["goal:g1"]);
  assert.deepStrictEqual(Object.keys(doc.suggestions[0]).sort(), ["id", "kind", "reason", "route", "title"]);
});
