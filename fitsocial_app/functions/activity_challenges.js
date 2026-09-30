/**
 * Activity challenges: friends against each other on steps, active minutes,
 * sessions or meals logged, between two dates.
 *
 * The third challenge engine, and the thinnest. It shares everything it can
 * with running challenges -- the `challenges/{id}` document, the participant
 * rows, invitations, the membership mirror, the notifications and the hourly
 * finalise job all live in running_challenges.js and apply unchanged -- and
 * adds only what differs: where a participant's numbers come from, and how
 * they are ordered (activity_ranking.js).
 *
 * The numbers come from dailyStats (stats.js), which is itself rebuilt from
 * the logs. So this engine never reads a run, a workout or a step count
 * directly, and it inherits the integrity rules for free: hand-typed steps and
 * days over the Remote Config ceilings rank as nothing.
 *
 * What the server owns, and a client may never write: `total`, `dayValues`,
 * `longestStreak`, `qualifiedDays`, `targetReachedDayKey`, `lastGainDayKey`,
 * `countsFromDayKey`, `rank` and `finalRank`. firestore.rules refuses all of
 * them, on create as well as on update.
 *
 * Invite-only in Build 11. There is no public discovery for these: open
 * challenges between strangers need moderation this build does not have.
 */

const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

const {
  db,
  dayKeyOf,
  addDays,
  offsetFor,
  badgeFactsFor,
  awardBadges,
} = require("./challenges")._internals;
const running = require("./running_challenges")._internals;
const stats = require("./stats")._internals;
const remoteConfig = require("./remote_config");
const ranking = require("./activity_ranking");

const RANKED = running.RANKED_STATUSES;
const serverTimestamp = () => admin.firestore.FieldValue.serverTimestamp();

const isActivity = (challengeDoc) =>
  challengeDoc?.exists && challengeDoc.get("type") === ranking.ACTIVITY_TYPE;

/** The day [uid] joined, in their own calendar. */
async function joinedDayKeyOf(participantDoc, uid) {
  const joined = participantDoc.get("joinedAt")?.toDate?.() || new Date();
  return dayKeyOf(joined, await offsetFor(uid));
}

/**
 * Everything a participant has done in the challenge, rebuilt from dailyStats.
 * Run when somebody starts counting -- joining, or accepting -- and safe to
 * run again at any time.
 */
async function backfillParticipant(challengeDoc, participantDoc) {
  const challenge = challengeDoc.data();
  const uid = participantDoc.id;
  const offset = await offsetFor(uid);
  const from = ranking.effectiveStart(
    challenge,
    await joinedDayKeyOf(participantDoc, uid)
  );
  const today = dayKeyOf(new Date(), offset);
  const last = challenge.endDayKey < today ? challenge.endDayKey : today;

  const dayKeys = [];
  for (
    let k = from;
    k <= last && dayKeys.length < ranking.MAX_ACTIVITY_DAYS;
    k = addDays(k, 1)
  ) {
    dayKeys.push(k);
  }

  // Days nobody built stats for yet -- the pipeline sleeps while every Build
  // 11 feature is off -- are built now, a month at most.
  let days = await stats.readDays(uid, dayKeys);
  const missing = dayKeys.filter((k) => !days[k]).slice(-31);
  for (const k of missing) await stats.recomputeDay(uid, k, offset);
  if (missing.length > 0) days = await stats.readDays(uid, dayKeys);

  const dayValues = {};
  for (const k of dayKeys) {
    const value = ranking.dayValue(days[k], challenge.metric);
    if (value > 0) dayValues[k] = value;
  }

  await writeStanding(challengeDoc, participantDoc, dayValues, from);
}

/** Writes a participant's standing, and tells them if they just hit target. */
async function writeStanding(challengeDoc, participantDoc, dayValues, from) {
  const challenge = challengeDoc.data();
  const standing = ranking.standingFrom(challenge, dayValues, from);

  // update() rather than set with merge: a merge deep-merges maps, so a day
  // whose value fell to zero (its only session deleted) would linger in
  // `dayValues` forever. update() replaces the field whole.
  await participantDoc.ref.update({
    dayValues,
    countsFromDayKey: from,
    ...standing,
    updatedAt: serverTimestamp(),
  });

  const reachedNow =
    challenge.mode === "target" &&
    standing.targetReachedDayKey != null &&
    participantDoc.get("targetReachedDayKey") == null;
  if (reachedNow) {
    await running.notify(
      participantDoc.id,
      challenge.creatorId,
      "challengeCompleted",
      { challengeId: challengeDoc.id, challengeTitle: challenge.title || "" },
      `challengeCompleted_${challengeDoc.id}`
    );
  }
}

/**
 * A day of [uid]'s changed. Every activity challenge they are counting in that
 * covers the day takes the new figure, and re-ranks.
 */
