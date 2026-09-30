/**
 * The stats pipeline's arithmetic, checked against hand-worked fixtures.
 *
 * Only the pure half is tested here: what a day adds up to, and what a week or
 * a month of days adds up to. The Firestore half is thin plumbing over these,
 * and the rules tests cover who may read and write the documents.
 */

const test = require("node:test");
const assert = require("node:assert");

const { dayStatsFrom, rollUp, mergePeriods, longestStreak } =
  require("../stats")._internals;

const CAPS = { maxDailySteps: 100000, maxDailyActiveMinutes: 1440 };

test("a day adds up its logs", () => {
  const day = dayStatsFrom(
    {
      steps: { steps: 9000, manualSteps: 1500, avgHeartRate: 71, maxHeartRate: 150 },
      workouts: [{ durationMinutes: 45 }, { durationMinutes: 20 }],
      runs: [{ durationSeconds: 1800 }],
      meals: [{}, {}, {}],
    },
    CAPS
  );
  assert.strictEqual(day.steps, 9000);
  assert.strictEqual(day.manualSteps, 1500);
  assert.strictEqual(day.rankableSteps, 7500);
  assert.strictEqual(day.activeMinutes, 95);
  assert.strictEqual(day.rankableActiveMinutes, 95);
  assert.strictEqual(day.sessions, 3);
  assert.strictEqual(day.meals, 3);
  assert.strictEqual(day.active, true);
  assert.strictEqual(day.hasSteps, true);
  assert.strictEqual(day.avgHeartRate, 71);
  assert.deepStrictEqual(day.flags, []);
});

test("a day with nothing logged is not active and has no heart rate", () => {
  const day = dayStatsFrom({ steps: null }, CAPS);
  assert.strictEqual(day.steps, 0);
  assert.strictEqual(day.active, false);
  assert.strictEqual(day.hasSteps, false);
  assert.strictEqual(day.avgHeartRate, null);
  assert.strictEqual(day.maxHeartRate, null);
});

test("a day over the step ceiling is flagged and ranks as zero", () => {
  const day = dayStatsFrom({ steps: { steps: 150000 } }, CAPS);
  assert.deepStrictEqual(day.flags, ["steps_over_cap"]);
  assert.strictEqual(day.steps, 150000, "the raw figure stays for its owner");
  assert.strictEqual(day.rankableSteps, 0);
});

test("more than 24 hours of activity is flagged", () => {
  const day = dayStatsFrom(
    { workouts: [{ durationMinutes: 1000 }, { durationMinutes: 500 }] },
    CAPS
  );
  assert.deepStrictEqual(day.flags, ["active_minutes_over_cap"]);
  assert.strictEqual(day.rankableActiveMinutes, 0);
  assert.strictEqual(day.activeMinutes, 1500);
});

test("manual steps can never exceed the total", () => {
  const day = dayStatsFrom({ steps: { steps: 100, manualSteps: 900 } }, CAPS);
  assert.strictEqual(day.manualSteps, 100);
  assert.strictEqual(day.rankableSteps, 0);
});

test("garbage in a log counts as nothing, not NaN", () => {
  const day = dayStatsFrom(
    {
      steps: { steps: "lots" },
      workouts: [{ durationMinutes: "an hour" }, { durationMinutes: -5 }],
      runs: [{}],
    },
    CAPS
  );
  assert.strictEqual(day.steps, 0);
  assert.strictEqual(day.activeMinutes, 0);
  assert.strictEqual(day.sessions, 3);
});

test("longest streak counts consecutive days, across a month end", () => {
  assert.strictEqual(longestStreak([]), 0);
  assert.strictEqual(longestStreak(["2026-09-30"]), 1);
  assert.strictEqual(
    longestStreak(["2026-09-29", "2026-09-30", "2026-10-01", "2026-10-03"]),
    3
  );
  assert.strictEqual(
    longestStreak(["2026-10-03", "2026-09-30", "2026-10-01", "2026-09-30"]),
    2,
    "order and duplicates do not matter"
  );
  assert.strictEqual(longestStreak(["2024-02-28", "2024-02-29", "2024-03-01"]), 3);
});

