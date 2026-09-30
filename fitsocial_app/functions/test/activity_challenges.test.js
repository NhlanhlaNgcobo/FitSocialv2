/**
 * The activity-challenge engine against a fake Firestore: a late joiner's
 * backfill, a day changing, and final results being written exactly once.
 *
 * The windows are in early September 2026 so they have ended by the time
 * these run, which keeps "today" out of the arithmetic.
 */

const test = require("node:test");
const assert = require("node:assert");
const Module = require("node:module");

const { createFakeAdmin } = require("./fake_admin");

const pad = (n) => String(n).padStart(2, "0");
const addDays = (dayKey, days) => {
  const [y, m, d] = dayKey.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
};

function loadEngine(seed = {}) {
  const fake = createFakeAdmin(seed);
  const awarded = [];
  const originalLoad = Module._load;

  Module._load = function (request, parent, isMain) {
    if (request === "firebase-admin") return fake.admin;
    if (request === "firebase-functions/v2/firestore") {
      return { onDocumentWritten: (path, handler) => ({ path, handler }) };
    }
    if (request === "firebase-functions/v2/scheduler") {
      return { onSchedule: (options, handler) => ({ options, handler }) };
    }
    if (request === "./remote_config") {
      return {
        isOn: async () => true,
        values: async () => ({
          f1_goals_challenges: true,
          integrity_max_daily_steps: 100000,
          integrity_max_daily_active_minutes: 1440,
        }),
      };
    }
    if (request === "./challenges") {
      return {
        _internals: {
          db: () => fake.admin.firestore(),
          dayKeyOf: (instant, offset) =>
            new Date(instant.getTime() + offset * 60000)
              .toISOString()
              .slice(0, 10),
          addDays,
          daysBetween: (from, to) => {
            const [ay, am, ad] = from.split("-").map(Number);
            const [by, bm, bd] = to.split("-").map(Number);
            return Math.round(
              (Date.UTC(by, bm - 1, bd) - Date.UTC(ay, am - 1, ad)) / 86400000
            );
          },
          dayRange: (dayKey) => ({
            start: new Date(`${dayKey}T00:00:00Z`),
            end: new Date(`${addDays(dayKey, 1)}T00:00:00Z`),
          }),
          activityInDay: async () => [],
          offsetFor: async () => 120,
          badgeFactsFor: async (uid) => ({ uid }),
          awardBadges: async (uid, facts, context) => {
            awarded.push({ uid, context });
            return [];
          },
        },
      };
    }
    return originalLoad(request, parent, isMain);
  };

  try {
    for (const mod of [
      "../stats",
      "../running_challenges",
      "../activity_challenges",
    ]) {
      delete require.cache[require.resolve(mod)];
    }
    const engine = require("../activity_challenges");
    return { engine, db: fake.admin.firestore(), store: fake.store, awarded };
  } finally {
    Module._load = originalLoad;
  }
}

const stamp = (iso) => ({
  toDate: () => new Date(iso),
  toMillis: () => new Date(iso).getTime(),
});

const CHALLENGE = {
  creatorId: "creator",
  title: "September steps",
  type: "activity",
  metric: "steps",
  mode: "cumulative",
  startDayKey: "2026-09-01",
  endDayKey: "2026-09-07",
  utcOffsetMinutes: 120,
  visibility: "private",
  status: "active",
  participantCount: 2,
};

const participant = (userId, joinedIso) => ({
  userId,
  challengeId: "c1",
  status: "active",
  visibility: "private",
  rank: 0,
  joinedAt: stamp(joinedIso),
});

/** A week of daily stats for [uid], `rankableSteps` from [perDay]. */
function days(uid, perDay) {
  const seed = {};
  perDay.forEach((steps, i) => {
    const dayKey = `2026-09-${pad(i + 1)}`;
    seed[`dailyStats/${uid}_${dayKey}`] = {
      userId: uid,
      dayKey,
      steps,
      rankableSteps: steps,
    };
  });
  return seed;
}

test("a late joiner is counted from the day they joined", async () => {
  const { engine, db } = loadEngine({
    "challenges/c1": CHALLENGE,
    "challenges/c1/participants/late": participant(
      "late",
      "2026-09-04T08:00:00Z"
    ),
    ...days("late", [9000, 9000, 9000, 1000, 2000, 3000, 4000]),
  });

  const challengeDoc = await db.collection("challenges").doc("c1").get();
  const participantDoc = await db
    .collection("challenges/c1/participants")
    .doc("late")
    .get();
  await engine._internals.backfillParticipant(challengeDoc, participantDoc);

  const after = (
    await db.collection("challenges/c1/participants").doc("late").get()
  ).data();
  assert.strictEqual(after.countsFromDayKey, "2026-09-04");
  assert.strictEqual(after.total, 1000 + 2000 + 3000 + 4000);
  assert.strictEqual(after.lastGainDayKey, "2026-09-07");
  assert.deepStrictEqual(Object.keys(after.dayValues).sort(), [
    "2026-09-04",
    "2026-09-05",
    "2026-09-06",
    "2026-09-07",
  ]);
});

