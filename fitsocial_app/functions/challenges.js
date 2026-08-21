/**
 * The challenge engine.
 *
 * Everything that decides an outcome lives here. The app may show a tick before
 * the server has confirmed it, but it may never write one: whether a day
 * counted, whether a streak survived, whether somebody was eliminated, what
 * they scored and what they earned are all written from this file and are
 * closed to clients in firestore.rules. That is not belt and braces — a
 * challenge whose result the participant can write is not a challenge.
 *
 * The rules implemented here are specified by, and must stay in step with,
 * lib/features/challenges/domain/ on the client. The Dart side is unit-tested
 * in test/challenge_domain_test.dart, and those tests are the shared
 * specification: this file is the second implementation of them, in Node,
 * because a Cloud Function cannot import Dart. When you change a threshold,
 * change it in both places and run that test file.
 */

const { onDocumentCreated, onDocumentWritten } = require(
  "firebase-functions/v2/firestore"
);
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

/**
 * Creates the default Admin app if nothing has yet, and hands back Firestore.
 *
 * The guard used to read `admin.apps.length === 0`, and that one line took
 * every automatic task on the tracker down with it for as long as it stood.
 * `admin.apps` is *every* app, not the default one -- and before a Firestore
 * trigger's handler is called, firebase-functions builds the snapshot behind
 * `event.data` through its own `getApp()`, which on finding no default app
 * initialises a **named** one of its own, `__FIREBASE_FUNCTIONS_SDK__`. So by
 * the time a handler in this file asked, `apps` held exactly one entry, the
 * guard concluded initialisation had already happened, skipped it, and the next
 * line asked for the *default* app and threw "The default Firebase app does not
 * exist".
 *
 * Every trigger here died on its first invocation, on every cold start, from
 * the moment the app was deployed. Water and reading kept working only because
 * they are the two the client writes and overlays for itself; the five the
 * engine computes -- workout, run, steps, nutrition, pulse -- and Early Worm,
 * which lives entirely in `onPulsePublished`, recorded nothing for anybody.
 *
 * So ask for the default app by name and let the miss tell you. `getApps()`,
 * the modular spelling, counts the same way and is the same bug -- see
 * race_entry_taps.js, which had it too.
 */
function ensureDefaultApp() {
  try {
    admin.app();
  } catch (_) {
    admin.initializeApp();
  }
}

/**
 * Firestore, memoised.
 *
 * `admin.firestore` is a namespace getter that rebuilds its function object on
 * every read -- requiring @google-cloud/firestore and reassembling the
 * v1/v1beta1 accessors each time. This is called dozens of times per
 * invocation, so it is worth holding on to.
 */
let firestoreInstance;

function db() {
  if (!firestoreInstance) {
    ensureDefaultApp();
    firestoreInstance = admin.firestore();
  }
  return firestoreInstance;
}

// --- Rules, mirrored from the Dart domain ---------------------------------

const PULSE_75_DURATION = 75;
const ELIMINATION_THRESHOLD = 3;
const FINALISATION_HOUR = 2;
const EARLY_WORM_START_HOUR = 4;
const EARLY_WORM_END_HOUR = 6;

/** Africa/Johannesburg, used when a user has no stored offset yet. */
const DEFAULT_OFFSET_MINUTES = 120;

/** The seven tasks: target, and what completing one pays. */
const TASKS = {
  workout: { target: 45, points: 15, auto: true },
  runWalk: { target: 10, points: 15, auto: true },
  steps: { target: 12000, points: 10, auto: true },
  nutrition: { target: 3, points: 10, auto: true },
  water: { target: 8, points: 5, auto: false },
  reading: { target: 10, points: 5, auto: false },
  pulse: { target: 1, points: 10, auto: true },
};

const TASK_KEYS = Object.keys(TASKS);

const DAY_COMPLETE_BASE_BONUS = 30;
const FINISHER_BONUS = 500;
const EARLY_WORM_POINTS = 10;
const EARLY_WORM_STREAK_BONUS = 25;
const EARLY_WORM_STREAK_INTERVAL = 7;
const GENERAL_WORKOUT_MINIMUM_MINUTES = 20;

/** General engagement points, with the daily cap that stops them being farmed. */
const GENERAL_RULES = {
  pulse_published: { points: 5, dailyCap: 3 },
  workout_logged: { points: 5, dailyCap: 2 },
  meal_logged: { points: 2, dailyCap: 3 },
  like_received: { points: 1, dailyCap: 20 },
  comment_given: { points: 1, dailyCap: 10 },
};

/** Statuses whose days are still being counted. */
const RUNNING_STATUSES = ["active", "at_risk", "danger"];

function streakMultiplier(streak) {
  if (streak >= 50) return 2.5;
  if (streak >= 21) return 2.0;
  if (streak >= 7) return 1.5;
  return 1.0;
}

// --- The clock ------------------------------------------------------------
//
// Offset minutes rather than an IANA zone, matching the client. The device is
// the only thing that knows what zone it is in, so it stamps its offset on the
// enrollment and this file reads it back. See ChallengeClock in Dart for why
// that trade is the right one for a launch market with no DST.

