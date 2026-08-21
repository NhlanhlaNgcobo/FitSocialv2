/**
 * The running-challenge engine.
 *
 * The streak and ranking cases here are the same examples
 * test/running_challenge_domain_test.dart holds on the Dart side — the two
 * implementations of one specification, checked against one set of numbers. If
 * you change a case here, change it there.
 *
 * The attribution cases are this side's own, because idempotency, edits and
 * reversal are server concerns that have no Dart counterpart.
 */

const test = require("node:test");
const assert = require("node:assert");
const Module = require("node:module");

const { createFakeAdmin } = require("./fake_admin");

/**
 * Loads the engine against a fake firebase-admin.
 *
 * `challenges.js` is stubbed rather than loaded, for two reasons: requiring it
 * would register eight real Firestore triggers as a side effect, and its
 * `_internals.db` memoises a Firestore instance across requires, which would
 * leak one test's store into the next. The day-key helpers it hands over are
 * pure, so re-stating them here costs nothing and keeps each test isolated.
 */
function loadEngine(seed = {}) {
  const fake = createFakeAdmin(seed);
  const originalLoad = Module._load;

  Module._load = function (request, parent, isMain) {
    if (request === "firebase-admin") return fake.admin;

    if (request === "firebase-functions/v2/firestore") {
      return { onDocumentWritten: (path, handler) => ({ path, handler }) };
    }
    if (request === "firebase-functions/v2/scheduler") {
      return { onSchedule: (options, handler) => ({ options, handler }) };
    }
    if (request === "./challenges") {
      return {
        _internals: {
          db: () => fake.admin.firestore(),
          dayKeyOf: (instant, offsetMinutes) =>
            new Date(instant.getTime() + offsetMinutes * 60000)
              .toISOString()
              .slice(0, 10),
          addDays: (dayKey, days) => {
            const [y, m, d] = dayKey.split("-").map(Number);
            return new Date(Date.UTC(y, m - 1, d + days))
              .toISOString()
              .slice(0, 10);
          },
          daysBetween: (from, to) => {
            const [ay, am, ad] = from.split("-").map(Number);
            const [by, bm, bd] = to.split("-").map(Number);
            return Math.round(
              (Date.UTC(by, bm - 1, bd) - Date.UTC(ay, am - 1, ad)) / 86400000
            );
          },
        },
      };
    }
    return originalLoad(request, parent, isMain);
  };

  try {
    delete require.cache[require.resolve("../running_challenges")];
    const engine = require("../running_challenges");
    return { engine, db: fake.admin.firestore(), ...fake };
  } finally {
    Module._load = originalLoad;
  }
}

/** A Firestore-shaped timestamp, which is what the engine reads. */
const stamp = (iso) => ({
  toDate: () => new Date(iso),
  toMillis: () => new Date(iso).getTime(),
});

const CHALLENGE = {
  creatorId: "creator",
  title: "September 100",
  type: "running",
  goalType: "distance",
  goalValueKm: 100,
  dailyMinimumKm: 1,
  startDayKey: "2026-09-01",
  endDayKey: "2026-09-30",
  utcOffsetMinutes: 120,
  visibility: "public",
  status: "active",
  participantCount: 1,
};

const PARTICIPANT = {
  userId: "runner",
  challengeId: "c1",
  status: "active",
  visibility: "public",
  totalDistanceKm: 0,
  completedDays: 0,
  currentStreak: 0,
  longestStreak: 0,
  completionPercentage: 0,
  rank: 0,
  joinedAt: stamp("2026-09-01T06:00:00Z"),
};

/** A world with one active public challenge and one active participant. */
function world(extra = {}) {
  return {
    "challenges/c1": { ...CHALLENGE },
    "challenges/c1/participants/runner": { ...PARTICIPANT },
    "users/runner": { displayName: "Runner" },
    "users/creator": { displayName: "Creator" },
    ...extra,
  };
}

const run = (iso, distanceKm, extra = {}) => ({
  authorId: "runner",
  distanceKm,
  durationSeconds: 1800,
  startedAt: stamp(iso),
  createdAt: stamp(iso),
  ...extra,
});

