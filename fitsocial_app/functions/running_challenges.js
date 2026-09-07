/**
 * The running-challenge engine.
 *
 * The second challenge model in this app, and deliberately its own file.
 * `challenges.js` is Pulse 75 and Early Worm: fixed, personal, seven
 * all-or-nothing tasks a day, one participant per run. This is the other kind —
 * somebody creates a challenge with a distance goal and a date range, other
 * people join it, and a leaderboard says who is doing best.
 *
 * The two engines share the clock and nothing else. In particular this file
 * adds a **second** trigger on `runs/{runId}` rather than editing
 * `onRunLogged`, so that no change here can move a Pulse 75 streak. Two
 * functions may listen to one document path; they are separate deployments with
 * separate retries, and neither can see the other fail.
 *
 * The rules implemented here are specified by, and must stay in step with,
 * lib/features/challenges/domain/running_challenge.dart. The Dart side is
 * unit-tested in test/running_challenge_domain_test.dart and those cases are
 * the shared specification; test/running_challenges.test.js runs the same
 * examples against this side. When you change a rule, change it in both places
 * and run both files.
 *
 * What the server owns, and the client may never write:
 *   total distance, completed days, current and longest streak, completion
 *   percentage, rank, participant count, challenge status.
 * firestore.rules refuses all of them. A challenge whose participants can write
 * their own rank is not a challenge.
 */

const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

// The database accessor from the Pulse 75 engine, reused rather than rebuilt.
//
// This is not tidiness. `db()` there carries the fix for the bug that took the
// whole challenge system down: a guard reading `admin.apps.length === 0`
// concludes initialisation has happened when firebase-functions has installed a
// *named* app of its own, and the next line then asks for the default app and
// throws. Writing a second guard here would be writing the same bug a second
// time. The day-key helpers come from the same place for the same reason — one
// implementation of "which day did that happen on", not two that can drift.
const {
  db,
  dayKeyOf,
  addDays,
  daysBetween,
} = require("./challenges")._internals;

// --- Rules, mirrored from the Dart domain ---------------------------------

/** What a day must clear to count when a challenge does not say. */
const DEFAULT_DAILY_QUALIFYING_KM = 1;

/**
 * How many people one challenge may hold.
 *
 * A ceiling rather than a business rule. `rewriteRanks` below is linear in the
 * number of participants and runs whenever anybody's numbers move; this is the
 * point past which that stops being cheap. Mirrored as
 * kMaxChallengeParticipants in the Dart domain.
 */
const MAX_PARTICIPANTS = 500;

/**
 * The longest a challenge may run.
 *
 * Bounds `recomputeParticipant`, which reads one document per qualifying day.
 * Mirrored as kMaxChallengeDays.
 */
const MAX_CHALLENGE_DAYS = 180;

/** Participant states whose activity still counts and still ranks. */
const RANKED_STATUSES = ["active", "completed"];

/** Participant states that count toward a challenge's advertised size. */
const COUNTED_STATUSES = ["active", "completed"];

/** The only challenge type this engine knows how to score. */
const RUNNING_TYPE = "running";

const serverTimestamp = () => admin.firestore.FieldValue.serverTimestamp();

// --- Reading a run --------------------------------------------------------

/**
 * When a run happened, as an instant.
 *
 * `startedAt` when the run was tracked, `createdAt` otherwise — the same pair
 * and the same precedence `challenges.js` uses to bucket a run into a day. A
 * tracked run carries the moment the user pressed start; a manually entered one
 * only has the moment it was saved, and filing that under the save time is the
 * best available answer.
 */
function runInstant(data) {
  const started = data?.startedAt;
  const created = data?.createdAt;
  const at = started?.toDate?.() || created?.toDate?.() || null;
  return at instanceof Date && !Number.isNaN(at.getTime()) ? at : null;
}

function runDistanceKm(data) {
  const km = Number(data?.distanceKm);
  return Number.isFinite(km) && km > 0 ? km : 0;
}

function runDurationSeconds(data) {
  const seconds = Number(data?.durationSeconds);
  return Number.isFinite(seconds) && seconds > 0 ? Math.round(seconds) : 0;
}

