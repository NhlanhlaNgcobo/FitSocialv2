/**
 * Milestone posts: what counts as one, and what gets written.
 */

const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const Module = require("node:module");

const { createFakeAdmin } = require("./fake_admin");

/**
 * Loads milestones.js against a fake firebase-admin, with the trigger
 * factories reduced to records of their handler so a test can call one.
 */
function load(seed = {}) {
  const fake = createFakeAdmin(seed);
  const originalLoad = Module._load;

  Module._load = function (request, parent, isMain) {
    if (request === "firebase-admin") return fake.admin;
    if (request === "firebase-functions/v2/firestore") {
      return {
        onDocumentCreated: (p, handler) => ({ path: p, handler }),
        onDocumentUpdated: (p, handler) => ({ path: p, handler }),
      };
    }
    if (request === "./challenges") {
      return { _internals: { db: () => fake.admin.firestore() } };
    }
    return originalLoad(request, parent, isMain);
  };

  try {
    delete require.cache[require.resolve("../milestones")];
    return { module: require("../milestones"), ...fake };
  } finally {
    Module._load = originalLoad;
  }
}

const { _internals } = load().module;

/** A document snapshot the way a trigger event carries one. */
const snap = (data) => ({ data: () => data, get: (f) => data[f] });

const posts = (store) =>
  [...store.entries()].filter(([p]) => p.startsWith("posts/"));

test("a streak milestone is reported only on the day it is crossed", () => {
  const { crossedStreakMilestone } = _internals;
  assert.strictEqual(crossedStreakMilestone(2, 3), 3);
  assert.strictEqual(crossedStreakMilestone(6, 7), 7);
  assert.strictEqual(crossedStreakMilestone(7, 7), null);
  assert.strictEqual(crossedStreakMilestone(7, 8), null);
  assert.strictEqual(crossedStreakMilestone(8, 1), null);
  assert.strictEqual(crossedStreakMilestone(undefined, 3), 3);
  // A jump over two milestones reports the larger.
  assert.strictEqual(crossedStreakMilestone(5, 15), 14);
  // Past a year, every hundred.
  assert.strictEqual(crossedStreakMilestone(399, 400), 400);
  assert.strictEqual(crossedStreakMilestone(400, 401), null);
});

test("every badge the app defines has milestone copy", () => {
  const dart = fs.readFileSync(
    path.join(
      __dirname,
      "..",
      "..",
      "lib",
      "features",
      "challenges",
      "domain",
      "challenge_badges.dart"
    ),
    "utf8"
  );
  const keys = [...dart.matchAll(/key: '([A-Z0-9_]+)'/g)].map((m) => m[1]);
  assert.ok(keys.length > 0);
  for (const key of keys) {
    assert.ok(_internals.BADGE_COPY[key], `no milestone copy for ${key}`);
  }
});

test("personal bests need a history to beat", () => {
  const { personalBests } = _internals;
  const run = { distanceKm: 12, durationSeconds: 12 * 300 };
  assert.deepStrictEqual(
    personalBests(run, [{ distanceKm: 5, durationSeconds: 1800 }]),
    []
  );
});

test("a longer run and a faster 5K+ are both bests", () => {
  const { personalBests } = _internals;
  const prior = [
    { distanceKm: 5, durationSeconds: 5 * 360 },
    { distanceKm: 8, durationSeconds: 8 * 330 },
    { distanceKm: 3, durationSeconds: 3 * 280 },
  ];
  const bests = personalBests({ distanceKm: 10, durationSeconds: 10 * 300 }, prior);
  assert.deepStrictEqual(
    bests.map((b) => b.key),
    ["longest_run", "fastest_5k_pace"]
  );
  assert.strictEqual(bests[1].subtitle, "5:00 /km over 10.0 km");
  assert.strictEqual(bests[0].subtitle, "10.0 km, up from 8.0 km");
});