// --- Pure rules -----------------------------------------------------------

test("streaks: the specification example resolves exactly as written", () => {
  const { engine } = loadEngine();
  const { metricsFromDays } = engine._internals;

  const metrics = metricsFromDays([
    { dayKey: "2026-09-01", distanceKm: 5.2, runCount: 1, qualified: true },
    { dayKey: "2026-09-02", distanceKm: 6.1, runCount: 1, qualified: true },
    { dayKey: "2026-09-03", distanceKm: 5.0, runCount: 1, qualified: true },
    { dayKey: "2026-09-05", distanceKm: 5.5, runCount: 1, qualified: true },
  ]);

  assert.equal(metrics.completedDays, 4);
  assert.equal(metrics.currentStreak, 1);
  assert.equal(metrics.longestStreak, 3);
  assert.equal(metrics.lastQualifiedDayKey, "2026-09-05");
  assert.ok(Math.abs(metrics.totalDistanceKm - 21.8) < 1e-9);
});

test("streaks: an unqualified day breaks the run but keeps its distance", () => {
  const { engine } = loadEngine();
  const metrics = engine._internals.metricsFromDays([
    { dayKey: "2026-09-01", distanceKm: 5.2, runCount: 1, qualified: true },
    { dayKey: "2026-09-02", distanceKm: 6.1, runCount: 1, qualified: true },
    { dayKey: "2026-09-03", distanceKm: 0.4, runCount: 1, qualified: false },
    { dayKey: "2026-09-04", distanceKm: 5.5, runCount: 1, qualified: true },
  ]);

  assert.equal(metrics.completedDays, 3);
  assert.equal(metrics.currentStreak, 1);
  assert.equal(metrics.longestStreak, 2);
  assert.ok(Math.abs(metrics.totalDistanceKm - 17.2) < 1e-9);
});

test("streaks: days may arrive in any order", () => {
  const { engine } = loadEngine();
  const metrics = engine._internals.metricsFromDays([
    { dayKey: "2026-09-05", distanceKm: 5.5, runCount: 1, qualified: true },
    { dayKey: "2026-09-01", distanceKm: 5.2, runCount: 1, qualified: true },
    { dayKey: "2026-09-03", distanceKm: 5.0, runCount: 1, qualified: true },
    { dayKey: "2026-09-02", distanceKm: 6.1, runCount: 1, qualified: true },
  ]);

  assert.equal(metrics.currentStreak, 1);
  assert.equal(metrics.longestStreak, 3);
});

test("streaks: a run across a month boundary is not broken by it", () => {
  const { engine } = loadEngine();
  const metrics = engine._internals.metricsFromDays([
    { dayKey: "2026-09-29", distanceKm: 3, runCount: 1, qualified: true },
    { dayKey: "2026-09-30", distanceKm: 3, runCount: 1, qualified: true },
    { dayKey: "2026-10-01", distanceKm: 3, runCount: 1, qualified: true },
  ]);
  assert.equal(metrics.currentStreak, 3);
});

test("completion percentage caps at 100 and survives a zero goal", () => {
  const { engine } = loadEngine();
  const { completionPercentage } = engine._internals;

  assert.ok(Math.abs(completionPercentage(22.4, 50) - 44.8) < 1e-9);
  assert.equal(completionPercentage(80, 50), 100);
  assert.equal(completionPercentage(5, 0), 0);
});

test("ranking: completed days outrank total distance", () => {
  const { engine } = loadEngine();
  const { compareParticipants } = engine._internals;

  const consistent = {
    userId: "a",
    completedDays: 12,
    totalDistanceKm: 42.5,
    completionPercentage: 42.5,
    joinedAtMillis: 1,
  };
  const oneBigRun = {
    userId: "b",
    completedDays: 2,
    totalDistanceKm: 90,
    completionPercentage: 90,
    joinedAtMillis: 1,
  };

  assert.ok(compareParticipants(consistent, oneBigRun) < 0);
  assert.deepEqual(
    [oneBigRun, consistent].sort(compareParticipants).map((p) => p.userId),
    ["a", "b"]
  );
});