// --- Metrics --------------------------------------------------------------

/**
 * Every consistency metric, derived from a participant's day records.
 *
 * The Node half of RunningChallengeMetrics.fromDays. Re-derived from the days
 * rather than accumulated, which is the whole reason a deletion can be undone
 * correctly: there is no running total to unwind, only a set of facts to read
 * again. `days` may arrive in any order and is sparse — a day with no running
 * has no document at all.
 */
function metricsFromDays(days) {
  const sorted = [...days].sort((a, b) => (a.dayKey < b.dayKey ? -1 : 1));

  let totalDistanceKm = 0;
  let runCount = 0;
  let completedDays = 0;
  let longestStreak = 0;
  let running = 0;
  let currentStreak = 0;
  let previousQualified = null;
  let lastQualifiedDayKey = null;

  for (const day of sorted) {
    totalDistanceKm += day.distanceKm || 0;
    runCount += day.runCount || 0;
    if (!day.qualified) continue;

    completedDays += 1;
    // Measured between qualifying days rather than by walking the calendar:
    // the days in between may have no documents at all.
    const continues =
      previousQualified !== null &&
      daysBetween(previousQualified, day.dayKey) === 1;
    running = continues ? running + 1 : 1;
    if (running > longestStreak) longestStreak = running;
    // The current streak is the run ending at the latest qualifying day, so it
    // is whatever the run is when the loop runs out.
    currentStreak = running;
    previousQualified = day.dayKey;
    lastQualifiedDayKey = day.dayKey;
  }

  return {
    totalDistanceKm,
    runCount,
    completedDays,
    currentStreak,
    longestStreak,
    lastQualifiedDayKey,
  };
}

/** Progress toward a goal, capped at 100. Zero rather than infinity at goal 0. */
function completionPercentage(totalKm, goalKm) {
  if (!(goalKm > 0)) return 0;
  const percent = (totalKm / goalKm) * 100;
  return percent > 100 ? 100 : percent;
}

/**
 * The leaderboard order — consistency first, distance second.
 *
 * The Node half of compareParticipants. Ranking on total kilometres alone would
 * hand the top of the board to one enormous Sunday run over somebody who turned
 * up every day, which is the opposite of what this challenge is for.
 *
 * The last two keys do no ranking work. They exist so that participants who are
 * equal on the first three come back in the same order on every pass — a board
 * that reshuffles tied rows between refreshes looks broken even when it is
 * correct — and so that a document the server has not stamped a `joinedAt` on
 * yet cannot make the comparator inconsistent with itself.
 */
function compareParticipants(a, b) {
  if (a.completedDays !== b.completedDays) {
    return b.completedDays - a.completedDays;
  }
  if (a.totalDistanceKm !== b.totalDistanceKm) {
    return b.totalDistanceKm - a.totalDistanceKm;
  }
  if (a.completionPercentage !== b.completionPercentage) {
    return b.completionPercentage - a.completionPercentage;
  }

  const aJoined = a.joinedAtMillis;
  const bJoined = b.joinedAtMillis;
  if (aJoined !== null && bJoined !== null && aJoined !== bJoined) {
    return aJoined - bJoined;
  }
  if (aJoined !== null && bJoined === null) return -1;
  if (aJoined === null && bJoined !== null) return 1;

  return a.userId < b.userId ? -1 : a.userId > b.userId ? 1 : 0;
}

/** The comparable shape [compareParticipants] wants, from a participant doc. */
function rankableOf(doc) {
  const joined = doc.get("joinedAt");
  return {
    userId: doc.id,
    status: doc.get("status") || "active",
    completedDays: doc.get("completedDays") || 0,
    totalDistanceKm: doc.get("totalDistanceKm") || 0,
    completionPercentage: doc.get("completionPercentage") || 0,
    joinedAtMillis: joined?.toMillis?.() ?? null,
    rank: doc.get("rank") || 0,
    ref: doc.ref,
  };
}

// --- Attribution ----------------------------------------------------------

