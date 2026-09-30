/**
 * Personal goals: validation, period arithmetic, and the one rule that keeps
 * completion counts honest -- a period is counted the first time it completes
 * and never again.
 */

const test = require("node:test");
const assert = require("node:assert");

const {
  validateGoal,
  periodOf,
  evaluatePeriod,
  metricValue,
  MAX_CUSTOM_DAYS,
} = require("../goals")._internals;

const TODAY = "2026-09-30"; // A Wednesday in 2026-W40.

test("weekly goals run Monday to Sunday in the ISO week", () => {
  assert.deepStrictEqual(periodOf({ period: "weekly" }, TODAY), {
    id: "2026-W40",
    startDayKey: "2026-09-28",
    endDayKey: "2026-10-04",
  });
});

test("monthly and annual periods", () => {
  assert.deepStrictEqual(periodOf({ period: "monthly" }, TODAY), {
    id: "2026-09",
    startDayKey: "2026-09-01",
    endDayKey: "2026-09-30",
  });
  assert.deepStrictEqual(periodOf({ period: "annual" }, TODAY), {
    id: "2026",
    startDayKey: "2026-01-01",
    endDayKey: "2026-12-31",
  });
});

test("a year-end week belongs to the ISO year of its Thursday", () => {
  assert.strictEqual(periodOf({ period: "weekly" }, "2027-01-01").id, "2026-W53");
});

test("valid goals pass and are cleaned", () => {
  assert.deepStrictEqual(
    validateGoal({ metric: "steps", period: "weekly", target: 70000, extra: 1 }, TODAY),
    { metric: "steps", period: "weekly", target: 70000 }
  );
  assert.deepStrictEqual(
    validateGoal(
      { metric: "workouts", period: "custom", target: 12,
        startDayKey: "2026-09-28", endDayKey: "2026-10-27" },
      TODAY
    ),
    { metric: "workouts", period: "custom", target: 12,
      startDayKey: "2026-09-28", endDayKey: "2026-10-27" }
  );
});

test("bad goals are refused with a message the app can show", () => {
  const refused = [
    { metric: "weight", period: "weekly", target: 1 },
    { metric: "steps", period: "daily", target: 1 },
    { metric: "steps", period: "weekly", target: 0 },
    { metric: "steps", period: "weekly", target: 2.5 },
    { metric: "steps", period: "weekly", target: "10000" + "x" },
    // Eight days' streak in a seven-day week.
    { metric: "streak", period: "weekly", target: 8 },
    // More steps than a week can hold at the daily ceiling.
    { metric: "steps", period: "weekly", target: 700001 },
    { metric: "steps", period: "custom", target: 1 },
    { metric: "steps", period: "custom", target: 1,
      startDayKey: "2026-09-01", endDayKey: "2026-09-29" },
    { metric: "steps", period: "custom", target: 1,
      startDayKey: "2026-10-10", endDayKey: "2026-10-01" },
    { metric: "steps", period: "custom", target: 1,
      startDayKey: "2026-09-01", endDayKey: "2026-10-30" },
  ];
  for (const input of refused) {
    assert.throws(() => validateGoal(input, TODAY), /./, JSON.stringify(input));
  }
});

test("custom goals are capped in length", () => {
  const end = new Date(Date.UTC(2026, 8, 30 + MAX_CUSTOM_DAYS))
    .toISOString().slice(0, 10);
  assert.throws(() =>
    validateGoal(
      { metric: "steps", period: "custom", target: 1,
        startDayKey: TODAY, endDayKey: end },
      TODAY
    )
  );
});

test("each metric reads its own stats field", () => {
  const stats = { steps: 1, activeMinutes: 2, sessions: 3, meals: 4, longestStreak: 5 };
  assert.strictEqual(metricValue(stats, "steps"), 1);
  assert.strictEqual(metricValue(stats, "active_minutes"), 2);
  assert.strictEqual(metricValue(stats, "workouts"), 3);
  assert.strictEqual(metricValue(stats, "meals_logged"), 4);
  assert.strictEqual(metricValue(stats, "streak"), 5);
  assert.strictEqual(metricValue(null, "steps"), 0);
});

const goal = { target: 4 };
const week = { id: "2026-W40", startDayKey: "2026-09-28", endDayKey: "2026-10-04" };

test("a period below target is recorded, not completed", () => {
  const outcome = evaluatePeriod(goal, week, 3, null);
  assert.strictEqual(outcome.newlyCompleted, false);
  assert.strictEqual(outcome.record.completed, false);
  assert.strictEqual(outcome.record.progress, 3);
});

test("reaching the target completes the period exactly once", () => {
  const first = evaluatePeriod(goal, week, 4, { completed: false });
  assert.strictEqual(first.newlyCompleted, true);

  // The same trigger delivered again finds the record already completed.
  const again = evaluatePeriod(goal, week, 4, first.record);
  assert.strictEqual(again.newlyCompleted, false);
  assert.strictEqual(again.record.completed, true);
});

test("completion is sticky within its period", () => {
  // A session deleted after the week was hit does not un-hit it.
  const later = evaluatePeriod(goal, week, 3, { completed: true });
  assert.strictEqual(later.record.completed, true);
  assert.strictEqual(later.newlyCompleted, false);
  assert.strictEqual(later.record.progress, 3, "progress still shows the truth");
});