test("ranking: every tie-break fires in order, and ties stay deterministic", () => {
  const { engine } = loadEngine();
  const { compareParticipants } = engine._internals;

  const base = {
    completedDays: 5,
    totalDistanceKm: 20,
    completionPercentage: 40,
    joinedAtMillis: 100,
  };

  // distance breaks a tie on days
  assert.ok(
    compareParticipants(
      { ...base, userId: "a", totalDistanceKm: 25 },
      { ...base, userId: "b" }
    ) < 0
  );
  // percentage breaks a tie on days and distance
  assert.ok(
    compareParticipants(
      { ...base, userId: "a", completionPercentage: 50 },
      { ...base, userId: "b" }
    ) < 0
  );
  // join order breaks a total tie, earliest first
  assert.ok(
    compareParticipants(
      { ...base, userId: "z", joinedAtMillis: 1 },
      { ...base, userId: "a", joinedAtMillis: 2 }
    ) < 0
  );
  // and uid breaks it when even that is equal
  assert.ok(
    compareParticipants({ ...base, userId: "amy" }, { ...base, userId: "zoe" }) <
      0
  );

  // The property all of that exists for: same input, same order, always.
  const people = ["c", "a", "b"].map((userId) => ({ ...base, userId }));
  assert.deepEqual(
    people.sort(compareParticipants).map((p) => p.userId),
    [...people].reverse().sort(compareParticipants).map((p) => p.userId)
  );
});

test("a run's day comes from startedAt, falling back to createdAt", () => {
  const { engine } = loadEngine();
  const { runInstant } = engine._internals;

  assert.equal(
    runInstant({
      startedAt: stamp("2026-09-02T05:00:00Z"),
      createdAt: stamp("2026-09-03T05:00:00Z"),
    }).toISOString(),
    "2026-09-02T05:00:00.000Z"
  );
  assert.equal(
    runInstant({ createdAt: stamp("2026-09-03T05:00:00Z") }).toISOString(),
    "2026-09-03T05:00:00.000Z"
  );
  assert.equal(runInstant({}), null);
});

// --- Attribution ----------------------------------------------------------

test("a qualifying run moves distance, days, streak and percentage", async () => {
  const { engine, store } = loadEngine(world());

  await engine._internals.attributeRun(
    "run1",
    run("2026-09-02T05:00:00Z", 5.4),
    "runner"
  );

  const attribution = store.get("challenges/c1/attributions/run1");
  assert.equal(attribution.dayKey, "2026-09-02");
  assert.equal(attribution.distanceKm, 5.4);

  const day = store.get(
    "challenges/c1/participants/runner/days/2026-09-02"
  );
  assert.equal(day.distanceKm, 5.4);
  assert.equal(day.runCount, 1);
  assert.equal(day.qualified, true);

  const participant = store.get("challenges/c1/participants/runner");
  assert.equal(participant.totalDistanceKm, 5.4);
  assert.equal(participant.completedDays, 1);
  assert.equal(participant.currentStreak, 1);
  assert.equal(participant.rank, 1);
  assert.ok(Math.abs(participant.completionPercentage - 5.4) < 1e-9);
});

test("the same run filed twice counts once", async () => {
  const { engine, store } = loadEngine(world());
  const payload = run("2026-09-02T05:00:00Z", 5.4);

  await engine._internals.attributeRun("run1", payload, "runner");
  const applied = await engine._internals.attributeRun("run1", payload, "runner");

  // The second pass finds the attribution already correct and does nothing.
  assert.equal(applied, 0);
  assert.equal(
    store.get("challenges/c1/participants/runner").totalDistanceKm,
    5.4
  );
  assert.equal(
    store.get("challenges/c1/participants/runner/days/2026-09-02").runCount,
    1
  );
});

