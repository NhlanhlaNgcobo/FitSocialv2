const { test } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const { createFakeAdmin } = require("./fake_admin");

const FUNCTIONS_DIR = path.join(__dirname, "..");

/** Loads data_export.js against a fake firebase-admin. See account_deletion.test.js. */
function loadWithFakeAdmin(seed) {
  const adminPath = require.resolve("firebase-admin", {
    paths: [FUNCTIONS_DIR],
  });
  const modulePath = require.resolve("../data_export.js");

  const fake = createFakeAdmin(seed);
  const previousAdmin = require.cache[adminPath];
  require.cache[adminPath] = {
    id: adminPath,
    filename: adminPath,
    loaded: true,
    exports: fake.admin,
  };
  delete require.cache[modulePath];
  const module = require(modulePath);
  if (previousAdmin) {
    require.cache[adminPath] = previousAdmin;
  } else {
    delete require.cache[adminPath];
  }
  delete require.cache[modulePath];

  return { ...fake, internals: module._internals };
}

const ME = "uid_me";
const OTHER = "uid_other";
const LOGGED = new Date("2026-10-02T06:30:00Z");

function seedDatabase() {
  return {
    "users/uid_me": { displayName: "Me", handle: "me" },
    "users/uid_me/private/nutrition": { calorieGoal: 2300 },
    "users/uid_me/goals/g1": { metric: "steps", target: 10000 },
    "users/uid_me/goals/g1/periods/2026-W40": { progress: 4200 },
    "users/uid_me/fcmTokens/tok": { token: "secret-device-token" },
    "users/uid_me/safetyContactOf/uid_other": { ownerId: OTHER },
    "users/uid_me/pulseSeen/uid_other": { seenAt: LOGGED },
    "meals/m1": { authorId: ME, name: "Oats", calories: 178, loggedAt: LOGGED },
    "meals/m2": { authorId: OTHER, name: "Not mine", calories: 900 },
    "runs/r1": {
      authorId: ME,
      routePoints: [{ lat: -26.1, lng: 28.0 }],
    },
    "posts/p1": {
      authorId: ME,
      postType: "run",
      routePoints: [{ lat: -26.1, lng: 28.0 }],
    },
    "posts/p_other": { authorId: OTHER },
    "posts/p_other/comments/c1": { authorId: ME, text: "Nice one" },
    "posts/p_other/comments/c2": { authorId: OTHER, text: "Thanks" },
    "dailyStats/uid_me_2026-10-02": { userId: ME, steps: 8000 },
    "dailyStats/uid_other_2026-10-02": { userId: OTHER, steps: 3 },
  };
}

test("exports the user's own documents and nobody else's", async () => {
  const { internals } = loadWithFakeAdmin(seedDatabase());
  const exported = await internals.collectExport(ME, LOGGED);

  assert.equal(exported.format, "fitsocial-export");
  assert.equal(exported.userId, ME);
  assert.equal(exported.profile.handle, "me");
  assert.deepEqual(exported.meals.map((m) => m.id), ["m1"]);
  assert.deepEqual(exported.dailyStats.map((d) => d.id), ["uid_me_2026-10-02"]);
  assert.deepEqual(exported.comments.map((c) => c.path), [
    "posts/p_other/comments/c1",
  ]);
});

test("timestamps come out as ISO strings", async () => {
  const { internals } = loadWithFakeAdmin(seedDatabase());
  const exported = await internals.collectExport(ME, LOGGED);
  assert.equal(exported.meals[0].loggedAt, "2026-10-02T06:30:00.000Z");
  assert.equal(exported.exportedAt, "2026-10-02T06:30:00.000Z");
});

test("account subcollections are included, nested periods too", async () => {
  const { internals } = loadWithFakeAdmin(seedDatabase());
  const exported = await internals.collectExport(ME, LOGGED);
  assert.equal(exported.account.private[0].calorieGoal, 2300);
  assert.equal(exported.account.goals[0].periods[0].id, "2026-W40");
});

test("push tokens and other people's data about the user are left out", async () => {
  const { internals } = loadWithFakeAdmin(seedDatabase());
  const exported = await internals.collectExport(ME, LOGGED);
  const json = JSON.stringify(exported);
  assert.equal(json.includes("secret-device-token"), false);
  assert.equal("fcmTokens" in exported.account, false);
  assert.equal("safetyContactOf" in exported.account, false);
  assert.equal("pulseSeen" in exported.account, false);
});

test("a run keeps its route; its post does not repeat it", async () => {
  const { internals } = loadWithFakeAdmin(seedDatabase());
  const exported = await internals.collectExport(ME, LOGGED);
  assert.equal(exported.runs[0].routePoints.length, 1);
  assert.equal("routePoints" in exported.posts[0], false);
});

test("counts every list section", async () => {
  const { internals } = loadWithFakeAdmin(seedDatabase());
  const counts = internals.countsOf(
    await internals.collectExport(ME, LOGGED)
  );
  assert.equal(counts.meals, 1);
  assert.equal(counts.comments, 1);
  assert.equal(counts.workouts, 0);
});

test("every collection account deletion sweeps by owner is exported", () => {
  const fs = require("node:fs");
  const deletion = fs.readFileSync(
    path.join(FUNCTIONS_DIR, "account_deletion.js"),
    "utf8"
  );
  const { internals } = loadWithFakeAdmin({});
  const exported = new Set(internals.OWNED_COLLECTIONS.map(([name]) => name));
  const swept = [
    ...deletion.matchAll(/collection\("([A-Za-z]+)"\)\s*\.where\("(authorId|userId)"/g),
  ].map((match) => match[1]);
  // Guards the guard: a regex that stopped matching would pass vacuously.
  assert.ok(swept.length >= 10, `only matched ${swept.length} sweeps`);
  for (const name of swept) {
    assert.ok(exported.has(name), `${name} is deleted but not exported`);
  }
});
