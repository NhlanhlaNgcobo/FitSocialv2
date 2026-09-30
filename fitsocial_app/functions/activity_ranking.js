/**
 * Activity challenges: the arithmetic and the ordering, with no Firestore.
 *
 * An activity challenge counts one metric -- steps, active minutes, sessions
 * or meals logged -- between two dates, in one of three modes:
 *
 *   cumulative  most in total wins
 *   target      first to reach `target` wins; everyone who reaches it has done
 *               it, and the rest are ordered by how close they got
 *   streak      a day counts when it reaches `target`; the longest run of
 *               counted days wins
 *
 * The daily figures come from dailyStats (stats.js), and always the rankable
 * ones: steps typed in by hand, and any day over a Remote Config ceiling,
 * never move a place on a board. The owner still sees their raw numbers on
 * their own screens.
 *
 * Each participant's days are their own calendar days, not the creator's.
 * That is forced rather than chosen: the phone records steps per local day,
 * and there is no way to re-cut a day's steps at somebody else's midnight. In
 * one timezone -- South Africa has one -- the two are the same thing.
 *
 * Joining late counts from the day you joined. A challenge that started a
 * week ago does not hand a newcomer a week of walking they did before they
 * were on it; everybody is measured over the days they were actually in.
 *
 * Ties are broken, in order, by who got to their final figure on an earlier
 * day, then by who joined first, then by user id -- so a board never
 * reshuffles tied rows between refreshes.
 */

const ACTIVITY_TYPE = "activity";

/** The dailyStats field each metric reads. Rankable figures only. */
const METRIC_FIELDS = Object.freeze({
  steps: "rankableSteps",
  active_minutes: "rankableActiveMinutes",
  workouts: "sessions",
  meals_logged: "meals",
});

const MODES = Object.freeze(["cumulative", "target", "streak"]);

/** The longest an activity challenge may run. Bounds the join backfill. */
const MAX_ACTIVITY_DAYS = 92;

function nextDay(dayKey) {
  const [y, m, d] = dayKey.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + 1)).toISOString().slice(0, 10);
}

/** A day's contribution to [metric], from its dailyStats (or none). */
function dayValue(dayStats, metric) {
  const field = METRIC_FIELDS[metric];
  const n = Number(dayStats?.[field]);
  return field && Number.isFinite(n) && n > 0 ? Math.round(n) : 0;
}

/** The first day that counts for somebody who joined on [joinedDayKey]. */
function effectiveStart(challenge, joinedDayKey) {
  if (!joinedDayKey) return challenge.startDayKey;
  return joinedDayKey > challenge.startDayKey
    ? joinedDayKey
    : challenge.startDayKey;
}

/**
 * One participant's standing from their day values.
 *
 * [dayValues] maps day key to that day's figure and may hold days outside the
 * window; only [from, challenge.endDayKey] counts.
 */
function standingFrom(challenge, dayValues, from) {
  const target = Number(challenge.target) || 0;
  const keys = Object.keys(dayValues || {})
    .filter((key) => key >= from && key <= challenge.endDayKey)
    .sort();

  let total = 0;
  let targetReachedDayKey = null;
  let lastGainDayKey = null;
  let qualifiedDays = 0;
  let longestStreak = 0;
  let currentStreak = 0;
  let previousQualified = null;

  for (const key of keys) {
    const value = Math.max(0, Math.round(Number(dayValues[key]) || 0));
    if (value <= 0) continue;
    total += value;
    lastGainDayKey = key;
    if (targetReachedDayKey == null && target > 0 && total >= target) {
      targetReachedDayKey = key;
    }
    if (target > 0 && value >= target) {
      qualifiedDays += 1;
      currentStreak =
        previousQualified != null && nextDay(previousQualified) === key
          ? currentStreak + 1
          : 1;
      if (currentStreak > longestStreak) longestStreak = currentStreak;
      previousQualified = key;
    }
  }

  return {
    total,
    lastGainDayKey,
    targetReachedDayKey: challenge.mode === "target" ? targetReachedDayKey : null,
    qualifiedDays: challenge.mode === "streak" ? qualifiedDays : 0,
    longestStreak: challenge.mode === "streak" ? longestStreak : 0,
  };
}

/** Earlier day key first; a missing one sorts last. */
function earlierFirst(a, b) {
  if (a === b) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a < b ? -1 : 1;
}

/**
 * Orders two participants of a challenge in [mode]. Both are the shape
 * `rankableOf` builds: total, longestStreak, targetReachedDayKey,
 * lastGainDayKey, joinedAtMillis, userId.
 */
function compareActivity(mode) {
  return (a, b) => {
    if (mode === "target") {
      const reached = earlierFirst(a.targetReachedDayKey, b.targetReachedDayKey);
      if (reached !== 0) return reached;
    }
    if (mode === "streak" && a.longestStreak !== b.longestStreak) {
      return b.longestStreak - a.longestStreak;
    }
    if (a.total !== b.total) return b.total - a.total;

    const gained = earlierFirst(a.lastGainDayKey, b.lastGainDayKey);
    // Only a tiebreak between equal totals; with nothing gained at all both
    // are null and fall through.
    if (gained !== 0 && a.total > 0) return gained;

    const aj = a.joinedAtMillis;
    const bj = b.joinedAtMillis;
    if (aj != null && bj != null && aj !== bj) return aj - bj;
    if (aj != null && bj == null) return -1;
    if (aj == null && bj != null) return 1;
    return a.userId < b.userId ? -1 : a.userId > b.userId ? 1 : 0;
  };
}

/** The comparable shape of an activity participant document. */
function rankableActivity(doc) {
  const joined = doc.get("joinedAt");
  return {
    userId: doc.id,
    status: doc.get("status") || "active",
    total: doc.get("total") || 0,
    longestStreak: doc.get("longestStreak") || 0,
    targetReachedDayKey: doc.get("targetReachedDayKey") || null,
    lastGainDayKey: doc.get("lastGainDayKey") || null,
    joinedAtMillis: joined?.toMillis?.() ?? null,
    rank: doc.get("rank") || 0,
    ref: doc.ref,
  };
}

/**
 * Checks an activity challenge before it is created. Returns null when it is
 * fine, or the reason it is not. Mirrors the create rule in firestore.rules,
 * which is the check that actually holds.
 */
function validateActivityChallenge(c) {
  if (!Object.keys(METRIC_FIELDS).includes(c.metric)) return "metric";
  if (!MODES.includes(c.mode)) return "mode";
  const needsTarget = c.mode !== "cumulative";
  if (needsTarget && !(Number.isInteger(c.target) && c.target > 0)) {
    return "target";
  }
  if (!needsTarget && c.target != null) return "target";
  return null;
}

module.exports = {
  ACTIVITY_TYPE,
  METRIC_FIELDS,
  MODES,
  MAX_ACTIVITY_DAYS,
  dayValue,
  effectiveStart,
  standingFrom,
  compareActivity,
  rankableActivity,
  validateActivityChallenge,
};