test("editing a run's distance applies the difference, not the sum", async () => {
  const { engine, store } = loadEngine(world());

  await engine._internals.attributeRun(
    "run1",
    run("2026-09-02T05:00:00Z", 5.4),
    "runner"
  );
  await engine._internals.attributeRun(
    "run1",
    run("2026-09-02T05:00:00Z", 8.1),
    "runner"
  );

  assert.equal(
    store.get("challenges/c1/participants/runner").totalDistanceKm,
    8.1
  );
});

test("moving a run to another day empties the day it left", async () => {
  const { engine, store } = loadEngine(world());

  await engine._internals.attributeRun(
    "run1",
    run("2026-09-02T05:00:00Z", 5.4),
    "runner"
  );
  await engine._internals.attributeRun(
    "run1",
    run("2026-09-04T05:00:00Z", 5.4),
    "runner"
  );

  assert.equal(
    store.get("challenges/c1/participants/runner/days/2026-09-02"),
    undefined
  );
  assert.equal(
    store.get("challenges/c1/participants/runner/days/2026-09-04").distanceKm,
    5.4
  );
  const participant = store.get("challenges/c1/participants/runner");
  assert.equal(participant.totalDistanceKm, 5.4);
  assert.equal(participant.completedDays, 1);
});

test("deleting a run reverses it and recalculates the streak", async () => {
  const { engine, store } = loadEngine(world());

  for (const [id, day] of [
    ["r1", "2026-09-01"],
    ["r2", "2026-09-02"],
    ["r3", "2026-09-03"],
  ]) {
    await engine._internals.attributeRun(
      id,
      run(`${day}T05:00:00Z`, 5),
      "runner"
    );
  }
  assert.equal(store.get("challenges/c1/participants/runner").currentStreak, 3);

  // The middle day goes. The streak either side of it is now two ones.
  await engine._internals.attributeRun("r2", null, "runner");

  const participant = store.get("challenges/c1/participants/runner");
  assert.equal(participant.totalDistanceKm, 10);
  assert.equal(participant.completedDays, 2);
  assert.equal(participant.currentStreak, 1);
  assert.equal(participant.longestStreak, 1);
  assert.equal(
    store.get("challenges/c1/attributions/r2"),
    undefined,
    "the attribution record must be gone, not merely zeroed"
  );
});

test("two runs on one day are one completed day and both distances", async () => {
  const { engine, store } = loadEngine(world());

  await engine._internals.attributeRun("r1", run("2026-09-02T05:00:00Z", 4), "runner");
  await engine._internals.attributeRun("r2", run("2026-09-02T17:00:00Z", 6), "runner");

  const day = store.get("challenges/c1/participants/runner/days/2026-09-02");
  assert.equal(day.distanceKm, 10);
  assert.equal(day.runCount, 2);

  const participant = store.get("challenges/c1/participants/runner");
  assert.equal(participant.completedDays, 1);
  assert.equal(participant.runCount, 2);
});

test("a run under the daily minimum adds distance but not a day", async () => {
  const { engine, store } = loadEngine(world());

  await engine._internals.attributeRun(
    "r1",
    run("2026-09-02T05:00:00Z", 0.4),
    "runner"
  );

  const participant = store.get("challenges/c1/participants/runner");
  assert.equal(participant.totalDistanceKm, 0.4);
  assert.equal(participant.completedDays, 0);
  assert.equal(participant.currentStreak, 0);
});

test("a run outside the challenge window is ignored", async () => {
  const { engine, store } = loadEngine(world());

  await engine._internals.attributeRun("early", run("2026-08-31T05:00:00Z", 9), "runner");
  await engine._internals.attributeRun("late", run("2026-10-02T05:00:00Z", 9), "runner");

  assert.equal(store.get("challenges/c1/attributions/early"), undefined);
  assert.equal(store.get("challenges/c1/attributions/late"), undefined);
  assert.equal(store.get("challenges/c1/participants/runner").totalDistanceKm, 0);
});

