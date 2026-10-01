/**
 * The friends leaderboard's projection: the handful of numbers one person's
 * week or month may be ranked on, in a document the people who follow them are
 * allowed to read.
 *
 *   leaderboardEntries/{uid}_{periodId}
 *
 * Why a projection at all. `weeklyStats` and `monthlyStats` are health records
 * -- raw steps, hand-typed steps, meals, heart rate, a figure for every day --
 * and firestore.rules keeps them to their owner on purpose. A board needs other
 * people's figures, so rather than opening those documents up, this file copies
 * out the four numbers a board actually ranks and nothing else:
 *
 *   steps          rankableSteps, so hand-typed steps are already gone
 *   activeMinutes  rankableActiveMinutes
 *   sessions       runs, rides, hikes and workouts, one each
 *   streak         the longest run of active days inside the period
 *
 * No meals (a food diary is nobody else's business), no heart rate, no per-day
 * series, no raw step count. Somebody who follows you learns what you walked
 * this week, not which days you walked it on.
 *
 * Integrity is settled upstream: stats.js writes a `rankable` figure beside
 * each raw one, zero for a day over the Remote Config ceiling and net of
 * anything typed in by hand, and those are the two fields copied here. An
 * implausible day is excluded from every board without this file knowing the
 * rule. Sessions and streaks have no ceiling to breach -- they count things the
 * user logged one at a time, which is not the shape bad data arrives in.
 *
 * Opting out. `users/{uid}.leaderboardOptOut` takes somebody off every board:
 * no entry is written while it is set, and the entries already written are
 * deleted when it goes on. Nothing is left behind to rank.
 *
 * Dark until switched on: nothing is written while `f6_leaderboards` is off, so
 * a build with the flag down has no projection to leak. The one thing that does
 * happen with the flag down is a purge -- see [onUserForLeaderboard].
 */

const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

const { db, dayKeyOf, offsetFor } = require("./challenges")._internals;
const periods = require("./period_keys");
const remoteConfig = require("./remote_config");
const stats = require("./stats")._internals;

const FLAG = "f6_leaderboards";

/** How many entries one purge pass deletes. */
const BATCH_LIMIT = 300;

const serverTimestamp = () => admin.firestore.FieldValue.serverTimestamp();

const entries = () => db().collection("leaderboardEntries");

const entryRef = (uid, periodId) => entries().doc(`${uid}_${periodId}`);

function toInt(value) {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.round(n) : 0;
}

// --- Pure ------------------------------------------------------------------

/**
 * The entry a period's stats project to, or null when the period holds nothing
 * worth ranking.
 *
 * Null rather than a row of zeros, because a week nobody logged anything in is
 * not a last place -- it is somebody who was not playing. They are back on the
 * board the moment they log something.
 *
 * `activeDays` comes along as the tiebreak and as the one piece of context a
 * row shows ("4 active days"). It is a count, not a calendar: which days is
 * still private.
 */
function projectionFrom(periodStats) {
  if (!periodStats) return null;
  const entry = {
    steps: toInt(periodStats.rankableSteps),
    activeMinutes: toInt(periodStats.rankableActiveMinutes),
    sessions: toInt(periodStats.sessions),
    streak: toInt(periodStats.longestStreak),
    activeDays: toInt(periodStats.activeDays),
  };
  const ranksOnSomething =
    entry.steps > 0 ||
    entry.activeMinutes > 0 ||
    entry.sessions > 0 ||
    entry.streak > 0;
  return ranksOnSomething ? entry : null;
}

// --- Firestore -------------------------------------------------------------

/** Whether [uid] has taken themselves off the boards. */
async function isOptedOut(uid) {
  const snap = await db().collection("users").doc(uid).get();
  return snap.data()?.leaderboardOptOut === true;
}

/**
 * Writes or clears one period's entry for [uid]. Returns what it wrote, or null
 * when it cleared.
 *
 * A full `set`, not a merge: an entry is a projection of a stats document and
 * has no history of its own, so the last write is the whole truth.
 */