const WEEK = [
  "2026-09-28",
  "2026-09-29",
  "2026-09-30",
  "2026-10-01",
  "2026-10-02",
  "2026-10-03",
  "2026-10-04",
];

test("a week rolls up its days, hand-checked", () => {
  const days = {
    "2026-09-28": dayStatsFrom(
      { steps: { steps: 8000, avgHeartRate: 70, heartRateCoverageMinutes: 600 },
        workouts: [{ durationMinutes: 30 }], meals: [{}, {}] },
      CAPS
    ),
    "2026-09-29": dayStatsFrom(
      { steps: { steps: 12000, manualSteps: 2000, avgHeartRate: 80,
                 heartRateCoverageMinutes: 200, maxHeartRate: 170 },
        runs: [{ durationSeconds: 2400 }] },
      CAPS
    ),
    "2026-10-01": dayStatsFrom({ steps: { steps: 150000 } }, CAPS),
    "2026-10-02": dayStatsFrom({ meals: [{}] }, CAPS),
  };
  const week = rollUp(days, WEEK);

  assert.strictEqual(week.steps, 170000);
  assert.strictEqual(week.rankableSteps, 8000 + 10000 + 0);
  assert.strictEqual(week.manualSteps, 2000);
  assert.strictEqual(week.activeMinutes, 70);
  assert.strictEqual(week.sessions, 2);
  assert.strictEqual(week.meals, 3);
  assert.strictEqual(week.dayCount, 7);
  assert.strictEqual(week.daysWithSteps, 3);
  assert.strictEqual(week.daysWithData, 4);
  assert.strictEqual(week.flaggedDays, 1);
  assert.deepStrictEqual(week.activeDayKeys, ["2026-09-28", "2026-09-29"]);
  assert.strictEqual(week.longestStreak, 2);
  // (70 * 600 + 80 * 200) / 800 = 72.5, rounded.
  assert.strictEqual(week.avgHeartRate, 73);
  assert.strictEqual(week.maxHeartRate, 170);
});

test("an empty week is zeros and nulls, never NaN", () => {
  const week = rollUp({}, WEEK);
  assert.strictEqual(week.steps, 0);
  assert.strictEqual(week.daysWithData, 0);
  assert.strictEqual(week.avgHeartRate, null);
  assert.strictEqual(week.maxHeartRate, null);
  assert.strictEqual(week.longestStreak, 0);
  for (const value of Object.values(week)) {
    if (typeof value === "number") assert.ok(Number.isFinite(value));
  }
});

test("days outside the period are ignored", () => {
  const days = { "2026-10-05": dayStatsFrom({ steps: { steps: 5000 } }, CAPS) };
  assert.strictEqual(rollUp(days, WEEK).steps, 0);
});

test("periods merge into a longer span, with streaks across the seam", () => {
  const september = {
    steps: 100, sessions: 2, meals: 1, dayCount: 30, daysWithData: 2,
    activeDayKeys: ["2026-09-29", "2026-09-30"], avgHeartRate: 70,
    maxHeartRate: 150,
  };
  const october = {
    steps: 50, sessions: 1, meals: 0, dayCount: 31, daysWithData: 1,
    activeDayKeys: ["2026-10-01"], avgHeartRate: null, maxHeartRate: null,
  };
  const merged = mergePeriods([september, null, october]);
  assert.strictEqual(merged.steps, 150);
  assert.strictEqual(merged.sessions, 3);
  assert.strictEqual(merged.dayCount, 61);
  assert.strictEqual(merged.activeDays, 3);
  assert.strictEqual(merged.longestStreak, 3);
  assert.strictEqual(merged.avgHeartRate, 70);
  assert.strictEqual(merged.maxHeartRate, 150);
});
