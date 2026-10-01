const { test } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const { createFakeAdmin } = require("./fake_admin");

const FUNCTIONS_DIR = path.join(__dirname, "..");

/**
 * Loads account_deletion.js against a fake firebase-admin.
 *
 * The stub has to be planted under the key Node will resolve `firebase-admin`
 * to *from the functions directory* — resolving it from this test file lands it
 * under a different key and the module under test quietly gets the real SDK.
 */
function loadWithFakeAdmin(seed) {
  const adminPath = require.resolve("firebase-admin", {
    paths: [FUNCTIONS_DIR],
  });
  const modulePath = require.resolve("../account_deletion.js");

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

  // Restore immediately: the module under test captured the stub at require
  // time, and leaving it in place would leak into every later test file.
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

/**
 * A database with the departing user woven through somebody else's content:
 * their post, their comment on a stranger's post, a reaction they left, both
 * halves of two follow edges, and a Pulse view carrying their name.
 */
function seedDatabase() {
  return {
    "users/uid_me": { displayName: "Me", handle: "me", followersCount: 1, followingCount: 1 },
    "users/uid_me/private/body": { weightKg: 74 },
    "users/uid_me/bookmarks/post_other": { postId: "post_other" },
    "users/uid_me/following/uid_other": { userId: OTHER },
    "users/uid_me/followers/uid_other": { userId: OTHER },

    "users/uid_other": { displayName: "Other", handle: "other", followersCount: 3, followingCount: 5 },
    // The mirror halves: uid_other follows me, and is followed by me.
    "users/uid_other/following/uid_me": { userId: ME },
    "users/uid_other/followers/uid_me": { userId: ME },
    "users/uid_other/notifications/follow_uid_me": { type: "follow", actorId: ME },
    "users/uid_other/notifications/follow_someone": { type: "follow", actorId: "uid_third" },

    "usernames/me": { uid: ME },
    "usernames/other": { uid: OTHER },

    // My post, with a comment and a reaction on it from someone else.
    "posts/post_mine": { authorId: ME, caption: "my post", commentsCount: 1, likesCount: 1 },
    "posts/post_mine/comments/c1": { authorId: OTHER, text: "nice" },
    "likes/post_mine/users/uid_other": { reaction: "fire" },

    // Their post, which I commented on and reacted to.
    "posts/post_other": {
      authorId: OTHER,
      caption: "their post",
      commentsCount: 2,
      likesCount: 4,
      likedBy: [ME, "uid_third"],
      reactionsBy: { uid_me: "fire", uid_third: "clap" },
      reactionCounts: { fire: 2, clap: 2 },
    },
    "posts/post_other/comments/c2": { authorId: ME, text: "strong" },
    "posts/post_other/comments/c3": { authorId: "uid_third", text: "same" },
    "likes/post_other/users/uid_me": { reaction: "fire" },
    "likes/post_other/users/uid_third": { reaction: "clap" },

    // Their Pulse, which I watched and reacted to.
    "pulses/pulse_other": { authorId: OTHER, viewCount: 1 },
    "pulses/pulse_other/views/uid_me": { viewerId: ME, viewerName: "Me" },
    "pulses/pulse_other/reactions/uid_me": { reactorId: ME },

    // My own Pulse.
    "pulses/pulse_mine": { authorId: ME },
    "pulses/pulse_mine/views/uid_other": { viewerId: OTHER, viewerName: "Other" },

    // Private logs.
    "runs/run1": { authorId: ME, distanceKm: 5 },
    "runs/run2": { authorId: OTHER, distanceKm: 8 },
    "workouts/w1": { authorId: ME },
    "meals/m1": { authorId: ME },
    "dailySteps/uid_me_2026-08-18": { userId: ME, steps: 8000 },
    "dailySteps/uid_other_2026-08-18": { userId: OTHER, steps: 9000 },

    // The Build 11 stats pipeline's records, and the one projection of them
    // other people can read.
    "dailyStats/uid_me_2026-08-18": { userId: ME, steps: 8000 },
    "weeklyStats/uid_me_2026-W34": { userId: ME, rankableSteps: 52000 },
    "monthlyStats/uid_me_2026-08": { userId: ME, rankableSteps: 180000 },
    "leaderboardEntries/uid_me_2026-W34": { userId: ME, steps: 52000 },
    "leaderboardEntries/uid_other_2026-W34": { userId: OTHER, steps: 44000 },
    "pointsLedger/p1": { userId: ME, points: 10 },
    "earlyWorm/uid_me": { streak: 4 },
    "earlyWorm/uid_other": { streak: 9 },

    "challengeEnrollments/e1": { userId: ME, status: "active" },
    "challengeEnrollments/e1/days/2026-08-17": { counted: true },
    "challengeEnrollments/e2": { userId: OTHER, status: "active" },

    // Reference data, owned by nobody.
    "progress/steps": { label: "Steps" },
  };
}

async function purge(seed = seedDatabase()) {
  const context = loadWithFakeAdmin(seed);
  await context.internals.purgeAccount(ME);
  return context;
}

test("removes the user's profile and everything beneath it", async () => {
  const { store } = await purge();

  assert.equal(store.has("users/uid_me"), false);
  assert.equal(store.has("users/uid_me/private/body"), false);
  assert.equal(store.has("users/uid_me/bookmarks/post_other"), false);
});

test("deletes the user's own posts with their comments and reaction records", async () => {
  const { store } = await purge();

  assert.equal(store.has("posts/post_mine"), false);
  assert.equal(store.has("posts/post_mine/comments/c1"), false);
  // The reaction records hang off a top-level `likes` document keyed by post
  // id, so a recursive delete of the post alone would strand them.
  assert.equal(store.has("likes/post_mine/users/uid_other"), false);
});

test("withdraws reactions left on other people's posts and corrects the counters", async () => {
  const { store } = await purge();

  assert.equal(store.has("likes/post_other/users/uid_me"), false);
  // Somebody else's reaction on the same post is untouched.
  assert.equal(store.has("likes/post_other/users/uid_third"), true);

  const post = store.get("posts/post_other");
  assert.deepEqual(post.likedBy, ["uid_third"]);
  assert.equal(post.likesCount, 3);
  assert.equal(post.reactionCounts.fire, 1);
  assert.equal(post.reactionCounts.clap, 2, "another reaction key must not move");
  assert.equal("uid_me" in post.reactionsBy, false);
});

test("deletes comments left on other people's posts and decrements the count", async () => {
  const { store } = await purge();

  assert.equal(store.has("posts/post_other/comments/c2"), false);
  assert.equal(store.has("posts/post_other/comments/c3"), true);
  assert.equal(store.get("posts/post_other").commentsCount, 1);
});

test("severs both halves of every follow edge and corrects both counters", async () => {
  const { store } = await purge();

  assert.equal(store.has("users/uid_other/following/uid_me"), false);
  assert.equal(store.has("users/uid_other/followers/uid_me"), false);

  const other = store.get("users/uid_other");
  assert.equal(other.followingCount, 4, "they follow one fewer person");
  assert.equal(other.followersCount, 2, "they have one fewer follower");
});

test("clears Pulse views and reactions, including the viewer's stored name", async () => {
  const { store } = await purge();

  assert.equal(store.has("pulses/pulse_other/views/uid_me"), false);
  assert.equal(store.has("pulses/pulse_other/reactions/uid_me"), false);
  assert.equal(store.has("pulses/pulse_other"), true, "their Pulse survives");

  assert.equal(store.has("pulses/pulse_mine"), false);
  assert.equal(store.has("pulses/pulse_mine/views/uid_other"), false);
});

test("removes notifications this user caused in other inboxes", async () => {
  const { store } = await purge();

  assert.equal(store.has("users/uid_other/notifications/follow_uid_me"), false);
  assert.equal(store.has("users/uid_other/notifications/follow_someone"), true);
});

test("deletes private logs and challenge records, subcollections included", async () => {
  const { store } = await purge();

  for (const gone of [
    "runs/run1",
    "workouts/w1",
    "meals/m1",
    "dailySteps/uid_me_2026-08-18",
    "dailyStats/uid_me_2026-08-18",
    "weeklyStats/uid_me_2026-W34",
    "monthlyStats/uid_me_2026-08",
    "leaderboardEntries/uid_me_2026-W34",
    "pointsLedger/p1",
    "earlyWorm/uid_me",
    "challengeEnrollments/e1",
    "challengeEnrollments/e1/days/2026-08-17",
  ]) {
    assert.equal(store.has(gone), false, `${gone} should be deleted`);
  }
  assert.equal(
    store.has("leaderboardEntries/uid_other_2026-W34"),
    true,
    "someone else's leaderboard entry stays"
  );
});

test("holds the username instead of freeing it", async () => {
  const { store, internals } = await purge();

  const claim = store.get("usernames/me");
  assert.ok(claim, "the reservation must survive so nobody can take the name");
  assert.equal(claim.uid, ME);

  const heldDays = (claim.releaseAt.getTime() - Date.now()) / 86400000;
  assert.ok(
    Math.abs(heldDays - internals.USERNAME_HOLD_DAYS) < 0.01,
    `expected a ${internals.USERNAME_HOLD_DAYS} day hold, got ${heldDays}`
  );
});

test("never resurrects a document whose owner is already gone", async () => {
  const seed = seedDatabase();
  // uid_gone closed their account first: their follow edge to me survived the
  // sweep, but their profile did not. Correcting a counter on it must not
  // bring the profile back as a one-field ghost.
  seed["users/uid_gone/following/uid_me"] = { userId: ME };
  delete seed["users/uid_gone"];

  const { store } = await purge(seed);

  assert.equal(store.has("users/uid_gone/following/uid_me"), false);
  assert.equal(
    store.has("users/uid_gone"),
    false,
    "a counter fix must not create the profile it points at"
  );
});

test("coalesces repeated counter changes to one document", async () => {
  const seed = seedDatabase();
  // Three comments on the same post, on top of the one already seeded.
  seed["posts/post_other"].commentsCount = 5;
  seed["posts/post_other/comments/c4"] = { authorId: ME, text: "again" };
  seed["posts/post_other/comments/c5"] = { authorId: ME, text: "and again" };

  const { store } = await purge(seed);

  assert.equal(store.get("posts/post_other").commentsCount, 2);
});

test("leaves every other account and shared reference data alone", async () => {
  const { store } = await purge();

  for (const kept of [
    "users/uid_other",
    "usernames/other",
    "posts/post_other",
    "runs/run2",
    "dailySteps/uid_other_2026-08-18",
    "earlyWorm/uid_other",
    "challengeEnrollments/e2",
    "progress/steps",
  ]) {
    assert.equal(store.has(kept), true, `${kept} should survive`);
  }
});

test("sweeps past a single batch", async () => {
  const seed = seedDatabase();
  const context = loadWithFakeAdmin(seed);
  const overBatch = context.internals.BATCH_LIMIT + 25;

  for (let i = 0; i < overBatch; i += 1) {
    context.store.set(`runs/bulk_${i}`, { authorId: ME, distanceKm: 3 });
  }

  await context.internals.purgeAccount(ME);

  const remaining = [...context.store.keys()].filter((p) =>
    p.startsWith("runs/bulk_")
  );
  assert.deepEqual(remaining, [], "the loop must keep going past one batch");
});