async function writeEntry(uid, periodId, scope, periodStats) {
  const ref = entryRef(uid, periodId);
  const projection = projectionFrom(periodStats);
  if (projection == null) {
    // A period that used to hold something and no longer does -- a deleted
    // workout, a corrected step count -- leaves the board rather than keeping
    // its old figures.
    await ref.delete();
    return null;
  }
  await ref.set({
    userId: uid,
    periodId,
    scope,
    ...projection,
    updatedAt: serverTimestamp(),
  });
  return projection;
}

/** The week and month entries for the period [dayKey] falls in. */
async function refreshPeriodsOf(uid, dayKey) {
  const weekId = periods.isoWeekIdOf(dayKey);
  const monthId = periods.monthIdOf(dayKey);

  if (await isOptedOut(uid)) {
    await Promise.all([
      entryRef(uid, weekId).delete(),
      entryRef(uid, monthId).delete(),
    ]);
    return;
  }

  const [week, month] = await Promise.all([
    stats.weeklyRef(uid, weekId).get(),
    stats.monthlyRef(uid, monthId).get(),
  ]);
  await Promise.all([
    writeEntry(uid, weekId, "week", week.exists ? week.data() : null),
    writeEntry(uid, monthId, "month", month.exists ? month.data() : null),
  ]);
}

/**
 * Keeps [uid]'s entries in step with a day that changed.
 *
 * Registered on stats.js rather than on the logs themselves, so it runs after
 * the week and month documents it reads have been rebuilt. There is no window
 * in which a board shows yesterday's total.
 */
async function refreshFor(uid, dayKey) {
  if (!(await remoteConfig.isOn(FLAG))) return;
  await refreshPeriodsOf(uid, dayKey);
}

stats.onDayChanged(refreshFor);

/** Deletes every entry [uid] has, however many periods they span. */
async function purgeEntries(uid) {
  const firestore = db();
  let removed = 0;
  // Re-queried rather than paged with a cursor: each pass deletes what it read,
  // so the next "first N matches" are the ones still there. The same shape as
  // the account purge in account_deletion.js.
  for (;;) {
    const snapshot = await entries()
      .where("userId", "==", uid)
      .limit(BATCH_LIMIT)
      .get();
    if (snapshot.empty) break;

    const batch = firestore.batch();
    for (const doc of snapshot.docs) batch.delete(doc.ref);
    await batch.commit();
    removed += snapshot.size;
    if (snapshot.size < BATCH_LIMIT) break;
  }
  return removed;
}

/** Puts [uid] back on the current week's and month's boards. */
async function rebuildCurrent(uid) {
  const todayKey = dayKeyOf(new Date(), await offsetFor(uid));
  await refreshPeriodsOf(uid, todayKey);
}

// --- Triggers --------------------------------------------------------------

/**
 * The opt-out switch, acted on.
 *
 * On `users/{uid}` because that is where the preference lives, and it returns
 * on the first comparison for every other profile edit -- a changed avatar must
 * not cost a leaderboard write.
 *
 * Switching the boards off is honoured whether or not `f6_leaderboards` is on.
 * Entries written while the flag was up outlive it coming down, and somebody
 * asking to be taken off is owed that regardless of what the console says this
 * week. Switching back on only rebuilds when the feature is live: with it off
 * there is no board to appear on, and the next logged day writes the entries
 * anyway.
 *
 * Opting back in restores the current week and month, not every period ever
 * ranked. The finished boards somebody sat out stay sat out -- quietly
 * reinstating months-old figures is not what "put me back on" means.
 */
exports.onUserForLeaderboard = onDocumentWritten(
  "users/{uid}",
  async (event) => {
    const before = event.data?.before?.data?.() || null;
    const after = event.data?.after?.data?.() || null;
    const was = before?.leaderboardOptOut === true;
    const now = after?.leaderboardOptOut === true;
    if (was === now) return;

    const uid = event.params.uid;
    if (now) {
      await purgeEntries(uid);
      return;
    }
    if (await remoteConfig.isOn(FLAG)) await rebuildCurrent(uid);
  }
);

exports._internals = {
  FLAG,
  projectionFrom,
  entryRef,
  writeEntry,
  refreshPeriodsOf,
  refreshFor,
  purgeEntries,
  rebuildCurrent,
  isOptedOut,
};
