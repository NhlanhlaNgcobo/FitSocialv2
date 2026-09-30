/**
 * Daily, weekly and monthly stats: the numbers goals, Compare and the friends
 * leaderboard are all built from.
 *
 * Three layers, each derived from the one below and never accumulated:
 *
 *   dailyStats/{uid}_{dayKey}     from the day's runs, workouts, meals and
 *                                  dailySteps record
 *   weeklyStats/{uid}_{weekId}    from that week's seven daily documents
 *   monthlyStats/{uid}_{monthId}  from that month's daily documents
 *
 * Every layer is recomputed from scratch whenever something beneath it
 * changes, which is what makes the whole pipeline idempotent: a trigger that
 * fires twice writes the same numbers twice, and a deleted run is subtracted
 * simply by no longer being there to read. There is no running total anywhere
 * to unwind.
 *
 * All three are server-written and closed to clients in firestore.rules. The
 * phone reports what it measured (dailySteps) and what the user logged (runs,
 * workouts, meals); what that adds up to is decided here.
 *
 * Integrity. Two numbers can rank somebody: steps and active minutes. Each
 * day carries its raw figure and a `rankable` one. Rankable steps leave out
 * anything typed in by hand; either rankable figure is zero for a day whose
 * raw value is over the Remote Config ceiling, and the day is flagged. The raw
 * figures stay, and stay visible to their owner -- a flagged day is excluded
 * from ranking, not deleted, and nobody is banned by this file.
 *
 * Dormant while every reader is switched off: with no Build 11 feature on,
 * the triggers return before reading anything, so a dark build costs nothing.
 */

const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

const {
  db,
  dayKeyOf,
  dayRange,
  activityInDay,
  offsetFor,
} = require("./challenges")._internals;
const periods = require("./period_keys");
const remoteConfig = require("./remote_config");

/** Features that read these stats. Any one being on keeps the pipeline live. */
const READER_FLAGS = [
  "f1_goals_challenges",
  "f2_weekly_insights",
  "f3_up_next",
  "f4_compare",
  "f6_leaderboards",
];

// --- Pure: one day ---------------------------------------------------------

function toInt(value) {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.round(n) : 0;
}

function nullableInt(value) {
  const n = Number(value);
  return value == null || !Number.isFinite(n) ? null : Math.round(n);
}

/**
 * A day's stats from its raw inputs, all plain objects.
 *
 * Definitions, shared with the app's labels:
 *   activeMinutes  workout minutes plus run/hike/ride minutes
 *   sessions       workouts plus runs/hikes/rides, one each
 *   meals          meals logged
 *   active         at least one session -- what a streak counts
 */
function dayStatsFrom({ steps, workouts = [], runs = [], meals = [] }, caps) {
  const totalSteps = toInt(steps?.steps);
  const manualSteps = Math.min(toInt(steps?.manualSteps), totalSteps);

  const workoutMinutes = workouts.reduce(
    (sum, w) => sum + toInt(w.durationMinutes),
    0
  );
  const runMinutes = runs.reduce(
    (sum, r) => sum + toInt(r.durationSeconds) / 60,
    0
  );
  const activeMinutes = Math.round(workoutMinutes + runMinutes);

  const flags = [];
  if (totalSteps > caps.maxDailySteps) flags.push("steps_over_cap");
  if (activeMinutes > caps.maxDailyActiveMinutes) {
    flags.push("active_minutes_over_cap");
  }

  const sessions = workouts.length + runs.length;
  return {
    steps: totalSteps,
    manualSteps,
    rankableSteps: flags.includes("steps_over_cap")
      ? 0
      : totalSteps - manualSteps,
    activeMinutes,
    rankableActiveMinutes: flags.includes("active_minutes_over_cap")
      ? 0
      : activeMinutes,
    sessions,
    meals: meals.length,
    active: sessions > 0,
    hasSteps: steps != null,
    avgHeartRate: nullableInt(steps?.avgHeartRate),
    maxHeartRate: nullableInt(steps?.maxHeartRate),
    heartRateCoverageMinutes: nullableInt(steps?.heartRateCoverageMinutes),
    flags,
  };
}

// --- Pure: a period --------------------------------------------------------

const SUMMED = [
  "steps",
  "manualSteps",
  "rankableSteps",
  "activeMinutes",
  "rankableActiveMinutes",
  "sessions",
  "meals",
];

/** The longest run of consecutive day keys in [dayKeys] (any order). */
function longestStreak(dayKeys) {
  const sorted = [...new Set(dayKeys)].sort();
  let best = 0;
  let current = 0;
  let previous = null;
  for (const key of sorted) {
    current = previous != null && nextDay(previous) === key ? current + 1 : 1;
    if (current > best) best = current;
    previous = key;
  }
  return best;
}

function nextDay(dayKey) {
  const [y, m, d] = dayKey.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + 1)).toISOString().slice(0, 10);
}

