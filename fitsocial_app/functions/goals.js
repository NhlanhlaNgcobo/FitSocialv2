/**
 * Personal goals: a target on one metric, over a week, a month, a year, or a
 * custom span.
 *
 *   users/{uid}/goals/{goalId}                   the goal, and its current period
 *   users/{uid}/goals/{goalId}/periods/{periodId} one record per period it ran
 *
 * Weekly, monthly and annual goals repeat: "four sessions a week" is a goal
 * for every week, not for one. Each period gets its own record, and the goal
 * document mirrors whichever period is current. A custom goal has one period
 * and ends -- completed if it was reached, expired if not.
 *
 * Progress is read from stats.js, never from anything the client writes. The
 * client may create a goal (through the callable below, which caps how many
 * are active) and archive it; target, progress and completion are the
 * server's, and firestore.rules closes them.
 *
 * Idempotency. A completion is counted when a period record flips from not
 * completed to completed, inside a transaction on that record. A trigger that
 * fires twice finds the flip already made the second time and counts nothing.
 * Completion is sticky within its period: deleting the run that tipped a week
 * over does not take the week's completion back, for the same reason a badge
 * is never revoked.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

const {
  db,
  dayKeyOf,
  offsetFor,
  addDays,
  daysBetween,
  badgeFactsFor,
  awardBadges,
} = require("./challenges")._internals;
const periods = require("./period_keys");
const remoteConfig = require("./remote_config");
const stats = require("./stats")._internals;

// --- Rules ------------------------------------------------------------------

const METRICS = ["steps", "active_minutes", "workouts", "meals_logged", "streak"];
const PERIODS = ["weekly", "monthly", "annual", "custom"];

/** Active goals one person may hold. A ceiling, not the free tier's limit. */
const MAX_ACTIVE_GOALS = 10;

/** The longest custom span. Bounds the daily reads one evaluation makes. */
const MAX_CUSTOM_DAYS = 92;

/** The largest target each metric accepts, per day of the period. */
const DAILY_CEILING = {
  steps: 100000,
  active_minutes: 1440,
  workouts: 20,
  meals_logged: 20,
  streak: 1,
};

/** The stats field each metric reads. */
function metricValue(periodStats, metric) {
  if (!periodStats) return 0;
  switch (metric) {
    case "steps":
      return periodStats.steps || 0;
    case "active_minutes":
      return periodStats.activeMinutes || 0;
    case "workouts":
      return periodStats.sessions || 0;
    case "meals_logged":
      return periodStats.meals || 0;
    case "streak":
      return periodStats.longestStreak || 0;
    default:
      return 0;
  }
}

/** The period of [goal] that holds [dayKey]: `{ id, startDayKey, endDayKey }`. */
function periodOf(goal, dayKey) {
  switch (goal.period) {
    case "weekly": {
      const id = periods.isoWeekIdOf(dayKey);
      const days = periods.weekDayKeys(id);
      return { id, startDayKey: days[0], endDayKey: days[6] };
    }
    case "monthly": {
      const id = periods.monthIdOf(dayKey);
      const days = periods.monthDayKeys(id);
      return { id, startDayKey: days[0], endDayKey: days[days.length - 1] };
    }
    case "annual": {
      const id = dayKey.slice(0, 4);
      return { id, startDayKey: `${id}-01-01`, endDayKey: `${id}-12-31` };
    }
    case "custom":
      return {
        id: "custom",
        startDayKey: goal.startDayKey,
        endDayKey: goal.endDayKey,
      };
    default:
      throw new Error(`Unknown goal period: ${goal.period}`);
  }
}

/** How many days a period of [goal] spans. */
function periodLength(goal, dayKey) {
  const { startDayKey, endDayKey } = periodOf(goal, dayKey);
  return daysBetween(startDayKey, endDayKey) + 1;
}

/**
 * Checks a new goal. Returns the cleaned goal, or throws with a message the
 * app can show.
 */
function validateGoal(input, todayKey) {
  const metric = input?.metric;
  const period = input?.period;
  const target = Number(input?.target);
  if (!METRICS.includes(metric)) throw new Error("Choose what to track.");
  if (!PERIODS.includes(period)) throw new Error("Choose a period.");
  if (!Number.isInteger(target) || target < 1) {
    throw new Error("The target must be a whole number above zero.");
  }

  const goal = { metric, period, target };
  if (period === "custom") {
    const { startDayKey, endDayKey } = input;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(startDayKey || "") ||
        !/^\d{4}-\d{2}-\d{2}$/.test(endDayKey || "")) {
      throw new Error("Choose a start and an end date.");
    }
    if (endDayKey < todayKey) throw new Error("The end date has passed.");
    const span = daysBetween(startDayKey, endDayKey) + 1;
    if (span < 1) throw new Error("The end date is before the start.");
    if (span > MAX_CUSTOM_DAYS) {
      throw new Error(`A custom goal can run for at most ${MAX_CUSTOM_DAYS} days.`);
    }
    // More than a week back would make "starting now" meaningless.
    if (daysBetween(startDayKey, todayKey) > 7) {
      throw new Error("The start date can be at most a week ago.");
    }
    goal.startDayKey = startDayKey;
    goal.endDayKey = endDayKey;
  }

  const days = periodLength(goal, todayKey);
  if (target > DAILY_CEILING[metric] * days) {
    throw new Error("That target is more than the period can hold.");
  }
  return goal;
}