test("a changed day moves the total and the ranking", async () => {
  const { engine, db, store } = loadEngine({
    "challenges/c1": CHALLENGE,
    "challenges/c1/participants/a": {
      ...participant("a", "2026-09-01T06:00:00Z"),
      countsFromDayKey: "2026-09-01",
      dayValues: { "2026-09-01": 5000 },
      total: 5000,
    },
    "challenges/c1/participants/b": {
      ...participant("b", "2026-09-01T07:00:00Z"),
      countsFromDayKey: "2026-09-01",
      dayValues: { "2026-09-01": 8000 },
      total: 8000,
    },
    "dailyStats/a_2026-09-02": { userId: "a", rankableSteps: 6000 },
  });

  await engine._internals.applyDay("a", "2026-09-02");

  const a = store.get("challenges/c1/participants/a");
  const b = store.get("challenges/c1/participants/b");
  assert.strictEqual(a.total, 11000);
  assert.strictEqual(a.rank, 1);
  assert.strictEqual(b.rank, 2);
  void db;
});

test("a day that falls to nothing leaves the map", async () => {
  const { engine, store } = loadEngine({
    "challenges/c1": CHALLENGE,
    "challenges/c1/participants/a": {
      ...participant("a", "2026-09-01T06:00:00Z"),
      countsFromDayKey: "2026-09-01",
      dayValues: { "2026-09-01": 5000, "2026-09-02": 3000 },
      total: 8000,
    },
    // The day's only record was deleted: its stats now read zero.
    "dailyStats/a_2026-09-02": { userId: "a", rankableSteps: 0 },
  });

  await engine._internals.applyDay("a", "2026-09-02");

  const a = store.get("challenges/c1/participants/a");
  assert.deepStrictEqual(a.dayValues, { "2026-09-01": 5000 });
  assert.strictEqual(a.total, 5000);
});

test("days outside the challenge, or before joining, change nothing", async () => {
  const { engine, store } = loadEngine({
    "challenges/c1": CHALLENGE,
    "challenges/c1/participants/a": {
      ...participant("a", "2026-09-03T06:00:00Z"),
      countsFromDayKey: "2026-09-03",
      dayValues: {},
      total: 0,
    },
    "dailyStats/a_2026-09-02": { userId: "a", rankableSteps: 9000 },
    "dailyStats/a_2026-09-09": { userId: "a", rankableSteps: 9000 },
  });

  await engine._internals.applyDay("a", "2026-09-02");
  await engine._internals.applyDay("a", "2026-09-09");

  assert.strictEqual(store.get("challenges/c1/participants/a").total, 0);
});

test("final results are written once, however often finalise runs", async () => {
  const { engine, db, store, awarded } = loadEngine({
    "challenges/c1": CHALLENGE,
    "challenges/c1/participants/a": {
      ...participant("a", "2026-09-01T06:00:00Z"),
      total: 30000,
      rank: 1,
    },
    "challenges/c1/participants/b": {
      ...participant("b", "2026-09-01T06:00:00Z"),
      total: 20000,
      rank: 2,
    },
    "challenges/c1/participants/c": {
      ...participant("c", "2026-09-01T06:00:00Z"),
      total: 10000,
      rank: 3,
    },
    "users/a": { displayName: "A" },
    "users/b": { displayName: "B" },
    "users/c": { displayName: "C" },
    "users/creator": { displayName: "Creator" },
  });

  const challengeDoc = await db.collection("challenges").doc("c1").get();
  await engine._internals.recordResults(challengeDoc);
  await engine._internals.recordResults(challengeDoc);

  assert.strictEqual(store.get("challenges/c1/participants/a").finalRank, 1);
  assert.strictEqual(store.get("challenges/c1/participants/c").finalRank, 3);

  assert.strictEqual(store.get("users/a").challengeWins, 1);
  assert.strictEqual(store.get("users/a").challengePodiums, 1);
  assert.strictEqual(store.get("users/a").challengesFinished, 1);
  assert.strictEqual(store.get("users/b").challengeWins, undefined);
  assert.strictEqual(store.get("users/c").challengePodiums, 1);

  assert.strictEqual(awarded.length, 3, "one badge check per person, once");

  const result = store.get("users/b/notifications/challengeResult_c1");
  assert.strictEqual(result.type, "challengeResult");
  assert.strictEqual(result.finalRank, 2);
  assert.strictEqual(result.participantCount, 3);
});