/**
 * A period's stats from the daily stats inside it.
 *
 * [days] maps day key to that day's stats, and may be sparse: a day nobody
 * logged anything on has no document. [dayKeys] is every day in the period,
 * so the result can say how many of them had data -- which is what lets
 * Compare say "not enough data yet" instead of comparing a real week against
 * three empty days.
 *
 * Heart rate is averaged weighted by how much of each day it covered, so one
 * spot reading does not count as much as a day-long watch trace.
 */
function rollUp(days, dayKeys) {
  const totals = Object.fromEntries(SUMMED.map((key) => [key, 0]));
  const activeDayKeys = [];
  let daysWithSteps = 0;
  let daysWithData = 0;
  let flaggedDays = 0;
  let hrWeighted = 0;
  let hrWeight = 0;
  let maxHeartRate = null;

  for (const key of dayKeys) {
    const day = days[key];
    if (!day) continue;
    for (const field of SUMMED) totals[field] += toInt(day[field]);
    if (day.active) activeDayKeys.push(key);
    if (day.hasSteps) daysWithSteps += 1;
    if (day.hasSteps || day.active || toInt(day.meals) > 0) daysWithData += 1;
    if ((day.flags || []).length > 0) flaggedDays += 1;
    if (day.avgHeartRate != null) {
      const weight = Math.max(1, toInt(day.heartRateCoverageMinutes));
      hrWeighted += day.avgHeartRate * weight;
      hrWeight += weight;
    }
    if (day.maxHeartRate != null) {
      maxHeartRate = Math.max(maxHeartRate ?? 0, day.maxHeartRate);
    }
  }

  return {
    ...totals,
    dayCount: dayKeys.length,
    daysWithSteps,
    daysWithData,
    flaggedDays,
    activeDays: activeDayKeys.length,
    activeDayKeys,
    longestStreak: longestStreak(activeDayKeys),
    avgHeartRate: hrWeight > 0 ? Math.round(hrWeighted / hrWeight) : null,
    maxHeartRate,
  };
}

/**
 * Several periods' stats combined into one, for spans no document is kept
 * for -- a year, from its months. Sums add; streaks and heart rate are worked
 * out again over the combined days, since a streak can cross a month end.
 */
function mergePeriods(list) {
  const totals = Object.fromEntries(SUMMED.map((key) => [key, 0]));
  const activeDayKeys = [];
  const counters = {
    dayCount: 0,
    daysWithSteps: 0,
    daysWithData: 0,
    flaggedDays: 0,
  };
  let hrWeighted = 0;
  let hrWeight = 0;
  let maxHeartRate = null;

  for (const period of list) {
    if (!period) continue;
    for (const field of SUMMED) totals[field] += toInt(period[field]);
    for (const field of Object.keys(counters)) {
      counters[field] += toInt(period[field]);
    }
    activeDayKeys.push(...(period.activeDayKeys || []));
    if (period.avgHeartRate != null) {
      // Weighted by days with data: the period's own weighting is already
      // folded into its average and cannot be recovered from it.
      const weight = Math.max(1, toInt(period.daysWithData));
      hrWeighted += period.avgHeartRate * weight;
      hrWeight += weight;
    }
    if (period.maxHeartRate != null) {
      maxHeartRate = Math.max(maxHeartRate ?? 0, period.maxHeartRate);
    }
  }

  const unique = [...new Set(activeDayKeys)].sort();
  return {
    ...totals,
    ...counters,
    activeDays: unique.length,
    activeDayKeys: unique,
    longestStreak: longestStreak(unique),
    avgHeartRate: hrWeight > 0 ? Math.round(hrWeighted / hrWeight) : null,
    maxHeartRate,
  };
}

// --- Firestore --------------------------------------------------------------

const serverTimestamp = () => admin.firestore.FieldValue.serverTimestamp();

const dailyRef = (uid, dayKey) =>
  db().collection("dailyStats").doc(`${uid}_${dayKey}`);
const weeklyRef = (uid, weekId) =>
  db().collection("weeklyStats").doc(`${uid}_${weekId}`);
const monthlyRef = (uid, monthId) =>
  db().collection("monthlyStats").doc(`${uid}_${monthId}`);

async function caps() {
  const values = await remoteConfig.values();
  return {
    maxDailySteps: values.integrity_max_daily_steps,
    maxDailyActiveMinutes: values.integrity_max_daily_active_minutes,
  };
}

async function anyReaderOn() {
  const values = await remoteConfig.values();
  return READER_FLAGS.some((flag) => values[flag] === true);
}

/** Rebuilds one day's stats from the logs. Returns what it wrote. */
async function recomputeDay(uid, dayKey, offsetMinutes) {
  const { start, end } = dayRange(dayKey, offsetMinutes);
  const [workouts, runs, meals, steps] = await Promise.all([
    activityInDay("workouts", uid, ["loggedAt", "createdAt"], start, end),
    activityInDay("runs", uid, ["startedAt", "createdAt"], start, end),
    activityInDay("meals", uid, ["loggedAt", "createdAt"], start, end),
    db().collection("dailySteps").doc(`${uid}_${dayKey}`).get(),
  ]);

  const stats = dayStatsFrom(
    {
      steps: steps.exists ? steps.data() : null,
      workouts: workouts.map((d) => d.data()),
      runs: runs.map((d) => d.data()),
      meals: meals.map((d) => d.data()),
    },
    await caps()
  );

  await dailyRef(uid, dayKey).set({
    userId: uid,
    dayKey,
    weekId: periods.isoWeekIdOf(dayKey),
    monthId: periods.monthIdOf(dayKey),
    ...stats,
    updatedAt: serverTimestamp(),
  });
  return stats;
}