async function applyDay(uid, dayKey) {
  if (!(await remoteConfig.isOn("f1_goals_challenges"))) return;

  const memberships = await db()
    .collectionGroup("participants")
    .where("userId", "==", uid)
    .where("status", "in", RANKED)
    .get();

  for (const participantDoc of memberships.docs) {
    const challengeRef = participantDoc.ref.parent.parent;
    if (!challengeRef) continue;
    const challengeDoc = await challengeRef.get();
    if (!isActivity(challengeDoc)) continue;
    const challenge = challengeDoc.data();
    if (challenge.status !== "active") continue;

    const from =
      participantDoc.get("countsFromDayKey") ||
      ranking.effectiveStart(challenge, await joinedDayKeyOf(participantDoc, uid));
    if (dayKey < from || dayKey > challenge.endDayKey) continue;

    const dayStats = await stats.dailyRef(uid, dayKey).get();
    const value = ranking.dayValue(
      dayStats.exists ? dayStats.data() : null,
      challenge.metric
    );
    const dayValues = { ...(participantDoc.get("dayValues") || {}) };
    if (value > 0) dayValues[dayKey] = value;
    else delete dayValues[dayKey];

    await writeStanding(challengeDoc, participantDoc, dayValues, from);
    await running.rewriteRanks(await challengeRef.get());
  }
}

stats.onDayChanged(applyDay);

/**
 * Final places, results and badges, once a challenge ends. For running
 * challenges too: a place on a finished board is worth the same whichever
 * kind of challenge it was.
 *
 * Idempotent per participant: a row that already has a `finalRank` is left
 * alone, and the counters behind the badges move in the same transaction that
 * writes it -- so a finalise pass that is retried halfway cannot count
 * anybody's win twice.
 */
async function recordResults(challengeDoc) {
  const participants = await challengeDoc.ref
    .collection("participants")
    .where("status", "in", RANKED)
    .get();
  const ranked = participants.docs.filter((d) => (d.get("rank") || 0) > 0);
  const field = isActivity(challengeDoc) ? "total" : "totalDistanceKm";

  for (const doc of ranked) {
    const rank = doc.get("rank");
    const progressed = (doc.get(field) || 0) > 0;
    const userRef = db().collection("users").doc(doc.id);

    const firstTime = await db().runTransaction(async (tx) => {
      const current = await tx.get(doc.ref);
      if (current.get("finalRank") != null) return false;
      tx.set(doc.ref, { finalRank: rank }, { merge: true });
      const increments = {};
      if (progressed) increments.challengesFinished = 1;
      if (progressed && rank === 1 && ranked.length >= 2) {
        increments.challengeWins = 1;
      }
      if (progressed && rank <= 3 && ranked.length >= 3) {
        increments.challengePodiums = 1;
      }
      if (Object.keys(increments).length > 0) {
        tx.set(
          userRef,
          Object.fromEntries(
            Object.entries(increments).map(([k, n]) => [
              k,
              admin.firestore.FieldValue.increment(n),
            ])
          ),
          { merge: true }
        );
      }
      return true;
    });
    if (!firstTime) continue;

    if (progressed) {
      await awardBadges(doc.id, await badgeFactsFor(doc.id, null), {
        challengeId: challengeDoc.id,
        finalRank: rank,
      });
    }
    await running.notify(
      doc.id,
      challengeDoc.get("creatorId"),
      "challengeResult",
      {
        challengeId: challengeDoc.id,
        challengeTitle: challengeDoc.get("title") || "",
        finalRank: rank,
        participantCount: ranked.length,
      },
      `challengeResult_${challengeDoc.id}`
    );
  }
}

running.onFinalise(recordResults);

/**
 * Somebody starts counting on an activity challenge: they joined, accepted,
 * or were put on it as its creator. Their standing is built from the day they
 * joined.
 *
 * The second trigger on participant rows, beside the one in
 * running_challenges.js that mirrors, recounts, notifies and ranks. This one
 * only reacts to a status arriving at a ranked state, so its own writes to the
 * row -- which leave the status alone -- do not bring it back.
 */
exports.onActivityParticipantWritten = onDocumentWritten(
  "challenges/{challengeId}/participants/{userId}",
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!after?.exists) return;

    const wasRanked = before?.exists && RANKED.includes(before.get("status"));
    const isRanked = RANKED.includes(after.get("status"));
    if (!isRanked || wasRanked) return;
    if (!(await remoteConfig.isOn("f1_goals_challenges"))) return;

    const challengeRef = db().collection("challenges").doc(event.params.challengeId);
    const challengeDoc = await challengeRef.get();
    if (!isActivity(challengeDoc)) return;

    await backfillParticipant(challengeDoc, after);
    await running.rewriteRanks(await challengeRef.get());
  }
);

exports._internals = {
  applyDay,
  backfillParticipant,
  recordResults,
  writeStanding,
};
