/**
 * Up Next (Build 11, F3): one to three suggestions for today, worked out by
 * plain rules from the stats the app already keeps.
 *
 *   users/{uid}/upNext/{dayKey}   today's suggestions, and the ids the user
 *                                 dismissed. Server-written, except that the
 *                                 owner may add to `dismissed` (firestore.rules).
 *
 * No AI: every suggestion here is a sentence with numbers filled in, so it
 * costs nothing, cannot say anything it was not written to say, and is tested
 * line by line. The rules, in the order they win a place:
 *
 *   streak     a run of active days that ends tonight unless today is active
 *   goal       a weekly goal close enough to finish today
 *   meal       somebody who logs meals most days has logged none today
 *   week       an active person with no session yet this week, by Wednesday
 *
 * Nothing is suggested to somebody with no data in the last fortnight: there
 * is nothing to base a suggestion on, and a stranger's nudge is noise.
 *
 * Dismissal is per day and final: a dismissed id is left out of every
 * rebuild until the day changes, which is also what keeps a card from
 * coming back after it was swiped away.
 *
 * Rebuilt when today's stats change (a listener on stats.js, after goals have
 * updated) and when the app asks, because two rules depend on the time of day
 * and nothing else would fire at noon.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const {
  db,
  dayKeyOf,
  offsetFor,
  addDays,
  daysBetween,
} = require("./challenges")._internals;
const periods = require("./period_keys");
const remoteConfig = require("./remote_config");
const stats = require("./stats")._internals;

const FLAG = "f3_up_next";

const MAX_SUGGESTIONS = 3;

/** How far back the rules look. Long enough to see a habit and a streak. */
const LOOKBACK_DAYS = 14;

/** Steps a brisk walk covers in a minute, for "a 20-minute walk". */
const STEPS_PER_MINUTE = 100;

/** Gaps a single day can reasonably close. */
const MAX_STEP_GAP = 6000;
const MAX_MINUTE_GAP = 60;
const MAX_MEAL_GAP = 3;

/** From when a missing session puts a streak at risk, local time. */
const STREAK_FROM_HOUR = 15;
/** The window in which a missing meal log is worth a mention, local time. */
const MEAL_FROM_HOUR = 12;
const MEAL_UNTIL_HOUR = 21;
/** Days out of the last seven with meals logged that make it a habit. */
const MEAL_HABIT_DAYS = 3;

// --- Pure -------------------------------------------------------------------

const formatThousands = (n) =>
  String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ",");

const hasData = (day) =>
  Boolean(day && (day.hasSteps || day.active || (day.meals || 0) > 0));

/** Consecutive active days ending yesterday. */
function streakBefore(todayKey, days) {
  let streak = 0;
  for (let key = addDays(todayKey, -1); days[key]?.active; key = addDays(key, -1)) {
    streak += 1;
  }
  return streak;
}

function streakRule({ todayKey, hour, days }) {
  if (hour < STREAK_FROM_HOUR || days[todayKey]?.active) return null;
  const streak = streakBefore(todayKey, days);
  if (streak < 2) return null;
  return {
    id: "streak",
    kind: "streak",
    title: `Keep your ${streak}-day streak going`,
    reason: "Any session today keeps it alive. The day ends at midnight.",
    route: "/create",
  };
}

/** A weekly goal's suggestion, or null when today cannot close the gap. */
function goalSuggestion(goal, todayKey) {
  if (goal.period !== "weekly" || goal.completedCurrent) return null;
  if (!goal.currentEndDayKey || daysBetween(todayKey, goal.currentEndDayKey) < 0) {
    return null;
  }
  const target = Number(goal.target) || 0;
  const progress = Number(goal.progress) || 0;
  const gap = target - progress;
  if (target <= 0 || gap <= 0) return null;

  const base = { id: `goal:${goal.id}`, kind: "goal", route: "/goals", gap: gap / target };
  switch (goal.metric) {
    case "steps": {
      if (gap > MAX_STEP_GAP) return null;
      const minutes = Math.max(5, Math.ceil(gap / STEPS_PER_MINUTE / 5) * 5);
      return {
        ...base,
        title: `${formatThousands(gap)} steps to your weekly goal`,
        reason: `A ${minutes}-minute walk gets you there.`,
      };
    }
    case "active_minutes":
      if (gap > MAX_MINUTE_GAP) return null;
      return {
        ...base,
        title: `${gap} active minutes to your weekly goal`,
        reason: "One session today gets you there.",
      };
    case "workouts":
      if (gap !== 1) return null;
      return {
        ...base,
        title: "One session from your weekly goal",
        reason: "Fit one in and this week's goal is done.",
      };
    case "meals_logged":
      if (gap > MAX_MEAL_GAP) return null;
      return {
        ...base,
        title: `${gap} more meal${gap === 1 ? "" : "s"} to log this week`,
        reason: "Log today's meals as you go to reach your goal.",
      };
    default:
      return null;
  }
}

function goalRules({ todayKey, goals }) {
  return goals
    .map((goal) => goalSuggestion(goal, todayKey))
    .filter(Boolean)
    .sort((a, b) => a.gap - b.gap);
}

