/**
 * The leaderboard projection: what crosses from a stats document into the
 * followers-readable entry, and what the opt-out does to the entries already
 * written.
 *
 * The projection is pure and is checked field by field -- it is the one place a
 * mistake would publish something private, so "only these keys" is an assertion
 * here and not a comment. The Firestore half runs against the in-memory admin
 * stand-in, because the two behaviours worth testing (an emptied period leaves
 * the board, an opt-out clears every period) are both about documents that have
 * to *stop* existing, and that cannot be read off a pure function.
 */

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const { createFakeAdmin } = require("./fake_admin");

const FUNCTIONS_DIR = path.join(__dirname, "..");

const ME = "uid_me";
const OTHER = "uid_other";

/**
 * Loads leaderboard.js, and the modules it reads Firestore through, against a
 * fake firebase-admin.
 *
 * Planted under the key Node resolves `firebase-admin` to *from the functions
 * directory*, for the reason account_deletion.test.js spells out. Three modules
 * have to leave the cache with it: leaderboard.js captured `db` from
 * challenges.js and the stats refs from stats.js at require time, so a stale
 * copy of either would quietly hold the real SDK.
 */
function loadWithFakeAdmin(seed) {
  const adminPath = require.resolve("firebase-admin", {
    paths: [FUNCTIONS_DIR],
  });
  const modulePaths = [
    require.resolve("../challenges.js"),
    require.resolve("../stats.js"),
    require.resolve("../remote_config.js"),
    require.resolve("../leaderboard.js"),
  ];

  const fake = createFakeAdmin(seed);
  const previousAdmin = require.cache[adminPath];
  const previousModules = modulePaths.map((p) => require.cache[p]);

  require.cache[adminPath] = {
    id: adminPath,
    filename: adminPath,
    loaded: true,
    exports: fake.admin,
  };
  for (const p of modulePaths) delete require.cache[p];

  const module = require(require.resolve("../leaderboard.js"));

  if (previousAdmin) {
    require.cache[adminPath] = previousAdmin;
  } else {
    delete require.cache[adminPath];
  }
  // Put back whatever the other test files are holding, so requiring the real
  // modules later in the run does not hand them this stub.
  modulePaths.forEach((p, i) => {
    if (previousModules[i]) {
      require.cache[p] = previousModules[i];
    } else {
      delete require.cache[p];
    }
  });

  return { ...fake, internals: module._internals };
}

// --- The projection ---------------------------------------------------------

const { projectionFrom } = require("../leaderboard")._internals;

/** A week's stats as stats.js writes them, with everything a board must not see. */
function weekStats(overrides = {}) {
  return {
    userId: ME,
    weekId: "2026-W40",
    steps: 61000,
    manualSteps: 9000,
    rankableSteps: 52000,
    activeMinutes: 320,
    rankableActiveMinutes: 320,
    sessions: 5,
    meals: 14,
    longestStreak: 4,
    activeDays: 4,
    daysWithData: 6,
    flaggedDays: 0,
    avgHeartRate: 74,
    maxHeartRate: 171,
    activeDayKeys: ["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01"],
    byDay: { steps: [9000, 11000, 8000, 12000, 7000, 5000, null] },
    ...overrides,
  };
}

test("the projection carries the rankable figures and nothing else", () => {
  const entry = projectionFrom(weekStats());
  assert.deepStrictEqual(entry, {
    steps: 52000,
    activeMinutes: 320,
    sessions: 5,
    streak: 4,
    activeDays: 4,
  });
});

test("nothing private can reach an entry", () => {
  const entry = projectionFrom(weekStats());
  for (const leak of [
    "manualSteps",
    "meals",
    "avgHeartRate",
    "maxHeartRate",
    "byDay",
    "activeDayKeys",
    "daysWithData",
  ]) {
    assert.equal(leak in entry, false, `${leak} must not be published`);
  }
  // The raw step count is the one that matters most: it is the figure the
  // rankable one was derived from, and 61,000 is not what the board may show.
  assert.notEqual(entry.steps, 61000);
});

test("a day over the ceiling is already excluded upstream", () => {
  // stats.js zeroes the rankable figure for a flagged day; the projection copies
  // that without having to know the rule.
  const entry = projectionFrom(
    weekStats({ steps: 250000, rankableSteps: 0, flaggedDays: 1 })
  );
  assert.equal(entry.steps, 0);
});