/**
 * Recomputes one participant's day from the attributions filed against it.
 *
 * The day document is a summary, never a source: it is rebuilt by reading the
 * attribution records back, so running this twice produces the same answer and
 * running it after a deletion produces the corrected one. A day that ends up
 * with nothing in it is deleted rather than written as zero, which keeps the
 * streak recompute reading only days that happened.
 */
async function recomputeDay(challengeDoc, userId, dayKey) {
  const challenge = challengeDoc.data();
  const dailyMinimum =
    Number(challenge.dailyMinimumKm) > 0
      ? Number(challenge.dailyMinimumKm)
      : DEFAULT_DAILY_QUALIFYING_KM;

  const attributions = await challengeDoc.ref
    .collection("attributions")
    .where("userId", "==", userId)
    .where("dayKey", "==", dayKey)
    .get();

  const dayRef = challengeDoc.ref
    .collection("participants")
    .doc(userId)
    .collection("days")
    .doc(dayKey);

  if (attributions.empty) {
    await dayRef.delete();
    return;
  }

  let distanceKm = 0;
  let durationSeconds = 0;
  for (const doc of attributions.docs) {
    distanceKm += doc.get("distanceKm") || 0;
    durationSeconds += doc.get("durationSeconds") || 0;
  }

  await dayRef.set(
    {
      dayKey,
      userId,
      distanceKm,
      durationSeconds,
      runCount: attributions.size,
      qualified: distanceKm >= dailyMinimum,
      computedAt: serverTimestamp(),
    },
    { merge: true }
  );
}

/**
 * Rebuilds a participant's standing from their day records.
 *
 * Returns whether the participant has just crossed the goal for the first time,
 * so the caller can send the one notification that is worth sending.
 */
async function recomputeParticipant(challengeDoc, userId) {
  const challenge = challengeDoc.data();
  const participantRef = challengeDoc.ref
    .collection("participants")
    .doc(userId);

  const [participant, dayDocs] = await Promise.all([
    participantRef.get(),
    participantRef.collection("days").limit(MAX_CHALLENGE_DAYS + 1).get(),
  ]);
  if (!participant.exists) return { finishedNow: false };

  const days = dayDocs.docs.map((doc) => ({
    dayKey: doc.id,
    distanceKm: doc.get("distanceKm") || 0,
    runCount: doc.get("runCount") || 0,
    qualified: doc.get("qualified") === true,
  }));

  const metrics = metricsFromDays(days);
  const percent = completionPercentage(
    metrics.totalDistanceKm,
    Number(challenge.goalValueKm) || 0
  );

  const durationSeconds = dayDocs.docs.reduce(
    (sum, doc) => sum + (doc.get("durationSeconds") || 0),
    0
  );

  const wasFinished = (participant.get("completionPercentage") || 0) >= 100;
  const finishedNow = !wasFinished && percent >= 100;

  await participantRef.set(
    {
      ...metrics,
      totalDurationSeconds: durationSeconds,
      completionPercentage: percent,
      // Reaching the goal marks the participant finished but does not stop
      // counting: a finisher who keeps running keeps adding days, and their
      // streak is still theirs. Somebody who left stays left.
      status:
        finishedNow && participant.get("status") === "active"
          ? "completed"
          : participant.get("status") || "active",
      updatedAt: serverTimestamp(),
    },
    { merge: true }
  );

  return { finishedNow };
}

/**
 * Rewrites every participant's rank on one challenge.
 *
 * Sorted in memory rather than by an ordered query, for two reasons. It is the
 * same comparator the Dart side uses, so client and server cannot disagree
 * about an order that a four-key `orderBy` would have to express as a composite
 * index; and it avoids that index entirely. The read is bounded by
 * MAX_PARTICIPANTS, which is what makes that affordable.
 *
 * Only rows whose rank actually changed are written. Without that this would be
 * MAX_PARTICIPANTS writes on every logged run, most of them setting a field to
 * the value it already held.
 */
