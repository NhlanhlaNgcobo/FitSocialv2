/**
 * The runWalk task figure, and which GPS activities feed it.
 *
 * `runs` is one collection holding runs, hikes and rides, discriminated by an
 * `activityType` field. 75 Hard's rule is a walk or a run, so a hike counts and
 * a ride does not — and a document with no `activityType` at all is a run,
 * because that is every run logged before the field existed. Those three
 * sentences are the whole contract, and the legacy case is the one that would
 * quietly rewrite history if it broke.
 *
 * readTaskValues is exercised through a real module load rather than by testing
 * the filter alone, because the filter is only correct in the position it sits
 * in: it has to run over what activityInDay already fetched, and it has to feed
 * sources.runIds as well as the sum.
 */

const test = require("node:test");
const assert = require("node:assert");
const Module = require("node:module");

const { createFakeAdmin } = require("./fake_admin");

/**
 * Loads challenges.js against a fake firebase-admin.
 *
 * The firebase-functions stubs matter: requiring the module registers a dozen
 * real triggers as a side effect, and every one of them would reach for a live
 * Firestore. Returning inert descriptors instead lets the pure helpers below be
 * called without any of that happening.
 *
 * Each call gets its own module instance -- `_internals.db` memoises a
 * Firestore, so a cached module would leak one test's store into the next.
 */
function loadChallenges(seed = {}) {
  const fake = createFakeAdmin(seed);
  const originalLoad = Module._load;

  Module._load = function (request, parent, isMain) {
    if (request === "firebase-admin") return fake.admin;
    if (request === "firebase-functions/v2/firestore") {
      return {
        onDocumentCreated: (path, handler) => ({ path, handler }),
        onDocumentWritten: (path, handler) => ({ path, handler }),
      };
    }
    if (request === "firebase-functions/v2/scheduler") {
      return { onSchedule: (options, handler) => ({ options, handler }) };
    }
    return originalLoad.apply(this, arguments);
  };

  try {
    const resolved = require.resolve("../challenges");
    delete require.cache[resolved];
    const module = require("../challenges");
    delete require.cache[resolved];
    return { internals: module._internals, store: fake.store };
  } finally {
    Module._load = originalLoad;
  }
}

const USER = "user-1";
const DAY = "2026-09-08";
const OFFSET = 120; // Africa/Johannesburg, the default.

/** Midday on DAY in the user's zone -- comfortably inside the day window. */
function middayOf(dayKey) {
  const [y, m, d] = dayKey.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d, 12 - OFFSET / 60, 0, 0));
}

/**
 * Seeds one document in `runs`.
 *
 * `activityType` is omitted entirely when null, which is the shape of every
 * document written before the field existed -- not the same thing as writing
 * an explicit null, and the distinction is the point of the legacy test.
 */
function runDoc(id, distanceKm, activityType) {
  const data = { authorId: USER, distanceKm, startedAt: middayOf(DAY) };
  if (activityType != null) data.activityType = activityType;
  return { [`runs/${id}`]: data };
}

async function readValues(seed) {
  const { internals, store } = loadChallenges(seed);
  const enrollmentRef = internals
    .db()
    .collection("challengeEnrollments")
    .doc(`${USER}_x`);
  const result = await internals.readTaskValues(
    enrollmentRef,
    USER,
    DAY,
    OFFSET
  );
  return { result, store };
}

test("isFootActivity: absent, empty and unknown values all read as a run", () => {
  const { internals } = loadChallenges();
  const { isFootActivity } = internals;

  // The legacy shape. Every run logged before activityType existed.
  assert.equal(isFootActivity(undefined), true);
  assert.equal(isFootActivity(null), true);
  assert.equal(isFootActivity(""), true);

  assert.equal(isFootActivity("run"), true);
  assert.equal(isFootActivity("hike"), true);
  assert.equal(isFootActivity("ride"), false);
});

test("a run with no activityType still counts toward runWalk", async () => {
  const { result } = await readValues(runDoc("legacy", 8, null));

  assert.equal(result.values.runWalk, 8);
  assert.deepEqual(result.sources.runIds, ["legacy"]);
});

test("an explicit run counts", async () => {
  const { result } = await readValues(runDoc("r1", 5, "run"));

  assert.equal(result.values.runWalk, 5);
  assert.deepEqual(result.sources.runIds, ["r1"]);
});

test("a hike counts -- 75 Hard's task is a walk or a run", async () => {
  const { result } = await readValues(runDoc("h1", 6, "hike"));

  assert.equal(result.values.runWalk, 6);
  assert.deepEqual(result.sources.runIds, ["h1"]);
});

test("a ride does not count, and is not claimed as a source", async () => {
  const { result } = await readValues(runDoc("c1", 40, "ride"));

  assert.equal(result.values.runWalk, 0);
  assert.deepEqual(result.sources.runIds, []);
});

test("a mixed day sums only the foot activities", async () => {
  const { result } = await readValues({
    ...runDoc("legacy", 3, null),
    ...runDoc("r1", 4, "run"),
    ...runDoc("h1", 2, "hike"),
    ...runDoc("c1", 55, "ride"),
  });

  // 3 + 4 + 2. The 55 km ride contributes nothing, which is the whole point:
  // it would otherwise clear the 10 km target on its own.
  assert.equal(result.values.runWalk, 9);
  assert.deepEqual(result.sources.runIds.sort(), ["h1", "legacy", "r1"]);
});

test("a ride alone leaves runWalk short of its target", async () => {
  const { internals } = loadChallenges();
  const { result } = await readValues(runDoc("c1", 40, "ride"));

  // Guards the figure against the threshold rather than against zero, so this
  // fails loudly if the target and the filter ever drift apart.
  assert.ok(result.values.runWalk < internals.TASKS.runWalk.target);
  assert.equal(internals.evaluate(result.values).met.runWalk, false);
});

test("a ride does not disturb the other six task figures", async () => {
  const { result } = await readValues({
    ...runDoc("c1", 40, "ride"),
    "workouts/w1": {
      authorId: USER,
      durationMinutes: 50,
      loggedAt: middayOf(DAY),
    },
    "meals/m1": { authorId: USER, loggedAt: middayOf(DAY) },
  });

  assert.equal(result.values.runWalk, 0);
  assert.equal(result.values.workout, 50);
  assert.equal(result.values.nutrition, 1);
  assert.deepEqual(result.sources.workoutIds, ["w1"]);
});