test("a short fast run is not a pace best, and hikes never count", () => {
  const { personalBests } = _internals;
  const prior = [
    { distanceKm: 5, durationSeconds: 5 * 360 },
    { distanceKm: 6, durationSeconds: 6 * 360 },
    { distanceKm: 7, durationSeconds: 7 * 360 },
  ];
  assert.deepStrictEqual(
    personalBests({ distanceKm: 3, durationSeconds: 3 * 200 }, prior),
    []
  );
  assert.deepStrictEqual(
    personalBests(
      { distanceKm: 20, durationSeconds: 20 * 600, activityType: "hike" },
      prior
    ),
    []
  );
});

test("a badge becomes a milestone post under the earner's name", async () => {
  const { module, store } = load({
    "users/u1": { displayName: "Lerato", avatarUrl: "https://a/p.jpg" },
  });
  await module.onBadgeAwardedMilestone.handler({
    params: { userId: "u1", badgeKey: "PULSE_75_FINISHER" },
  });

  const written = posts(store);
  assert.strictEqual(written.length, 1);
  const [, post] = written[0];
  assert.strictEqual(post.authorId, "u1");
  assert.strictEqual(post.authorName, "Lerato");
  assert.strictEqual(post.authorAvatarUrl, "https://a/p.jpg");
  assert.strictEqual(post.postType, "milestone");
  assert.strictEqual(post.milestone.title, "Pulse 75 Finisher");
  assert.match(post.caption, /Pulse 75 Finisher/);
});

test("a retried trigger does not post twice", async () => {
  const { module, store } = load({ "users/u1": { displayName: "Lerato" } });
  const event = { params: { userId: "u1", badgeKey: "FIRST_PULSE" } };
  await module.onBadgeAwardedMilestone.handler(event);
  await module.onBadgeAwardedMilestone.handler(event);
  assert.strictEqual(posts(store).length, 1);
});

test("nothing is posted for somebody who opted out", async () => {
  const { module, store } = load({
    "users/u1": { displayName: "Lerato", shareMilestones: false },
  });
  await module.onBadgeAwardedMilestone.handler({
    params: { userId: "u1", badgeKey: "FIRST_PULSE" },
  });
  assert.strictEqual(posts(store).length, 0);
});

test("an email is never used as the author name", async () => {
  const { module, store } = load({
    "users/u1": { displayName: "sipho@example.com", username: "sipho_runs" },
  });
  await module.onBadgeAwardedMilestone.handler({
    params: { userId: "u1", badgeKey: "FIRST_PULSE" },
  });
  assert.strictEqual(posts(store)[0][1].authorName, "sipho_runs");
});

test("a streak crossing seven posts once for that day", async () => {
  const { module, store } = load({ "users/u1": { displayName: "Thabo" } });
  const event = {
    params: { userId: "u1" },
    data: {
      before: snap({ currentStreak: 6, lastActivityDay: "2026-09-25" }),
      after: snap({ currentStreak: 7, lastActivityDay: "2026-09-26" }),
    },
  };
  await module.onStreakMilestone.handler(event);
  await module.onStreakMilestone.handler(event);

  const written = posts(store);
  assert.strictEqual(written.length, 1);
  assert.strictEqual(written[0][1].milestone.title, "7-day streak");
});

test("an unshared run never produces a personal best", async () => {
  const seed = {
    "users/u1": { displayName: "Thabo" },
    "runs/r1": { authorId: "u1", distanceKm: 5, durationSeconds: 1800 },
    "runs/r2": { authorId: "u1", distanceKm: 6, durationSeconds: 2160 },
    "runs/r3": { authorId: "u1", distanceKm: 7, durationSeconds: 2520 },
  };
  const run = { authorId: "u1", distanceKm: 15, durationSeconds: 4500 };

  const hidden = load({ ...seed, "runs/r4": run });
  await hidden.module.onRunPersonalBest.handler({
    params: { runId: "r4" },
    data: snap({ ...run, sharedToFeed: false }),
  });
  assert.strictEqual(posts(hidden.store).length, 0);

  const shared = load({ ...seed, "runs/r4": { ...run, sharedToFeed: true } });
  await shared.module.onRunPersonalBest.handler({
    params: { runId: "r4" },
    data: snap({ ...run, sharedToFeed: true }),
  });
  assert.deepStrictEqual(
    posts(shared.store).map(([, p]) => p.milestone.key).sort(),
    ["fastest_5k_pace", "longest_run"]
  );
});