test("a period with nothing in it is not a last place", () => {
  assert.equal(projectionFrom(null), null);
  assert.equal(
    projectionFrom(
      weekStats({
        rankableSteps: 0,
        rankableActiveMinutes: 0,
        sessions: 0,
        longestStreak: 0,
      })
    ),
    null
  );
});

test("a period holding only one of the four figures still ranks", () => {
  const entry = projectionFrom(
    weekStats({
      rankableSteps: 0,
      rankableActiveMinutes: 0,
      longestStreak: 0,
      sessions: 2,
    })
  );
  assert.equal(entry.sessions, 2);
  assert.equal(entry.steps, 0);
});

test("missing and nonsense figures count as zero, not NaN", () => {
  const entry = projectionFrom({
    rankableSteps: "lots",
    rankableActiveMinutes: -30,
    sessions: 3,
  });
  assert.deepStrictEqual(entry, {
    steps: 0,
    activeMinutes: 0,
    sessions: 3,
    streak: 0,
    activeDays: 0,
  });
});

// --- The Firestore half ----------------------------------------------------

function seed(extra = {}) {
  return {
    "users/uid_me": { displayName: "Me", handle: "me" },
    "users/uid_other": { displayName: "Other", handle: "other" },
    "weeklyStats/uid_me_2026-W40": weekStats(),
    "monthlyStats/uid_me_2026-09": weekStats({ rankableSteps: 180000 }),
    ...extra,
  };
}

test("a refresh writes the week's and the month's entry", async () => {
  const { internals, store } = loadWithFakeAdmin(seed());

  await internals.refreshPeriodsOf(ME, "2026-09-30");

  const week = store.get("leaderboardEntries/uid_me_2026-W40");
  assert.equal(week.userId, ME);
  assert.equal(week.periodId, "2026-W40");
  assert.equal(week.scope, "week");
  assert.equal(week.steps, 52000);
  const month = store.get("leaderboardEntries/uid_me_2026-09");
  assert.equal(month.scope, "month");
  assert.equal(month.steps, 180000);
});

test("a period emptied of everything leaves the board", async () => {
  const { internals, store } = loadWithFakeAdmin(
    seed({
      // The last workout of the week deleted, the step sync undone.
      "weeklyStats/uid_me_2026-W40": weekStats({
        rankableSteps: 0,
        rankableActiveMinutes: 0,
        sessions: 0,
        longestStreak: 0,
      }),
      "leaderboardEntries/uid_me_2026-W40": { userId: ME, steps: 52000 },
    })
  );

  await internals.refreshPeriodsOf(ME, "2026-09-30");

  assert.equal(
    store.has("leaderboardEntries/uid_me_2026-W40"),
    false,
    "the old figures must not be left standing"
  );
});

test("an opted-out user is refreshed to nothing", async () => {
  const { internals, store } = loadWithFakeAdmin(
    seed({
      "users/uid_me": { displayName: "Me", leaderboardOptOut: true },
      "leaderboardEntries/uid_me_2026-W40": { userId: ME, steps: 52000 },
    })
  );

  await internals.refreshPeriodsOf(ME, "2026-09-30");

  assert.equal(store.has("leaderboardEntries/uid_me_2026-W40"), false);
  assert.equal(store.has("leaderboardEntries/uid_me_2026-09"), false);
});

test("the purge clears every period, and only this user's", async () => {
  const { internals, store } = loadWithFakeAdmin(
    seed({
      "leaderboardEntries/uid_me_2026-W38": { userId: ME, steps: 1 },
      "leaderboardEntries/uid_me_2026-W39": { userId: ME, steps: 2 },
      "leaderboardEntries/uid_me_2026-W40": { userId: ME, steps: 3 },
      "leaderboardEntries/uid_me_2026-09": { userId: ME, steps: 4 },
      "leaderboardEntries/uid_other_2026-W40": { userId: OTHER, steps: 5 },
    })
  );

  const removed = await internals.purgeEntries(ME);

  assert.equal(removed, 4);
  assert.equal(store.has("leaderboardEntries/uid_me_2026-W38"), false);
  assert.equal(store.has("leaderboardEntries/uid_me_2026-09"), false);
  assert.equal(
    store.has("leaderboardEntries/uid_other_2026-W40"),
    true,
    "somebody else's entry stays"
  );
});