/** The wall clock a user reads at [instant], as a Date whose UTC fields are local. */
function wallClock(instant, offsetMinutes) {
  return new Date(instant.getTime() + offsetMinutes * 60000);
}

/** `YYYY-MM-DD` for [instant] in the user's zone. */
function dayKeyOf(instant, offsetMinutes) {
  return wallClock(instant, offsetMinutes).toISOString().slice(0, 10);
}

/** The instant at which the user's wall clock reads the given local parts. */
function instantOf(year, month, day, hour, offsetMinutes) {
  return new Date(Date.UTC(year, month - 1, day, hour) - offsetMinutes * 60000);
}

function parseDayKey(dayKey) {
  const [year, month, day] = dayKey.split("-").map(Number);
  return { year, month, day };
}

/** `[start, end)` — the instants bounding a local calendar day. */
function dayRange(dayKey, offsetMinutes) {
  const { year, month, day } = parseDayKey(dayKey);
  return {
    start: instantOf(year, month, day, 0, offsetMinutes),
    end: instantOf(year, month, day + 1, 0, offsetMinutes),
  };
}

/**
 * When a day stops accepting activity: 02:00 local the following morning.
 *
 * Not midnight. Late training is normal, and somebody who finishes at 23:50 and
 * saves the log at 00:10 has trained on the day they think they have. The grace
 * decides when the day *locks* — never which day owns the activity.
 */
function finalisesAt(dayKey, offsetMinutes) {
  const { year, month, day } = parseDayKey(dayKey);
  return instantOf(year, month, day + 1, FINALISATION_HOUR, offsetMinutes);
}

function addDays(dayKey, days) {
  const { year, month, day } = parseDayKey(dayKey);
  return new Date(Date.UTC(year, month - 1, day + days))
    .toISOString()
    .slice(0, 10);
}

function daysBetween(from, to) {
  const a = parseDayKey(from);
  const b = parseDayKey(to);
  return Math.round(
    (Date.UTC(b.year, b.month - 1, b.day) -
      Date.UTC(a.year, a.month - 1, a.day)) /
      86400000
  );
}

function isEarlyWorm(instant, offsetMinutes) {
  const hour = wallClock(instant, offsetMinutes).getUTCHours();
  return hour >= EARLY_WORM_START_HOUR && hour < EARLY_WORM_END_HOUR;
}

/** A user's stored clock offset, falling back to the launch market's. */
async function offsetFor(userId) {
  const user = await db().collection("users").doc(userId).get();
  const stored = user.get("utcOffsetMinutes");
  return Number.isInteger(stored) ? stored : DEFAULT_OFFSET_MINUTES;
}

// --- The points ledger ----------------------------------------------------

/**
 * Writes one award, at a document id derived from what earned it, and moves the
 * cached totals by the same amount in the same transaction.
 *
 * The derived id is the whole idempotency story. A Firestore trigger can fire
 * twice, a scheduled sweep can be retried, and a day can be recomputed on every
 * write of the day — none of which may pay twice. Two attempts to award the
 * same thing land on the same document, and the second is a no-op.
 *
 * The totals are incremented rather than re-summed, which matters more than it
 * looks. Summing the ledger costs one read per row, and the ledger only grows:
 * a Pulse 75 user writes about eight rows a day, so by the end of a run every
 * single task tick would have been re-reading six hundred documents to move a
 * number by fifteen. That is quadratic over a run, and it charges the most to
 * the users who stay the longest — precisely backwards.
 *
 * Incrementing is safe here only because it happens inside the transaction that
 * writes the row. The two either both land or neither does, so the total cannot
 * drift from the ledger it summarises. Do not move these increments outside it.
 *
 * Returns the amount actually credited: zero when it had already been paid.
 */