function mealRule({ todayKey, hour, days }) {
  if (hour < MEAL_FROM_HOUR || hour >= MEAL_UNTIL_HOUR) return null;
  if ((days[todayKey]?.meals || 0) > 0) return null;
  let loggedDays = 0;
  for (let i = 1; i <= 7; i++) {
    if ((days[addDays(todayKey, -i)]?.meals || 0) > 0) loggedDays += 1;
  }
  if (loggedDays < MEAL_HABIT_DAYS) return null;
  return {
    id: "meal",
    kind: "meal",
    title: "Log today's meals",
    reason: `You've logged meals on ${loggedDays} of the last 7 days. Keep the log going.`,
    route: "/meal-tracking",
  };
}

function weekRule({ todayKey, days }) {
  const weekStart = periods.weekStartDayKey(periods.isoWeekIdOf(todayKey));
  const dayOfWeek = daysBetween(weekStart, todayKey) + 1;
  if (dayOfWeek < 3) return null;
  for (let key = weekStart; daysBetween(key, todayKey) >= 0; key = addDays(key, 1)) {
    if ((days[key]?.sessions || 0) > 0) return null;
  }
  // Only for somebody who trains: a session in the fortnight before the week.
  let before = false;
  for (let i = 1; i <= LOOKBACK_DAYS; i++) {
    if ((days[addDays(weekStart, -i)]?.sessions || 0) > 0) before = true;
  }
  if (!before) return null;
  return {
    id: "week",
    kind: "week",
    title: "Get this week started",
    reason: "No sessions logged yet this week. Even 15 minutes counts.",
    route: "/create",
  };
}

/**
 * Today's suggestions, best first, at most [MAX_SUGGESTIONS], none of them
 * dismissed. Every input is plain data; `days` maps day keys to daily stats
 * and may be sparse.
 */
function suggestionsFor({ todayKey, hour, days, goals = [], dismissed = [] }) {
  const recent = Array.from({ length: LOOKBACK_DAYS }, (_, i) => addDays(todayKey, -i));
  if (!recent.some((key) => hasData(days[key]))) return [];

  const context = { todayKey, hour, days, goals };
  const candidates = [
    streakRule(context),
    ...goalRules(context),
    mealRule(context),
    weekRule(context),
  ].filter(Boolean);

  const skip = new Set(dismissed);
  return candidates
    .filter((s) => !skip.has(s.id))
    .slice(0, MAX_SUGGESTIONS)
    .map(({ id, kind, title, reason, route }) => ({ id, kind, title, reason, route }));
}

// --- Firestore --------------------------------------------------------------

const upNextRef = (uid, dayKey) =>
  db().collection("users").doc(uid).collection("upNext").doc(dayKey);

/** Rebuilds [uid]'s suggestions for today. Returns today's key. */
async function refreshFor(uid, now = new Date()) {
  const offset = await offsetFor(uid);
  const todayKey = dayKeyOf(now, offset);
  const hour = new Date(now.getTime() + offset * 60000).getUTCHours();
  const dayKeys = Array.from({ length: LOOKBACK_DAYS + 7 }, (_, i) => addDays(todayKey, -i));

  const [days, goalsSnap, existing] = await Promise.all([
    stats.readDays(uid, dayKeys),
    db().collection("users").doc(uid).collection("goals").where("status", "==", "active").get(),
    upNextRef(uid, todayKey).get(),
  ]);
  const dismissed = existing.exists ? existing.get("dismissed") || [] : [];
  const suggestions = suggestionsFor({
    todayKey,
    hour,
    days,
    goals: goalsSnap.docs.map((doc) => ({ ...doc.data(), id: doc.id })),
    dismissed,
  });

  // Merge, so `dismissed` -- the one field the owner writes -- is left alone.
  await upNextRef(uid, todayKey).set(
    {
      dayKey: todayKey,
      suggestions,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return todayKey;
}

/** After a change to [dayKey]'s stats: today's suggestions may have moved. */
async function onDayChanged(uid, dayKey) {
  if (!(await remoteConfig.isOn(FLAG))) return;
  const offset = await offsetFor(uid);
  if (dayKey !== dayKeyOf(new Date(), offset)) return;
  await refreshFor(uid);
}

// Registered after goals.js (see index.js), so a goal's progress is updated
// before the gap to it is read here.
stats.onDayChanged(onDayChanged);

// --- Exports ----------------------------------------------------------------

/**
 * The app opening home. Cheap -- a few document reads, no model -- and
 * throttled on the phone, so the time-of-day rules are current without a
 * schedule fanning out to everybody.
 */
exports.refreshUpNext = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  if (!(await remoteConfig.isOn(FLAG))) {
    throw new HttpsError("failed-precondition", "Up Next is switched off.");
  }
  return { dayKey: await refreshFor(uid) };
});

exports._internals = {
  suggestionsFor,
  streakBefore,
  goalSuggestion,
  refreshFor,
  onDayChanged,
  MAX_SUGGESTIONS,
};