/** Reads the daily stats for [dayKeys] into `{ dayKey: stats }`. */
async function readDays(uid, dayKeys) {
  const snaps = await Promise.all(
    dayKeys.map((key) => dailyRef(uid, key).get())
  );
  const days = {};
  snaps.forEach((snap, i) => {
    if (snap.exists) days[dayKeys[i]] = snap.data();
  });
  return days;
}

async function recomputeWeek(uid, weekId) {
  const dayKeys = periods.weekDayKeys(weekId);
  const stats = rollUp(await readDays(uid, dayKeys), dayKeys);
  await weeklyRef(uid, weekId).set({
    userId: uid,
    weekId,
    startDayKey: dayKeys[0],
    endDayKey: dayKeys[dayKeys.length - 1],
    ...stats,
    updatedAt: serverTimestamp(),
  });
  return stats;
}

async function recomputeMonth(uid, monthId) {
  const dayKeys = periods.monthDayKeys(monthId);
  const stats = rollUp(await readDays(uid, dayKeys), dayKeys);
  await monthlyRef(uid, monthId).set({
    userId: uid,
    monthId,
    startDayKey: dayKeys[0],
    endDayKey: dayKeys[dayKeys.length - 1],
    ...stats,
    updatedAt: serverTimestamp(),
  });
  return stats;
}

/**
 * Everything that follows from a change to [dayKey]: the day, its week, its
 * month, and then whoever else listens (goals). Listeners are registered
 * rather than required, so goals.js can depend on this file without this file
 * depending on it.
 */
const listeners = [];

function onDayChanged(listener) {
  listeners.push(listener);
}

async function refreshDay(uid, dayKey, offsetMinutes) {
  const offset = offsetMinutes ?? (await offsetFor(uid));
  await recomputeDay(uid, dayKey, offset);
  await Promise.all([
    recomputeWeek(uid, periods.isoWeekIdOf(dayKey)),
    recomputeMonth(uid, periods.monthIdOf(dayKey)),
  ]);
  for (const listener of listeners) {
    await listener(uid, dayKey);
  }
}

// --- Triggers --------------------------------------------------------------

/** When a log happened, as an instant, from whichever field it carries. */
function instantOf(data, fields) {
  for (const field of fields) {
    const at = data?.[field]?.toDate?.();
    if (at instanceof Date && !Number.isNaN(at.getTime())) return at;
  }
  return null;
}

/**
 * The days a write to a log touches: the day it is on now, and the day it
 * was on before if an edit moved it. A deletion touches the day it left.
 */
async function touchedDays(event, userField, timeFields) {
  const before = event.data?.before?.data?.() || null;
  const after = event.data?.after?.data?.() || null;
  const uid = after?.[userField] || before?.[userField];
  if (!uid) return null;

  const offset = await offsetFor(uid);
  const keys = new Set();
  for (const data of [before, after]) {
    const at = instantOf(data, timeFields);
    if (at) keys.add(dayKeyOf(at, offset));
  }
  return { uid, offset, dayKeys: [...keys] };
}

function logTrigger(path, timeFields) {
  return onDocumentWritten(path, async (event) => {
    if (!(await anyReaderOn())) return;
    const touched = await touchedDays(event, "authorId", timeFields);
    if (!touched) return;
    for (const dayKey of touched.dayKeys) {
      await refreshDay(touched.uid, dayKey, touched.offset);
    }
  });
}

exports.onRunForStats = logTrigger("runs/{runId}", ["startedAt", "createdAt"]);
exports.onWorkoutForStats = logTrigger("workouts/{workoutId}", [
  "loggedAt",
  "createdAt",
]);
exports.onMealForStats = logTrigger("meals/{mealId}", [
  "loggedAt",
  "createdAt",
]);

exports.onDailyStepsForStats = onDocumentWritten(
  "dailySteps/{docId}",
  async (event) => {
    if (!(await anyReaderOn())) return;
    const data = event.data?.after?.data?.() || event.data?.before?.data?.();
    if (!data?.userId || !data?.dayKey) return;
    await refreshDay(data.userId, data.dayKey);
  }
);

exports._internals = {
  dayStatsFrom,
  rollUp,
  mergePeriods,
  longestStreak,
  recomputeDay,
  recomputeWeek,
  recomputeMonth,
  readDays,
  refreshDay,
  onDayChanged,
  anyReaderOn,
  weeklyRef,
  monthlyRef,
  dailyRef,
  READER_FLAGS,
};
