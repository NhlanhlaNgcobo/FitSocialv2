/**
 * Activity challenges: standings and ordering, checked by hand.
 */

const test = require("node:test");
const assert = require("node:assert");

const {
  dayValue,
  effectiveStart,
  standingFrom,
  compareActivity,
  validateActivityChallenge,
} = require("../activity_ranking");

const WEEK = { startDayKey: "2026-09-28", endDayKey: "2026-10-04" };

test("each metric reads its rankable daily figure", () => {
  const day = { rankableSteps: 7000, steps: 9000, rankableActiveMinutes: 40,
    sessions: 2, meals: 3 };
  assert.strictEqual(dayValue(day, "steps"), 7000, "never the raw steps");
  assert.strictEqual(dayValue(day, "active_minutes"), 40);
  assert.strictEqual(dayValue(day, "workouts"), 2);
  assert.strictEqual(dayValue(day, "meals_logged"), 3);
  assert.strictEqual(dayValue(null, "steps"), 0);
  assert.strictEqual(dayValue(day, "sleep"), 0);
});

test("joining late counts from the day you joined", () => {
  assert.strictEqual(effectiveStart(WEEK, "2026-09-30"), "2026-09-30");
  assert.strictEqual(effectiveStart(WEEK, "2026-09-20"), "2026-09-28");
  assert.strictEqual(effectiveStart(WEEK, null), "2026-09-28");
});

test("cumulative: days outside the window are ignored", () => {
  const standing = standingFrom(
    { ...WEEK, mode: "cumulative" },
    {
      "2026-09-27": 50000, // before the start
      "2026-09-29": 8000,
      "2026-10-01": 6000,
      "2026-10-05": 9000, // after the end
    },
    "2026-09-28"
  );
  assert.deepStrictEqual(standing, {
    total: 14000,
    lastGainDayKey: "2026-10-01",
    targetReachedDayKey: null,
    qualifiedDays: 0,
    longestStreak: 0,
  });
});

test("a late joiner's earlier days do not count", () => {
  const standing = standingFrom(
    { ...WEEK, mode: "cumulative" },
    { "2026-09-28": 10000, "2026-09-30": 3000 },
    "2026-09-30"
  );
  assert.strictEqual(standing.total, 3000);
});

test("target: the day the running total first reaches the target", () => {
  const standing = standingFrom(
    { ...WEEK, mode: "target", target: 20000 },
    { "2026-09-28": 8000, "2026-09-29": 8000, "2026-09-30": 8000,
      "2026-10-01": 8000 },
    "2026-09-28"
  );
  assert.strictEqual(standing.total, 32000);
  assert.strictEqual(standing.targetReachedDayKey, "2026-09-30");
});

test("streak: the longest run of days that reached the daily target", () => {
  const standing = standingFrom(
    { ...WEEK, mode: "streak", target: 10000 },
    {
      "2026-09-28": 12000,
      "2026-09-29": 11000,
      "2026-09-30": 4000, // breaks it
      "2026-10-01": 10000,
      "2026-10-02": 10500,
      "2026-10-03": 15000,
    },
    "2026-09-28"
  );
  assert.strictEqual(standing.longestStreak, 3);
  assert.strictEqual(standing.qualifiedDays, 5);
});

const person = (userId, fields = {}) => ({
  userId,
  total: 0,
  longestStreak: 0,
  targetReachedDayKey: null,
  lastGainDayKey: null,
  joinedAtMillis: 1000,
  ...fields,
});

const order = (mode, people) =>
  [...people].sort(compareActivity(mode)).map((p) => p.userId);

test("cumulative ranks by total", () => {
  assert.deepStrictEqual(
    order("cumulative", [
      person("a", { total: 10, lastGainDayKey: "2026-09-29" }),
      person("b", { total: 30, lastGainDayKey: "2026-09-29" }),
      person("c", { total: 20, lastGainDayKey: "2026-09-29" }),
    ]),
    ["b", "c", "a"]
  );
});

test("an equal total goes to whoever reached it on an earlier day", () => {
  assert.deepStrictEqual(
    order("cumulative", [
      person("late", { total: 20, lastGainDayKey: "2026-10-02" }),
      person("early", { total: 20, lastGainDayKey: "2026-09-30" }),
    ]),
    ["early", "late"]
  );
});

test("an exact tie falls back to join time, then id, and never reshuffles", () => {
  const tied = [
    person("z", { total: 5, lastGainDayKey: "2026-09-30", joinedAtMillis: 1 }),
    person("y", { total: 5, lastGainDayKey: "2026-09-30", joinedAtMillis: 2 }),
    person("x", { total: 5, lastGainDayKey: "2026-09-30", joinedAtMillis: 2 }),
  ];
  assert.deepStrictEqual(order("cumulative", tied), ["z", "x", "y"]);
  assert.deepStrictEqual(order("cumulative", [...tied].reverse()), ["z", "x", "y"]);
});

test("target: whoever reached it first leads, even with a smaller total", () => {
  assert.deepStrictEqual(
    order("target", [
      person("big", { total: 90, targetReachedDayKey: "2026-10-01" }),
      person("first", { total: 60, targetReachedDayKey: "2026-09-30" }),
      person("close", { total: 49 }),
      person("far", { total: 10 }),
    ]),
    ["first", "big", "close", "far"]
  );
});

test("streak: longest streak first, then total", () => {
  assert.deepStrictEqual(
    order("streak", [
      person("a", { longestStreak: 2, total: 90 }),
      person("b", { longestStreak: 4, total: 40 }),
      person("c", { longestStreak: 4, total: 50 }),
    ]),
    ["c", "b", "a"]
  );
});

test("a challenge definition is checked before it is written", () => {
  assert.strictEqual(
    validateActivityChallenge({ metric: "steps", mode: "cumulative" }),
    null
  );
  assert.strictEqual(
    validateActivityChallenge({ metric: "steps", mode: "target", target: 50000 }),
    null
  );
  assert.strictEqual(
    validateActivityChallenge({ metric: "weight", mode: "cumulative" }),
    "metric"
  );
  assert.strictEqual(
    validateActivityChallenge({ metric: "steps", mode: "target" }),
    "target"
  );
  assert.strictEqual(
    validateActivityChallenge({ metric: "steps", mode: "cumulative", target: 5 }),
    "target"
  );
});