test("the window boundary is the challenge's clock, not UTC", async () => {
  const { engine, store } = loadEngine(world());

  // 23:30 SAST on the final day is 21:30 UTC — inside.
  await engine._internals.attributeRun(
    "lastNight",
    run("2026-09-30T21:30:00Z", 5),
    "runner"
  );
  // 00:30 SAST the next morning is 22:30 UTC — outside.
  await engine._internals.attributeRun(
    "afterMidnight",
    run("2026-09-30T22:30:00Z", 5),
    "runner"
  );

  assert.equal(
    store.get("challenges/c1/attributions/lastNight").dayKey,
    "2026-09-30"
  );
  assert.equal(store.get("challenges/c1/attributions/afterMidnight"), undefined);
});

test("a run from someone who is not a participant is ignored", async () => {
  const { engine, store } = loadEngine(world());

  await engine._internals.attributeRun(
    "r1",
    { ...run("2026-09-02T05:00:00Z", 9), authorId: "stranger" },
    "stranger"
  );

  assert.equal(store.get("challenges/c1/attributions/r1"), undefined);
  assert.equal(store.get("challenges/c1/participants/runner").totalDistanceKm, 0);
});

test("an invited user's runs do not count until they accept", async () => {
  const { engine, store } = loadEngine(
    world({
      "challenges/c1/participants/runner": {
        ...PARTICIPANT,
        status: "invited",
      },
    })
  );

  await engine._internals.attributeRun("r1", run("2026-09-02T05:00:00Z", 9), "runner");

  assert.equal(store.get("challenges/c1/attributions/r1"), undefined);
});

test("someone who left stops accruing", async () => {
  const { engine, store } = loadEngine(
    world({
      "challenges/c1/participants/runner": { ...PARTICIPANT, status: "left" },
    })
  );

  await engine._internals.attributeRun("r1", run("2026-09-02T05:00:00Z", 9), "runner");

  assert.equal(store.get("challenges/c1/attributions/r1"), undefined);
});

test("a completed challenge is frozen against late activity", async () => {
  const { engine, store } = loadEngine(
    world({ "challenges/c1": { ...CHALLENGE, status: "completed" } })
  );

  await engine._internals.attributeRun("r1", run("2026-09-02T05:00:00Z", 9), "runner");

  assert.equal(store.get("challenges/c1/attributions/r1"), undefined);
  assert.equal(store.get("challenges/c1/participants/runner").totalDistanceKm, 0);
});

test("a non-running challenge is not scored by this engine", async () => {
  const { engine, store } = loadEngine(
    world({ "challenges/c1": { ...CHALLENGE, type: "reading" } })
  );

  await engine._internals.attributeRun("r1", run("2026-09-02T05:00:00Z", 9), "runner");
  assert.equal(store.get("challenges/c1/attributions/r1"), undefined);
});

test("one run counts separately toward every challenge it qualifies for", async () => {
  const { engine, store } = loadEngine(
    world({
      "challenges/c2": { ...CHALLENGE, title: "Second", goalValueKm: 50 },
      "challenges/c2/participants/runner": {
        ...PARTICIPANT,
        challengeId: "c2",
      },
    })
  );

  await engine._internals.attributeRun("r1", run("2026-09-02T05:00:00Z", 10), "runner");

  assert.equal(store.get("challenges/c1/participants/runner").totalDistanceKm, 10);
  assert.equal(store.get("challenges/c2/participants/runner").totalDistanceKm, 10);
  assert.equal(
    store.get("challenges/c2/participants/runner").completionPercentage,
    20
  );
});

// --- Ranking over real documents ------------------------------------------