async function rewriteRanks(challengeDoc) {
  const participants = await challengeDoc.ref
    .collection("participants")
    .limit(MAX_PARTICIPANTS)
    .get();

  const ranked = participants.docs
    .map(rankableOf)
    .filter((p) => RANKED_STATUSES.includes(p.status))
    .sort(compareParticipants);

  const batch = db().batch();
  let changed = 0;

  ranked.forEach((participant, index) => {
    const rank = index + 1;
    if (participant.rank === rank) return;
    batch.set(participant.ref, { rank }, { merge: true });
    changed += 1;
  });

  // Anybody who left or declined keeps no rank. Leaving the old number behind
  // would show them a position they are no longer holding.
  for (const doc of participants.docs) {
    const status = doc.get("status") || "active";
    if (RANKED_STATUSES.includes(status)) continue;
    if ((doc.get("rank") || 0) === 0) continue;
    batch.set(doc.ref, { rank: 0 }, { merge: true });
    changed += 1;
  }

  if (changed > 0) await batch.commit();
  return changed;
}

/**
 * Files one run against one challenge, or takes it back.
 *
 * `runData` is null when the run has been deleted, or when it no longer
 * qualifies — an edit that moved it outside the challenge window is a removal
 * as far as this challenge is concerned, and goes down the same path.
 *
 * The attribution document's id is the run's id, which IS the
 * UNIQUE(challenge_id, activity_id) constraint: two attempts to file the same
 * run land on the same document, so a retry, a duplicated sync or a repeated
 * request cannot count it twice. Firestore has no unique-column constraint, and
 * a derived id is the only thing that can enforce one — the same trick
 * `usernames/{username}` and `pointsLedger` already rely on.
 */
async function applyRunToChallenge(challengeDoc, userId, runId, runData) {
  const challenge = challengeDoc.data();
  if (challenge.type !== RUNNING_TYPE) return false;
  // A finished or cancelled challenge is frozen. Activity arriving afterwards
  // does not reopen it — that is what "results remain stable" means.
  if (challenge.status !== "active") return false;

  const attributionRef = challengeDoc.ref.collection("attributions").doc(runId);
  const existing = await attributionRef.get();

  let target = null;
  if (runData) {
    const at = runInstant(runData);
    const distanceKm = runDistanceKm(runData);
    if (at && distanceKm > 0) {
      const offset = Number.isInteger(challenge.utcOffsetMinutes)
        ? challenge.utcOffsetMinutes
        : 0;
      const dayKey = dayKeyOf(at, offset);
      // Judged in the challenge's own zone, not the runner's. Everybody on one
      // leaderboard is measured against one calendar or "completed days" stops
      // meaning a single thing.
      if (dayKey >= challenge.startDayKey && dayKey <= challenge.endDayKey) {
        target = {
          activityId: runId,
          userId,
          dayKey,
          distanceKm,
          durationSeconds: runDurationSeconds(runData),
          activityType: "run",
        };
      }
    }
  }

  if (!target && !existing.exists) return false;

  // The idempotent no-op. A trigger that fired twice on an unchanged document
  // stops here, before any write.
  if (
    target &&
    existing.exists &&
    existing.get("dayKey") === target.dayKey &&
    existing.get("distanceKm") === target.distanceKm &&
    existing.get("durationSeconds") === target.durationSeconds
  ) {
    return false;
  }

  // An edit that moved a run to another date touches two days: the one it left
  // and the one it joined. Both have to be rebuilt or the old one keeps a
  // distance that is no longer there.
  const touched = new Set();
  if (existing.exists) touched.add(existing.get("dayKey"));
  if (target) touched.add(target.dayKey);

  if (target) {
    await attributionRef.set(
      { ...target, attributedAt: serverTimestamp() },
      { merge: true }
    );
  } else {
    await attributionRef.delete();
  }

  for (const dayKey of touched) {
    await recomputeDay(challengeDoc, userId, dayKey);
  }

  const { finishedNow } = await recomputeParticipant(challengeDoc, userId);
  await rewriteRanks(challengeDoc);

  if (finishedNow) {
    await notifyChallengeCompleted(challengeDoc, userId);
  }
  return true;
}