async function awardPoints(entryId, payload) {
  const ref = db().collection("pointsLedger").doc(entryId);
  const userRef = db().collection("users").doc(payload.userId);
  const enrollmentRef = payload.enrollmentId
    ? db().collection("challengeEnrollments").doc(payload.enrollmentId)
    : null;

  return db().runTransaction(async (tx) => {
    const existing = await tx.get(ref);
    if (existing.exists) return 0;

    const amount = payload.amount || 0;

    tx.set(ref, {
      ...payload,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Negative on a reversal, which decrements both totals by the same path —
    // there is no separate unwind to keep in step.
    tx.set(
      userRef,
      { totalPoints: admin.firestore.FieldValue.increment(amount) },
      { merge: true }
    );

    if (enrollmentRef) {
      tx.set(
        enrollmentRef,
        { pointsEarned: admin.firestore.FieldValue.increment(amount) },
        { merge: true }
      );
    }

    return amount;
  });
}

/**
 * Takes an award back, as a negative row rather than a deletion.
 *
 * Reversals exist because a task can un-complete: a meal is deleted, a GPS
 * activity turns out to be a car journey. The original row stays, so the
 * history reads as what happened rather than as what we wish had happened.
 */
async function reversePoints(originalId, reason) {
  const original = await db().collection("pointsLedger").doc(originalId).get();
  if (!original.exists) return 0;
  if (original.get("reversedAt")) return 0;

  const amount = original.get("amount") || 0;
  await awardPoints(`${originalId}__reversal`, {
    userId: original.get("userId"),
    eventType: "reversal",
    amount: -amount,
    sourceId: originalId,
    dayKey: original.get("dayKey") || null,
    enrollmentId: original.get("enrollmentId") || null,
    multiplier: 1,
    reason,
  });
  await original.ref.update({
    reversedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return -amount;
}

/**
 * A general engagement award, if the user is under the daily cap for it.
 *
 * The cap is counted from the ledger rather than from a counter, because the
 * ledger is already the record and a second counter is a second thing to get
 * wrong.
 */
async function awardGeneralPoints(userId, eventType, sourceId, dayKey) {
  const rule = GENERAL_RULES[eventType];
  if (!rule) return 0;

  const alreadyToday = await db()
    .collection("pointsLedger")
    .where("userId", "==", userId)
    .where("dayKey", "==", dayKey)
    .where("eventType", "==", eventType)
    .count()
    .get();

  if (alreadyToday.data().count >= rule.dailyCap) return 0;

  return awardPoints(`${userId}__${eventType}__${sourceId}`, {
    userId,
    eventType,
    amount: rule.points,
    sourceId,
    dayKey,
    enrollmentId: null,
    multiplier: 1,
  });
}

/**
 * Rebuilds a user's cached totals from the ledger.
 *
 * A repair tool, not part of the normal path. [awardPoints] keeps both totals
 * correct as it goes, so nothing here needs to run for the numbers to be right;
 * this exists for the day something has gone wrong anyway — a botched manual
 * edit, a backfill, a bug — and the ledger has to be treated as the record it
 * is. Reads every row for the user, so call it deliberately and never from a
 * trigger.
 */
async function recomputePointsTotals(userId) {
  const rows = await db()
    .collection("pointsLedger")
    .where("userId", "==", userId)
    .get();

  let total = 0;
  const byEnrollment = new Map();

  for (const row of rows.docs) {
    const amount = row.get("amount") || 0;
    total += amount;

    const enrollmentId = row.get("enrollmentId");
    if (enrollmentId) {
      byEnrollment.set(enrollmentId, (byEnrollment.get(enrollmentId) || 0) + amount);
    }
  }

  await db()
    .collection("users")
    .doc(userId)
    .set({ totalPoints: total }, { merge: true });

  for (const [enrollmentId, earned] of byEnrollment) {
    await db()
      .collection("challengeEnrollments")
      .doc(enrollmentId)
      .set({ pointsEarned: earned }, { merge: true });
  }

  return total;
}

// --- Badges ---------------------------------------------------------------

/**
 * Every badge condition, as a predicate over the same flat set of facts the
 * Dart side uses. Keys must match ChallengeBadge.key exactly.
 */
const BADGES = {
  PULSE_DAY_ONE: (f) => f.pulseDaysCompleted >= 1,
  PULSE_FIRST_WEEK: (f) => f.pulseLongestStreak >= 7,
  PULSE_LOCKED_IN: (f) => f.pulseLongestStreak >= 21,
  PULSE_IRON_MONTH: (f) => f.pulseLongestStreak >= 30,
  PULSE_HALFWAY: (f) => f.pulseDaysCompleted >= 38,
  PULSE_THE_GRIND: (f) => f.pulseDaysCompleted >= 50,
  PULSE_COMEBACK: (f) => f.pulseMissedDays > 0 && f.pulseCurrentStreak >= 14,
  PULSE_75_FINISHER: (f) => f.pulseCompleted,
  PULSE_FLAWLESS: (f) => f.pulseCompleted && f.pulseMissedDays === 0,
  EARLY_WORM: (f) => f.earlyWormTotalDays >= 1,
  EARLY_WORM_DAWN_PATROL: (f) => f.earlyWormLongestStreak >= 7,
  EARLY_WORM_SUNRISE: (f) => f.earlyWormLongestStreak >= 30,
  EARLY_WORM_4AM_CLUB: (f) => f.earlyWormLongestStreak >= 100,
  FIRST_PULSE: (f) => f.pulsesPublished >= 1,
  POINTS_CENTURY: (f) => f.totalPoints >= 100,
  POINTS_MACHINE: (f) => f.totalPoints >= 10000,
  SUPPORTER: (f) => f.reactionsGiven >= 100,
};

/** Badges that a second run can earn again, carried as a count. */
const REPEATABLE_BADGES = new Set(["PULSE_75_FINISHER", "PULSE_FLAWLESS"]);

/**
 * Awards every badge [facts] earns and the user does not already hold.
 *
 * Never revokes. A badge is the permanent half of the reward system: somebody
 * who reached day 50 and then lost the run still reached day 50, and taking the
 * badge back would be punishing them for the part they did do.
 */
async function awardBadges(userId, facts, context = {}) {
  const shelf = db().collection("users").doc(userId).collection("badges");
  const held = await shelf.get();
  const heldKeys = new Set(held.docs.map((doc) => doc.id));

  const awarded = [];
  for (const [badgeKey, condition] of Object.entries(BADGES)) {
    if (!condition(facts)) continue;
    if (heldKeys.has(badgeKey)) continue;

    await shelf.doc(badgeKey).set({
      badgeKey,
      userId,
      count: 1,
      context,
      awardedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    awarded.push(badgeKey);
  }
  return awarded;
}

/** Bumps the count on a repeatable badge the user has earned again. */
async function incrementRepeatableBadge(userId, badgeKey) {
  if (!REPEATABLE_BADGES.has(badgeKey)) return;
  const ref = db()
    .collection("users")
    .doc(userId)
    .collection("badges")
    .doc(badgeKey);
  const existing = await ref.get();
  if (!existing.exists) return;
  await ref.update({
    count: admin.firestore.FieldValue.increment(1),
  });
}

/** Assembles the fact set for a user, optionally against one run. */
async function badgeFactsFor(userId, enrollment) {
  const user = await db().collection("users").doc(userId).get();
  const earlyWorm = await db().collection("earlyWorm").doc(userId).get();

  return {
    pulseDaysCompleted: enrollment ? enrollment.daysCompleted || 0 : 0,
    pulseCurrentStreak: enrollment ? enrollment.currentStreak || 0 : 0,
    pulseLongestStreak: enrollment ? enrollment.longestStreak || 0 : 0,
    pulseMissedDays: enrollment ? enrollment.missedDaysTotal || 0 : 0,
    pulseCompleted: enrollment ? enrollment.status === "completed" : false,
    earlyWormLongestStreak: earlyWorm.exists
      ? earlyWorm.get("longestStreak") || 0
      : 0,
    earlyWormTotalDays: earlyWorm.exists ? earlyWorm.get("totalDays") || 0 : 0,
    totalPoints: user.get("totalPoints") || 0,
    pulsesPublished: user.get("pulsesPublished") || 0,
    reactionsGiven: user.get("reactionsGiven") || 0,
  };
}

// --- Reading the day ------------------------------------------------------

/**
 * Documents of [userId] whose own timestamp falls inside a local day.
 *
 * Two timestamp fields are queried and merged rather than one, because the logs
 * are not uniform: a run carries `startedAt` only when it was tracked, a
 * workout carries `loggedAt`, and everything carries the server's `createdAt`.
 * Querying only the preferred field would silently drop the older shape;
 * querying only `createdAt` would file a backdated entry on the wrong day.
 *
 * EVERY field named here needs its own `(authorId, <field>)` composite index in
 * firestore.indexes.json — an equality plus a range on a second field is not
 * served by the automatic single-field indexes. Adding a field to a `fields`
 * list without adding the index is not a slow query, it is a thrown
 * FAILED_PRECONDITION, and because this function sits under a `Promise.all`
 * that every trigger in the file funnels into, one missing index stops the day
 * document being written at all and leaves all seven tasks reading zero. That
 * is exactly how `workouts` and `meals` shipped missing their `createdAt`
 * pairs, and 75 Pulse recorded nothing for anybody until they were added.
 *
 * The **direction** counts too, and having the index is no protection at all
 * from getting it wrong. Every one of these indexes is declared descending,
 * because that is the order the app's own screens read the same collections in.
 * A range with no `orderBy` is implicitly ordered *ascending* on the range
 * field, and a descending composite cannot serve it — so these queries threw
 * FAILED_PRECONDITION against indexes that were present, live, and named in the
 * error as the thing to go and create. Hence the explicit descending `orderBy`
 * below. It does not change the answer — the caller counts and sums, and reads
 * through a Map that has already discarded order — it exists purely to name the
 * index this query is meant to use. Take it away and the same outage comes
 * back, with an error message pointing at an index that already exists.
 */
async function activityInDay(collection, userId, fields, start, end) {
  const found = new Map();

  for (const field of fields) {
    const snapshot = await db()
      .collection(collection)
      .where("authorId", "==", userId)
      .where(field, ">=", admin.firestore.Timestamp.fromDate(start))
      .where(field, "<", admin.firestore.Timestamp.fromDate(end))
      // Descending to match the declared index — see the note above. Not a
      // preference about ordering; the result is read order-insensitively.
      .orderBy(field, "desc")
      .get();

    for (const doc of snapshot.docs) {
      if (!found.has(doc.id)) found.set(doc.id, doc);
    }
  }

  return [...found.values()];
}

/**
 * The seven task figures for one day of one run.
 *
 * Read from the logs the app already keeps rather than from anything the
 * challenge writes for itself. That is what makes the automatic five
 * unfakeable: there is no field a client could set to claim them.
 */
async function readTaskValues(enrollmentRef, userId, dayKey, offsetMinutes) {
  const { start, end } = dayRange(dayKey, offsetMinutes);

  const [workouts, runs, meals, pulses, steps, manual] = await Promise.all([
    activityInDay("workouts", userId, ["loggedAt", "createdAt"], start, end),
    activityInDay("runs", userId, ["startedAt", "createdAt"], start, end),
    activityInDay("meals", userId, ["loggedAt", "createdAt"], start, end),
    activityInDay("pulses", userId, ["createdAt"], start, end),
    db().collection("dailySteps").doc(`${userId}_${dayKey}`).get(),
    enrollmentRef.collection("manual").doc(dayKey).get(),
  ]);

  const workoutMinutes = workouts.reduce(
    (sum, doc) => sum + (doc.get("durationMinutes") || 0),
    0
  );
  const runKilometres = runs.reduce(
    (sum, doc) => sum + (doc.get("distanceKm") || 0),
    0
  );

  return {
    values: {
      workout: workoutMinutes,
      runWalk: runKilometres,
      steps: steps.exists ? steps.get("steps") || 0 : 0,
      nutrition: meals.length,
      water: manual.exists ? manual.get("water") || 0 : 0,
      reading: manual.exists ? manual.get("reading") || 0 : 0,
      pulse: pulses.length,
    },
    sources: {
      workoutIds: workouts.map((doc) => doc.id),
      runIds: runs.map((doc) => doc.id),
      mealIds: meals.map((doc) => doc.id),
      pulseIds: pulses.map((doc) => doc.id),
      stepSource: steps.exists ? steps.get("source") || "unknown" : "none",
    },
  };
}

/** Which of the seven are met, and how many. */
function evaluate(values) {
  const met = {};
  for (const key of TASK_KEYS) {
    met[key] = (values[key] || 0) >= TASKS[key].target;
  }
  const completed = TASK_KEYS.filter((key) => met[key]).length;
  return {
    met,
    tasksCompleted: completed,
    // Seven of seven, or the day did not count. There is no partial credit
    // toward a streak — points are where a 5/7 day is recognised.
    complete: completed === TASK_KEYS.length,
    zeroDay: completed === 0,
  };
}

/**
 * Recomputes an open day and pays for any task that has just been met.
 *
 * Called from every activity trigger. Safe to run as often as it likes: the day
 * document is rewritten from the logs each time, and the task awards are
 * idempotent on their derived ids.
 */
async function recomputeOpenDay(enrollmentDoc, dayKey) {
  const enrollment = enrollmentDoc.data();
  const userId = enrollment.userId;
  const offset = enrollment.utcOffsetMinutes ?? DEFAULT_OFFSET_MINUTES;

  const dayRef = enrollmentDoc.ref.collection("days").doc(dayKey);
  const existing = await dayRef.get();
  // A finalised day is immutable. Activity that arrives after the lock does not
  // reopen it — that is the promise the 2 AM grace is making.
  if (existing.exists && existing.get("open") === false) return null;

  const { values, sources } = await readTaskValues(
    enrollmentDoc.ref,
    userId,
    dayKey,
    offset
  );
  const outcome = evaluate(values);

  await dayRef.set(
    {
      dayKey,
      userId,
      enrollmentId: enrollmentDoc.id,
      open: true,
      values,
      met: outcome.met,
      tasksCompleted: outcome.tasksCompleted,
      complete: outcome.complete,
      zeroDay: outcome.zeroDay,
      sources,
      computedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  // Task points land the moment the task is verified, which is what makes the
  // tick feel earned. The day-complete bonus waits for finalisation, because
  // until the day locks it can still be taken away.
  for (const key of TASK_KEYS) {
    if (!outcome.met[key]) continue;
    await awardPoints(`${enrollmentDoc.id}__task__${dayKey}__${key}`, {
      userId,
      eventType: "task",
      taskKey: key,
      amount: TASKS[key].points,
      sourceId: `${dayKey}:${key}`,
      dayKey,
      enrollmentId: enrollmentDoc.id,
      multiplier: 1,
    });
  }

  return outcome;
}

/** Recomputes today's open day for every running enrollment of a user. */
async function recomputeForUser(userId) {
  const enrollments = await db()
    .collection("challengeEnrollments")
    .where("userId", "==", userId)
    .where("status", "in", RUNNING_STATUSES)
    .get();

  for (const enrollmentDoc of enrollments.docs) {
    const offset =
      enrollmentDoc.get("utcOffsetMinutes") ?? DEFAULT_OFFSET_MINUTES;
    const today = dayKeyOf(new Date(), offset);
    const yesterday = addDays(today, -1);

    // Yesterday is recomputed too while it is still inside its grace window —
    // that is the entire point of the window, and without this a log saved at
    // 00:10 would be evaluated against the wrong day.
    for (const dayKey of [yesterday, today]) {
      if (daysBetween(enrollmentDoc.get("startDayKey"), dayKey) < 0) continue;
      await recomputeOpenDay(enrollmentDoc, dayKey);
    }
  }
}

// --- Finalisation ---------------------------------------------------------

/**
 * Locks one day and moves the run's counters.
 *
 * This is the state machine from EnrollmentProgress.applyFinalisedDay, and the
 * transitions must match it exactly. Terminal runs are left alone: a retried
 * sweep must not push an eliminated user further down or resurrect a finished
 * one.
 */
async function finaliseDay(enrollmentDoc, dayKey) {
  const enrollment = enrollmentDoc.data();
  if (!RUNNING_STATUSES.includes(enrollment.status)) return;

  const userId = enrollment.userId;
  const outcome = (await recomputeOpenDay(enrollmentDoc, dayKey)) ||
    evaluate({});

  const dayRef = enrollmentDoc.ref.collection("days").doc(dayKey);

  // Any task paid for during the day that did not survive to the lock is taken
  // back — a meal deleted at 23:00 should not leave its ten points behind.
  for (const key of TASK_KEYS) {
    if (outcome.met[key]) continue;
    await reversePoints(
      `${enrollmentDoc.id}__task__${dayKey}__${key}`,
      "task not met at finalisation"
    );
  }

  const complete = outcome.complete;
  const previousStreak = enrollment.currentStreak || 0;
  const previousMissed = enrollment.consecutiveMissedDays || 0;

  let next;
  if (complete) {
    const streak = previousStreak + 1;
    const daysCompleted = (enrollment.daysCompleted || 0) + 1;
    next = {
      daysCompleted,
      currentStreak: streak,
      longestStreak: Math.max(enrollment.longestStreak || 0, streak),
      consecutiveMissedDays: 0,
      missedDaysTotal: enrollment.missedDaysTotal || 0,
      status:
        daysCompleted >= PULSE_75_DURATION ? "completed" : "active",
    };
  } else {
    const missed = previousMissed + 1;
    next = {
      daysCompleted: enrollment.daysCompleted || 0,
      currentStreak: 0,
      longestStreak: enrollment.longestStreak || 0,
      consecutiveMissedDays: missed,
      missedDaysTotal: (enrollment.missedDaysTotal || 0) + 1,
      status:
        missed >= ELIMINATION_THRESHOLD
          ? "eliminated"
          : missed === 2
            ? "danger"
            : "at_risk",
    };
  }

  let bonus = 0;
  if (complete) {
    const multiplier = streakMultiplier(next.currentStreak);
    bonus = await awardPoints(
      `${enrollmentDoc.id}__day_complete_bonus__${dayKey}`,
      {
        userId,
        eventType: "day_complete_bonus",
        amount: Math.round(DAY_COMPLETE_BASE_BONUS * multiplier),
        sourceId: dayKey,
        dayKey,
        enrollmentId: enrollmentDoc.id,
        multiplier,
      }
    );

    if (next.status === "completed") {
      bonus += await awardPoints(`${enrollmentDoc.id}__finisher_bonus`, {
        userId,
        eventType: "finisher_bonus",
        amount: FINISHER_BONUS,
        sourceId: enrollmentDoc.id,
        dayKey,
        enrollmentId: enrollmentDoc.id,
        multiplier: 1,
      });
    }
  }

  await dayRef.set(
    {
      open: false,
      finalisedAt: admin.firestore.FieldValue.serverTimestamp(),
      bonusAwarded: bonus,
    },
    { merge: true }
  );

  await enrollmentDoc.ref.set(
    {
      ...next,
      lastEvaluatedDayKey: dayKey,
      lastQualifiedDayKey: complete
        ? dayKey
        : enrollment.lastQualifiedDayKey || null,
      progressPercent: Math.round(
        (next.daysCompleted / PULSE_75_DURATION) * 100
      ),
      completedAt:
        next.status === "completed"
          ? admin.firestore.FieldValue.serverTimestamp()
          : enrollment.completedAt || null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );


  const facts = await badgeFactsFor(userId, { ...enrollment, ...next });
  // A repeat finish bumps the count on the badge already held rather than
  // adding a second one, so a profile reads "Finisher x2".
  if (next.status === "completed") {
    await incrementRepeatableBadge(userId, "PULSE_75_FINISHER");
    if (facts.pulseMissedDays === 0) {
      await incrementRepeatableBadge(userId, "PULSE_FLAWLESS");
    }
  }
  await awardBadges(userId, facts, {
    enrollmentId: enrollmentDoc.id,
    dayKey,
  });
}

/**
 * The sweep. Hourly, because 2 AM happens at a different instant in every zone
 * and an hourly pass catches each one within the hour.
 */
async function finaliseDueDays() {
  const now = new Date();
  const running = await db()
    .collection("challengeEnrollments")
    .where("status", "in", RUNNING_STATUSES)
    .get();

  let finalised = 0;

  for (const enrollmentDoc of running.docs) {
    const offset = enrollmentDoc.get("utcOffsetMinutes") ?? DEFAULT_OFFSET_MINUTES;
    const startDayKey = enrollmentDoc.get("startDayKey");
    const lastEvaluated = enrollmentDoc.get("lastEvaluatedDayKey");

    let cursor = lastEvaluated ? addDays(lastEvaluated, 1) : startDayKey;

    // Walk forward one day at a time. A phone that was off for a week comes
    // back to a run that resolves day by day, in order, rather than to a single
    // jump that would skip the elimination it earned on the way.
    let guard = 0;
    while (
      now >= finalisesAt(cursor, offset) &&
      guard < PULSE_75_DURATION + 30
    ) {
      // Re-read: the previous iteration may have eliminated or completed it.
      const fresh = await enrollmentDoc.ref.get();
      if (!RUNNING_STATUSES.includes(fresh.get("status"))) break;

      await finaliseDay(fresh, cursor);
      finalised += 1;
      cursor = addDays(cursor, 1);
      guard += 1;
    }
  }

  return finalised;
}

// --- Early Worm -----------------------------------------------------------

/**
 * Credits a Pulse published between 4 and 6 in the morning.
 *
 * The window is checked against the server's own timestamp converted into the
 * user's stored zone, never against a time the client claims. A device clock is
 * the one input a user can set to whatever they like.
 */
async function creditEarlyWorm(userId, publishedAt, pulseId) {
  const offset = await offsetFor(userId);
  if (!isEarlyWorm(publishedAt, offset)) return false;

  const dayKey = dayKeyOf(publishedAt, offset);
  const ref = db().collection("earlyWorm").doc(userId);

  const streak = await db().runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const previous = snapshot.exists ? snapshot.data() : {};

    // One morning is one credit however many Pulses it carried.
    if (previous.lastQualifiedDayKey === dayKey) return null;

    const continues =
      previous.lastQualifiedDayKey &&
      daysBetween(previous.lastQualifiedDayKey, dayKey) === 1;
    const currentStreak = continues ? (previous.currentStreak || 0) + 1 : 1;

    const next = {
      userId,
      currentStreak,
      longestStreak: Math.max(previous.longestStreak || 0, currentStreak),
      totalDays: (previous.totalDays || 0) + 1,
      lastQualifiedDayKey: dayKey,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    tx.set(ref, next, { merge: true });
    return next;
  });

  if (!streak) return false;

  await awardPoints(`${userId}__early_worm__${dayKey}`, {
    userId,
    eventType: "early_worm",
    amount: EARLY_WORM_POINTS,
    sourceId: pulseId,
    dayKey,
    enrollmentId: null,
    multiplier: 1,
  });

  if (streak.currentStreak % EARLY_WORM_STREAK_INTERVAL === 0) {
    await awardPoints(`${userId}__early_worm_streak__${dayKey}`, {
      userId,
      eventType: "early_worm_streak",
      amount: EARLY_WORM_STREAK_BONUS,
      sourceId: String(streak.currentStreak),
      dayKey,
      enrollmentId: null,
      multiplier: 1,
    });
  }

  await awardBadges(userId, await badgeFactsFor(userId, null), {
    pulseId,
    dayKey,
  });
  return true;
}

// --- Triggers -------------------------------------------------------------

/** Every log type that can move a task, wired to the same recompute. */
function activityTrigger(path) {
  return onDocumentCreated(path, async (event) => {
    const userId = event.data?.get("authorId");
    if (!userId) return;
    await recomputeForUser(userId);
  });
}

exports.onWorkoutLogged = onDocumentCreated(
  "workouts/{workoutId}",
  async (event) => {
    const doc = event.data;
    const userId = doc?.get("authorId");
    if (!userId) return;

    const offset = await offsetFor(userId);
    const dayKey = dayKeyOf(new Date(), offset);

    // A workout has to be a real session to earn general points. Twenty minutes
    // is the floor; below it this is a note to self, not training.
    if ((doc.get("durationMinutes") || 0) >= GENERAL_WORKOUT_MINIMUM_MINUTES) {
      await awardGeneralPoints(userId, "workout_logged", doc.id, dayKey);
    }
    await recomputeForUser(userId);
  }
);

exports.onRunLogged = activityTrigger("runs/{runId}");

exports.onMealLogged = onDocumentCreated("meals/{mealId}", async (event) => {
  const doc = event.data;
  const userId = doc?.get("authorId");
  if (!userId) return;

  const offset = await offsetFor(userId);
  await awardGeneralPoints(
    userId,
    "meal_logged",
    doc.id,
    dayKeyOf(new Date(), offset)
  );
  await recomputeForUser(userId);
});

exports.onPulsePublished = onDocumentCreated(
  "pulses/{pulseId}",
  async (event) => {
    const doc = event.data;
    const userId = doc?.get("authorId");
    if (!userId) return;

    const publishedAt = doc.get("createdAt")?.toDate?.() || new Date();
    const offset = await offsetFor(userId);

    await db()
      .collection("users")
      .doc(userId)
      .set(
        { pulsesPublished: admin.firestore.FieldValue.increment(1) },
        { merge: true }
      );

    await awardGeneralPoints(
      userId,
      "pulse_published",
      doc.id,
      dayKeyOf(publishedAt, offset)
    );

    // One post can credit both Early Worm and the Pulse 75 task. That is
    // deliberate cross-promotion, not double-counting: they are two different
    // challenges asking for the same thing at the same time of day.
    await creditEarlyWorm(userId, publishedAt, doc.id);
    await recomputeForUser(userId);
  }
);

exports.onDailyStepsWritten = onDocumentWritten(
  "dailySteps/{docId}",
  async (event) => {
    const userId = event.data?.after?.get("userId");
    if (!userId) return;
    await recomputeForUser(userId);
  }
);

exports.onManualTaskWritten = onDocumentWritten(
  "challengeEnrollments/{enrollmentId}/manual/{dayKey}",
  async (event) => {
    const enrollmentDoc = await db()
      .collection("challengeEnrollments")
      .doc(event.params.enrollmentId)
      .get();
    if (!enrollmentDoc.exists) return;
    if (!RUNNING_STATUSES.includes(enrollmentDoc.get("status"))) return;

    await recomputeOpenDay(enrollmentDoc, event.params.dayKey);
  }
);

/**
 * Reactions given, which feed the Supporter badge and the reacting user's
 * points. The document id is the reactor, so this counts giving rather than
 * receiving; the post's author is paid separately below.
 */
exports.onPostReaction = onDocumentCreated(
  "likes/{postId}/users/{userId}",
  async (event) => {
    const reactorId = event.params.userId;
    const offset = await offsetFor(reactorId);
    const dayKey = dayKeyOf(new Date(), offset);

    await db()
      .collection("users")
      .doc(reactorId)
      .set(
        { reactionsGiven: admin.firestore.FieldValue.increment(1) },
        { merge: true }
      );

    const post = await db().collection("posts").doc(event.params.postId).get();
    const authorId = post.get("authorId");
    if (authorId && authorId !== reactorId) {
      const authorOffset = await offsetFor(authorId);
      await awardGeneralPoints(
        authorId,
        "like_received",
        `${event.params.postId}:${reactorId}`,
        dayKeyOf(new Date(), authorOffset)
      );
    }

    await awardBadges(reactorId, await badgeFactsFor(reactorId, null), {
      postId: event.params.postId,
      dayKey,
    });
  }
);

exports.onPulseComment = onDocumentCreated(
  "pulses/{pulseId}/comments/{commentId}",
  async (event) => {
    const authorId = event.data?.get("authorId");
    if (!authorId) return;

    const offset = await offsetFor(authorId);
    await awardGeneralPoints(
      authorId,
      "comment_given",
      `${event.params.pulseId}:${event.params.commentId}`,
      dayKeyOf(new Date(), offset)
    );
  }
);

/**
 * The finalisation sweep.
 *
 * Hourly rather than daily: 02:00 arrives at a different instant in every zone,
 * and an hourly pass closes each user's day within the hour of their own
 * cutoff. Retries are safe — a finalised day is skipped on the next pass.
 */
exports.finaliseChallengeDays = onSchedule(
  {
    schedule: "every 60 minutes",
    // Overrides the africa-south1 default set in index.js, and cannot be
    // changed to match it: Cloud Scheduler has no presence in Johannesburg.
    //
    //   Location 'africa-south1' is not a valid location.
    //
    // So the two scheduled jobs are the one part of this backend that has to
    // sit away from the database. They read across regions as a result, which
    // is a cost worth paying rather than the alternatives — there is no way to
    // schedule work in africa-south1 at all. Nothing user-facing waits on
    // these, so the distance costs time nobody is watching.
    //
    // Pinned explicitly rather than left to the global default so a deploy does
    // not fail every time somebody touches this file.
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "512MiB",
    retryCount: 3,
  },
  async () => {
    const count = await finaliseDueDays();
    console.log(`finaliseChallengeDays: closed ${count} day(s)`);
  }
);

/**
 * How many people are running each challenge. Aggregated on a schedule so the
 * detail screen costs one document read instead of a count query per open.
 */
exports.aggregateChallengeStats = onSchedule(
  // us-central1 for the same reason as finaliseChallengeDays above: Cloud
  // Scheduler is not available in africa-south1.
  { schedule: "every 60 minutes", region: "us-central1", timeoutSeconds: 120 },
  async () => {
    const running = await db()
      .collection("challengeEnrollments")
      .where("challengeKey", "==", "pulse75")
      .where("status", "in", RUNNING_STATUSES)
      .count()
      .get();

    const completed = await db()
      .collection("challengeEnrollments")
      .where("challengeKey", "==", "pulse75")
      .where("status", "==", "completed")
      .count()
      .get();

    await db().collection("challengeStats").doc("pulse75").set({
      challengeKey: "pulse75",
      activeCount: running.data().count,
      completedCount: completed.data().count,
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
);

// Exported for the unit tests, which exercise the rules without Firestore.
//
// awardPoints and recomputePointsTotals need a Firestore to run against, so
// their tests point at the emulator. recomputePointsTotals is also the repair
// path itself — reachable from an admin script or `firebase functions:shell`
// when a total has to be rebuilt from the ledger by hand.
exports._internals = {
  // The database accessor is exposed for one reason: test/admin_app_init.js
  // checks that it still works after firebase-functions has installed an app
  // of its own, which is the failure that broke every trigger in this file.
  db,
  awardPoints,
  recomputePointsTotals,
  dayKeyOf,
  dayRange,
  finalisesAt,
  addDays,
  daysBetween,
  isEarlyWorm,
  evaluate,
  streakMultiplier,
  TASKS,
  TASK_KEYS,
  BADGES,
  DAY_COMPLETE_BASE_BONUS,
  FINISHER_BONUS,
  PULSE_75_DURATION,
  ELIMINATION_THRESHOLD,
};