test("ranks are written server-side, and dropped for anyone who left", async () => {
  const { engine, store, db } = loadEngine(
    world({
      "challenges/c1/participants/a": {
        userId: "a",
        status: "active",
        completedDays: 12,
        totalDistanceKm: 42.5,
        completionPercentage: 42.5,
        rank: 0,
        joinedAt: stamp("2026-09-01T00:00:00Z"),
      },
      "challenges/c1/participants/b": {
        userId: "b",
        status: "active",
        completedDays: 10,
        totalDistanceKm: 38.2,
        completionPercentage: 38.2,
        rank: 0,
        joinedAt: stamp("2026-09-01T00:00:00Z"),
      },
      "challenges/c1/participants/c": {
        userId: "c",
        status: "left",
        completedDays: 40,
        totalDistanceKm: 200,
        completionPercentage: 100,
        rank: 1,
        joinedAt: stamp("2026-09-01T00:00:00Z"),
      },
    })
  );

  const challengeDoc = await db.collection("challenges").doc("c1").get();
  await engine._internals.rewriteRanks(challengeDoc);

  assert.equal(store.get("challenges/c1/participants/a").rank, 1);
  assert.equal(store.get("challenges/c1/participants/b").rank, 2);
  // "runner" from the base world has zero of everything and joined first, so it
  // sorts last among the active three.
  assert.equal(store.get("challenges/c1/participants/runner").rank, 3);
  // Someone who left holds no position at all.
  assert.equal(store.get("challenges/c1/participants/c").rank, 0);
});

test("reaching the goal marks a participant completed and notifies them", async () => {
  const { engine, store } = loadEngine(
    world({ "challenges/c1": { ...CHALLENGE, goalValueKm: 10 } })
  );

  await engine._internals.attributeRun("r1", run("2026-09-02T05:00:00Z", 12), "runner");

  const participant = store.get("challenges/c1/participants/runner");
  assert.equal(participant.status, "completed");
  assert.equal(participant.completionPercentage, 100);
  // Still ranked — finishing is not leaving.
  assert.equal(participant.rank, 1);

  const notifications = [...store.entries()].filter(([path]) =>
    path.startsWith("users/runner/notifications/")
  );
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0][1].type, "challengeCompleted");
  assert.equal(notifications[0][1].challengeId, "c1");

  // And a second qualifying run does not notify again.
  await engine._internals.attributeRun("r2", run("2026-09-03T05:00:00Z", 5), "runner");
  assert.equal(
    [...store.keys()].filter((p) => p.startsWith("users/runner/notifications/"))
      .length,
    1
  );
});

// --- Freezing -------------------------------------------------------------

test("a challenge freezes only after its end date plus the grace day", async () => {
  const { engine, store } = loadEngine(world());
  const { finaliseEndedChallenges } = engine._internals;

  // The morning after the last day: still inside the grace, so a run logged
  // late last night can still land.
  assert.equal(
    await finaliseEndedChallenges(new Date("2026-10-01T06:00:00Z")),
    0
  );
  assert.equal(store.get("challenges/c1").status, "active");

  // A day later, it closes.
  assert.equal(
    await finaliseEndedChallenges(new Date("2026-10-02T06:00:00Z")),
    1
  );
  assert.equal(store.get("challenges/c1").status, "completed");

  // And a retried sweep does not close it twice.
  assert.equal(
    await finaliseEndedChallenges(new Date("2026-10-03T06:00:00Z")),
    0
  );
});

test("participant counts follow status, and only count people on the challenge", async () => {
  const { engine, store } = loadEngine(
    world({
      "challenges/c1/participants/invitee": {
        ...PARTICIPANT,
        userId: "invitee",
        status: "invited",
      },
      "challenges/c1/participants/quitter": {
        ...PARTICIPANT,
        userId: "quitter",
        status: "left",
      },
      "challenges/c1/participants/finisher": {
        ...PARTICIPANT,
        userId: "finisher",
        status: "completed",
      },
    })
  );

  const handler = engine.onChallengeParticipantWritten.handler;
  await handler({
    params: { challengeId: "c1", userId: "invitee" },
    data: {
      before: { exists: false, get: () => undefined },
      after: {
        exists: true,
        get: (f) => store.get("challenges/c1/participants/invitee")[f],
      },
    },
  });

  // runner (active) + finisher (completed). Invited and left do not count.
  assert.equal(store.get("challenges/c1").participantCount, 2);

  const invites = [...store.entries()].filter(
    ([path]) => path.startsWith("users/invitee/notifications/")
  );
  assert.equal(invites.length, 1);
  assert.equal(invites[0][1].type, "challengeInvite");
  assert.equal(invites[0][1].actorId, "creator");
});