/**
 * Every challenge a run should be filed against, and the filing of it.
 *
 * The participant records are the index: a collection-group query for this
 * user's active memberships answers "which challenges is this person on"
 * without reading a challenge that has nothing to do with them.
 */
async function attributeRun(runId, runData, ownerId) {
  const userId = ownerId || runData?.authorId;
  if (!userId) return 0;

  const memberships = await db()
    .collectionGroup("participants")
    .where("userId", "==", userId)
    .where("status", "in", RANKED_STATUSES)
    .get();

  let applied = 0;
  for (const membership of memberships.docs) {
    const challengeRef = membership.ref.parent.parent;
    if (!challengeRef) continue;

    const challengeDoc = await challengeRef.get();
    if (!challengeDoc.exists) continue;

    if (await applyRunToChallenge(challengeDoc, userId, runId, runData)) {
      applied += 1;
    }
  }
  return applied;
}

// --- Notifications --------------------------------------------------------

/**
 * One notification, in the shape the app's own repository writes.
 *
 * Denormalised actor name and avatar, same as a like or a follow, so the
 * notifications list renders from the query it already runs instead of a
 * profile read per row.
 *
 * [id] is the document id, and giving one is what makes an event idempotent —
 * the same deterministic-id discipline NotificationIds keeps on the client, for
 * the same reason. Writing over a row rather than adding a second one is also
 * what makes a resent invitation resurface: the payload is rewritten whole, so
 * createdAt moves and the row lifts back to the top of the recipient's list
 * instead of the app quietly stacking up five copies of one invitation.
 */
async function notify(recipientId, actorId, type, extra, id) {
  if (!recipientId || recipientId === actorId) return;

  const actor = await db().collection("users").doc(actorId).get();
  const actorName =
    actor.get("displayName") || actor.get("username") || "Someone";
  const avatar = actor.get("photoUrl") || actor.get("avatarUrl") || "";

  const inbox = db()
    .collection("users")
    .doc(recipientId)
    .collection("notifications");

  const payload = {
    type,
    actorId,
    actorName,
    ...(avatar ? { actorAvatarUrl: avatar } : {}),
    ...extra,
    createdAt: serverTimestamp(),
    read: false,
  };

  await (id ? inbox.doc(id).set(payload) : inbox.add(payload));
}

async function notifyChallengeCompleted(challengeDoc, userId) {
  // From the challenge's creator, so the row reads as somebody telling you —
  // there is no system actor in this app's notification model.
  await notify(
    userId,
    challengeDoc.get("creatorId"),
    "challengeCompleted",
    {
      challengeId: challengeDoc.id,
      challengeTitle: challengeDoc.get("title") || "",
    },
    `challengeCompleted_${challengeDoc.id}`
  );
}

/**
 * Whether two stored timestamps are the same moment.
 *
 * Spelled out because these are Timestamp objects, not numbers: `===` compares
 * identity, and the before and after views of one unchanged field are two
 * separate objects. Two missing values count as the same moment; one missing
 * and one present do not, which is what makes the first resend of an
 * invitation written before `invitedAt` existed still count as a resend.
 */
function sameInstant(before, after) {
  if (!before || !after) return !before && !after;
  if (typeof before.isEqual === "function") return before.isEqual(after);
  // Anything that can say when it is, compared by that. Falling back to the
  // objects themselves would read two different moments as one, because two
  // plain objects stringify identically.
  const millis = (value) =>
    typeof value?.toMillis === "function" ? value.toMillis() : value;
  return millis(before) === millis(after);
}

// --- Participant bookkeeping ----------------------------------------------

/**
 * Keeps a challenge's advertised size honest.
 *
 * Counted rather than incremented. An increment has to be paired perfectly with
 * every status transition in both directions, and there are five statuses; a
 * count query is one read and cannot drift.
 */