/**
 * What evaluating one period of a goal changes. Pure.
 *
 * [record] is the stored period record, or null the first time. Returns the
 * record to write and whether this evaluation is the one that completed it.
 */
function evaluatePeriod(goal, period, value, record) {
  const wasCompleted = record?.completed === true;
  const completed = wasCompleted || value >= goal.target;
  return {
    record: {
      periodId: period.id,
      startDayKey: period.startDayKey,
      endDayKey: period.endDayKey,
      target: goal.target,
      progress: value,
      completed,
    },
    newlyCompleted: completed && !wasCompleted,
  };
}

// --- Reading progress --------------------------------------------------------

async function periodStats(uid, goal, period) {
  switch (goal.period) {
    case "weekly": {
      const snap = await stats.weeklyRef(uid, period.id).get();
      return snap.exists ? snap.data() : null;
    }
    case "monthly": {
      const snap = await stats.monthlyRef(uid, period.id).get();
      return snap.exists ? snap.data() : null;
    }
    case "annual": {
      const months = Array.from(
        { length: 12 },
        (_, i) => `${period.id}-${String(i + 1).padStart(2, "0")}`
      );
      const snaps = await Promise.all(
        months.map((m) => stats.monthlyRef(uid, m).get())
      );
      return stats.mergePeriods(snaps.map((s) => (s.exists ? s.data() : null)));
    }
    case "custom": {
      const dayKeys = [];
      for (let k = period.startDayKey; k <= period.endDayKey; k = addDays(k, 1)) {
        dayKeys.push(k);
      }
      return stats.rollUp(await stats.readDays(uid, dayKeys), dayKeys);
    }
    default:
      return null;
  }
}

// --- Writing -----------------------------------------------------------------

const serverTimestamp = () => admin.firestore.FieldValue.serverTimestamp();
const goalsOf = (uid) => db().collection("users").doc(uid).collection("goals");

/**
 * Evaluates one period of one goal and writes the result. [isCurrent] says
 * whether the goal document should mirror it.
 */
async function evaluateGoalPeriod(uid, goalRef, goal, period, isCurrent) {
  const value = metricValue(await periodStats(uid, goal, period), goal.metric);
  const recordRef = goalRef.collection("periods").doc(period.id);
  const userRef = db().collection("users").doc(uid);

  const newlyCompleted = await db().runTransaction(async (tx) => {
    const existing = await tx.get(recordRef);
    const outcome = evaluatePeriod(
      goal,
      period,
      value,
      existing.exists ? existing.data() : null
    );

    tx.set(
      recordRef,
      {
        ...outcome.record,
        ...(outcome.newlyCompleted ? { completedAt: serverTimestamp() } : {}),
        updatedAt: serverTimestamp(),
      },
      { merge: true }
    );

    const goalUpdate = {};
    if (isCurrent) {
      Object.assign(goalUpdate, {
        currentPeriodId: period.id,
        currentStartDayKey: period.startDayKey,
        currentEndDayKey: period.endDayKey,
        progress: value,
        completedCurrent: outcome.record.completed,
      });
    }
    if (outcome.newlyCompleted) {
      goalUpdate.completions = admin.firestore.FieldValue.increment(1);
      goalUpdate.lastCompletedPeriodId = period.id;
      tx.set(
        userRef,
        { goalCompletions: admin.firestore.FieldValue.increment(1) },
        { merge: true }
      );
    }
    if (Object.keys(goalUpdate).length > 0) {
      tx.set(goalRef, { ...goalUpdate, updatedAt: serverTimestamp() }, {
        merge: true,
      });
    }
    return outcome.newlyCompleted;
  });

  if (newlyCompleted) {
    await awardBadges(uid, await badgeFactsFor(uid, null), {
      goalId: goalRef.id,
      periodId: period.id,
    });
  }
  return { value, newlyCompleted };
}

/**
 * Brings one goal up to date as of [todayKey], and re-checks the period that
 * holds [changedDayKey] if a late log landed in one that has already ended.
 */
async function refreshGoal(uid, goalDoc, todayKey, changedDayKey = todayKey) {
  const goal = goalDoc.data();
  if (goal.status !== "active") return;

  if (goal.period === "custom") {
    const period = periodOf(goal, todayKey);
    const { newlyCompleted } = await evaluateGoalPeriod(
      uid, goalDoc.ref, goal, period, true
    );
    // A custom goal ends. It is settled the day after its last day, so the
    // last day's late logging still counts.
    if (todayKey > period.endDayKey) {
      const record = await goalDoc.ref.collection("periods").doc("custom").get();
      await goalDoc.ref.set(
        {
          status: record.get("completed") || newlyCompleted
            ? "completed"
            : "expired",
          updatedAt: serverTimestamp(),
        },
        { merge: true }
      );
    }
    return;
  }

  const current = periodOf(goal, todayKey);
  const changed = periodOf(goal, changedDayKey);
  if (changed.id !== current.id && changed.id < current.id) {
    await evaluateGoalPeriod(uid, goalDoc.ref, goal, changed, false);
  }
  await evaluateGoalPeriod(uid, goalDoc.ref, goal, current, true);
}

/** Every active goal of [uid], after a change to [dayKey]. */
async function refreshGoalsFor(uid, dayKey) {
  const values = await remoteConfig.values();
  if (values.f1_goals_challenges !== true) return;

  const active = await goalsOf(uid).where("status", "==", "active").get();
  if (active.empty) return;

  const todayKey = dayKeyOf(new Date(), await offsetFor(uid));
  for (const goalDoc of active.docs) {
    await refreshGoal(uid, goalDoc, todayKey, dayKey);
  }
}

stats.onDayChanged(refreshGoalsFor);

// --- Callables and schedule -------------------------------------------------

/**
 * Creates a goal. A callable rather than a client write so the active-goal cap
 * and the period arithmetic live in one place, and so the goal has real
 * progress the moment the app shows it.
 */
exports.createGoal = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  if (!(await remoteConfig.isOn("f1_goals_challenges"))) {
    throw new HttpsError("failed-precondition", "Goals are not available yet.");
  }

  const offset = await offsetFor(uid);
  const todayKey = dayKeyOf(new Date(), offset);

  let goal;
  try {
    goal = validateGoal(request.data, todayKey);
  } catch (error) {
    throw new HttpsError("invalid-argument", error.message);
  }

  const active = await goalsOf(uid).where("status", "==", "active").get();
  if (active.size >= MAX_ACTIVE_GOALS) {
    throw new HttpsError(
      "resource-exhausted",
      `You can have ${MAX_ACTIVE_GOALS} goals running at once. Archive one first.`
    );
  }

  const ref = goalsOf(uid).doc();
  await ref.set({
    ...goal,
    userId: uid,
    status: "active",
    progress: 0,
    completedCurrent: false,
    completions: 0,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  // Stats may never have been built for this period, if nothing was switched
  // on while the user was logging. Fill in the days of the current period
  // that have no stats yet -- at most a month's worth; an annual goal starts
  // from this month and the rest fills in as the year goes on.
  const period = periodOf(goal, todayKey);
  const fillFrom =
    goal.period === "annual" ? `${todayKey.slice(0, 7)}-01` : period.startDayKey;
  const days = [];
  for (let k = fillFrom; k <= todayKey && days.length < 31; k = addDays(k, 1)) {
    days.push(k);
  }
  const existing = await stats.readDays(uid, days);
  for (const dayKey of days) {
    if (!existing[dayKey]) await stats.refreshDay(uid, dayKey, offset);
  }

  const created = await ref.get();
  await refreshGoal(uid, created, todayKey);
  return { goalId: ref.id };
});

/**
 * Moves every active goal into its current period, and settles custom goals
 * that have ended. 02:30 Johannesburg: after the 02:00 lock, so the day that
 * just closed is final when it is judged.
 */
exports.rollGoalPeriods = onSchedule(
  { schedule: "30 2 * * *", timeZone: "Africa/Johannesburg" },
  async () => {
    if (!(await remoteConfig.isOn("f1_goals_challenges"))) return;
    const active = await db()
      .collectionGroup("goals")
      .where("status", "==", "active")
      .get();
    for (const goalDoc of active.docs) {
      const uid = goalDoc.get("userId");
      if (!uid) continue;
      try {
        const todayKey = dayKeyOf(new Date(), await offsetFor(uid));
        await refreshGoal(uid, goalDoc, todayKey);
      } catch (error) {
        // One bad goal must not stop the rest rolling over.
        console.error("goal rollover failed", { goalId: goalDoc.id, error });
      }
    }
  }
);

exports._internals = {
  METRICS,
  PERIODS,
  MAX_ACTIVE_GOALS,
  MAX_CUSTOM_DAYS,
  metricValue,
  periodOf,
  validateGoal,
  evaluatePeriod,
  refreshGoal,
  refreshGoalsFor,
};