async function recountParticipants(challengeRef) {
  const counted = await challengeRef
    .collection("participants")
    .where("status", "in", COUNTED_STATUSES)
    .count()
    .get();

  await challengeRef.set(
    { participantCount: counted.data().count, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

/**
 * Copies one participant row into `users/{uid}/challengeMemberships/{id}`.
 *
 * The index behind "which challenges am I on, and who has invited me?".
 *
 * That question used to be asked as a collection-group query across every
 * challenge's participants, and it could never be authorised: on a
 * collection-group list, security rules can see neither the document nor the
 * path wildcards, so the only rule that lets such a query through is one that
 * lets ANY signed-in caller list EVERY participant row in the database —
 * private challenge rosters included. The query was therefore refused for
 * everybody, and the hub's challenge list rendered empty from the day it
 * shipped. See the collection-group note in firestore.rules.
 *
 * Written under the person rather than under the challenge, exactly as their
 * notifications are, so reading it is an owner-only query on their own
 * subcollection and the rule has nothing to qualify.
 *
 * A copy, and only ever a copy: the participant row under the challenge stays
 * the record of truth. A mirror that fails to write leaves a challenge missing
 * from one list until the next write to that row puts it back — which is why
 * this runs on EVERY write rather than only on the ones that change status.
 */
async function mirrorMembership(challengeId, userId, snapshot) {
  const ref = db()
    .collection("users")
    .doc(userId)
    .collection("challengeMemberships")
    .doc(challengeId);

  if (!snapshot?.exists) {
    // Participant rows are never deleted — the rules refuse it — so this is
    // only reachable if one is removed out of band. Taking the copy with it
    // beats leaving a membership listed that no longer exists.
    await ref.delete();
    return;
  }

  await ref.set({
    ...snapshot.data(),
    // Pinned rather than trusted from the copied data: the id under the
    // challenge is the uid and the id here is the challenge, so both halves of
    // the pair have to survive being moved.
    challengeId,
    userId,
    mirroredAt: serverTimestamp(),
  });
}

// --- Triggers -------------------------------------------------------------

/**
 * Runs, for challenge attribution.
 *
 * A SECOND trigger on `runs/{runId}`, alongside `onRunLogged` in challenges.js.
 * That one is left exactly as it was — this is the change that makes adding a
 * whole challenge model unable to affect Pulse 75.
 *
 * `onDocumentWritten` rather than `onDocumentCreated` because this engine keeps
 * running totals, so it has to hear about edits and deletions too. Pulse 75 can
 * use the created-only trigger safely because it re-derives every day from the
 * logs on a schedule and self-heals; a stored sum does not get that for free,
 * which is why every write below is a re-derivation rather than an increment.
 */
exports.onRunWrittenForChallenges = onDocumentWritten(
  "runs/{runId}",
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;

    const afterData = after?.exists ? after.data() : null;
    const beforeData = before?.exists ? before.data() : null;
    const ownerId = afterData?.authorId || beforeData?.authorId;
    if (!ownerId) return;

    await attributeRun(event.params.runId, afterData, ownerId);
  }
);

/**
 * Participants joining, accepting, declining, leaving.
 *
 * Recounts the challenge, sends the invitation and acceptance notifications,
 * and re-ranks — because somebody leaving changes everybody below them.
 */
exports.onChallengeParticipantWritten = onDocumentWritten(
  "challenges/{challengeId}/participants/{userId}",
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    const { challengeId, userId } = event.params;

    // Before anything that can return early, and before the challenge is even
    // read: this copy is how the person's own hub finds the challenge at all,
    // so it must not depend on which kind of write this turned out to be.
    await mirrorMembership(challengeId, userId, after);

    const challengeRef = db().collection("challenges").doc(challengeId);
    const challengeDoc = await challengeRef.get();
    if (!challengeDoc.exists) return;

    const previousStatus = before?.exists ? before.get("status") : null;
    const currentStatus = after?.exists ? after.get("status") : null;

    const creatorId = challengeDoc.get("creatorId");
    const title = challengeDoc.get("title") || "";

    const inviteNotification = () =>
      notify(
        userId,
        creatorId,
        "challengeInvite",
        { challengeId, challengeTitle: title },
        // One invitation per challenge per person, however many times it is
        // sent: a resend rewrites this row and lifts it back to the top rather
        // than adding a second copy of the same ask.
        `challengeInvite_${challengeId}`
      );

    // Nothing moved between the states the board is built from. Almost every
    // write that lands here is one of those — rewriteRanks stamps a rank on
    // every participant of a challenge whenever anyone's does change — so this
    // is also what keeps the trigger from re-entering itself.
    //
    // The one exception is a resent invitation, which is deliberately the same
    // status twice and is told apart by its own stamp. `invitedAt` is written
    // by the invite sheet and by nothing else, least of all by the ranker, so
    // it cannot start a loop.
    if (previousStatus === currentStatus) {
      const resent =
        currentStatus === "invited" &&
        !sameInstant(before?.get("invitedAt"), after?.get("invitedAt"));
      if (resent) await inviteNotification();
      return;
    }

    await recountParticipants(challengeRef);
    await rewriteRanks(challengeDoc);

    // A new invitation: tell the person who was invited.
    if (!previousStatus && currentStatus === "invited") {
      await inviteNotification();
      return;
    }

    // An invitation accepted, or somebody joining a public challenge: tell the
    // creator. `notify` drops it when the creator is the joiner.
    if (currentStatus === "active" && previousStatus !== "active") {
      await notify(
        creatorId,
        userId,
        "challengeAccepted",
        { challengeId, challengeTitle: title },
        // Keyed by who joined, so leaving and rejoining refreshes one row
        // instead of telling the creator the same thing twice.
        `challengeAccepted_${challengeId}_${userId}`
      );
    }
  }
);

/**
 * Freezes challenges whose end date has passed.
 *
 * Hourly, and for the same reason `finaliseChallengeDays` is: a date boundary
 * arrives at a different instant in every zone, and an hourly pass closes each
 * challenge within the hour of its own cutoff. Retries are safe — a challenge
 * already marked completed is skipped on the next pass.
 */
async function finaliseEndedChallenges(now = new Date()) {
  const active = await db()
    .collection("challenges")
    .where("status", "==", "active")
    .get();

  let closed = 0;

  for (const challengeDoc of active.docs) {
    const offset = Number.isInteger(challengeDoc.get("utcOffsetMinutes"))
      ? challengeDoc.get("utcOffsetMinutes")
      : 0;
    const endDayKey = challengeDoc.get("endDayKey");
    if (!endDayKey) continue;

    // Closed at the end of the day AFTER the last day, so a run logged late on
    // the final evening still lands. The same grace `challenges.js` gives a
    // Pulse 75 day, for the same reason.
    const today = dayKeyOf(now, offset);
    if (today <= addDays(endDayKey, 1)) continue;

    // Ranks are rewritten once more before the freeze, so the final board
    // reflects everything that arrived during the grace.
    await rewriteRanks(challengeDoc);
    await challengeDoc.ref.set(
      {
        status: "completed",
        completedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      },
      { merge: true }
    );
    closed += 1;
  }

  return closed;
}

exports.finaliseRunningChallenges = onSchedule(
  {
    schedule: "every 60 minutes",
    // us-central1 for the same reason as the two scheduled jobs in
    // challenges.js: Cloud Scheduler has no presence in africa-south1, so a
    // schedule pinned to the database's own region fails to deploy with
    // "Location 'africa-south1' is not a valid location". Pinned explicitly
    // rather than left to the global default so a deploy does not fail every
    // time somebody touches this file.
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "512MiB",
    retryCount: 3,
  },
  async () => {
    const closed = await finaliseEndedChallenges();
    console.log(`finaliseRunningChallenges: froze ${closed} challenge(s)`);
  }
);

// Exported for the unit tests, which exercise the rules without Firestore.
exports._internals = {
  metricsFromDays,
  completionPercentage,
  compareParticipants,
  runInstant,
  runDistanceKm,
  runDurationSeconds,
  finaliseEndedChallenges,
  recomputeDay,
  recomputeParticipant,
  rewriteRanks,
  applyRunToChallenge,
  attributeRun,
  DEFAULT_DAILY_QUALIFYING_KM,
  MAX_PARTICIPANTS,
  MAX_CHALLENGE_DAYS,
  RANKED_STATUSES,
};
