// Activity challenges: what may be created, and what may never be written.
//
// They share the participant rules with running challenges, so the join,
// invite and accept paths are covered by running_challenges.test.mjs. This
// file checks what is new: the create rule for the challenge itself, and that
// no participant row can arrive carrying a figure the engine owns.
import fs from "node:fs";
import test, { before, after, beforeEach } from "node:test";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import {
  doc,
  setDoc,
  updateDoc,
  serverTimestamp,
} from "firebase/firestore";

const CREATOR = "creator-uid";
const FRIEND = "friend-uid";

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "fitsocial-rules-test",
    firestore: {
      rules: fs.readFileSync(
        new URL("../firestore.rules", import.meta.url),
        "utf8"
      ),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const db = (uid) => env.authenticatedContext(uid).firestore();

/** What the app sends for a new activity challenge. */
const activityChallenge = (overrides = {}) => ({
  creatorId: CREATOR,
  title: "October steps",
  description: "",
  type: "activity",
  metric: "steps",
  mode: "cumulative",
  visibility: "private",
  startDayKey: "2026-10-01",
  endDayKey: "2026-10-31",
  maxParticipants: 50,
  utcOffsetMinutes: 120,
  status: "active",
  participantCount: 0,
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  ...overrides,
});

/** The standing start every participant row is written with. */
const standingStart = (userId, challengeId, status) => ({
  challengeId,
  userId,
  status,
  visibility: "private",
  totalDistanceKm: 0,
  completedDays: 0,
  currentStreak: 0,
  longestStreak: 0,
  completionPercentage: 0,
  rank: 0,
  runCount: 0,
  totalDurationSeconds: 0,
  joinedAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
});

test("a cumulative, target and streak challenge can each be created", async () => {
  await assertSucceeds(setDoc(doc(db(CREATOR), "challenges/c1"), activityChallenge()));
  await assertSucceeds(
    setDoc(
      doc(db(CREATOR), "challenges/c2"),
      activityChallenge({ mode: "target", target: 200000 })
    )
  );
  await assertSucceeds(
    setDoc(
      doc(db(CREATOR), "challenges/c3"),
      activityChallenge({ metric: "workouts", mode: "streak", target: 1 })
    )
  );
  await assertSucceeds(
    setDoc(
      doc(db(CREATOR), "challenges/c4"),
      activityChallenge({ metric: "meal_quality" })
    )
  );
});

test("the definition is checked", async () => {
  const refused = [
    { visibility: "public" }, // invite-only this build
    { metric: "distance" },
    { mode: "fastest" },
    { mode: "target" }, // a target mode needs a target
    { mode: "target", target: 0 },
    { mode: "target", target: 2.5 },
    { target: 10 }, // cumulative has none
    { endDayKey: "2026-09-30" }, // backwards
    { endDayKey: "2027-01-01" }, // 93 days
    { startDayKey: "2026-10-1" },
    { participantCount: 3 },
    { status: "completed" },
    { maxParticipants: 501 },
    { creatorId: FRIEND },
    { title: "Hi" },
    { total: 0 }, // not a challenge field
  ];
  for (const bad of refused) {
    await assertFails(
      setDoc(doc(db(CREATOR), "challenges/bad"), activityChallenge(bad)),
      JSON.stringify(bad)
    );
  }
});

test("92 days is the longest allowed", async () => {
  await assertSucceeds(
    setDoc(
      doc(db(CREATOR), "challenges/long"),
      activityChallenge({ startDayKey: "2026-10-01", endDayKey: "2026-12-31" })
    )
  );
});

async function seedChallenge() {
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), "challenges/c1"), {
      ...activityChallenge(),
      createdAt: new Date(),
      updatedAt: new Date(),
    })
  );
}

test("the creator can join and invite from a standing start", async () => {
  await seedChallenge();
  await assertSucceeds(
    setDoc(
      doc(db(CREATOR), "challenges/c1/participants", CREATOR),
      standingStart(CREATOR, "c1", "active")
    )
  );
  await assertSucceeds(
    setDoc(
      doc(db(CREATOR), "challenges/c1/participants", FRIEND),
      standingStart(FRIEND, "c1", "invited")
    )
  );
});

test("no participant row can arrive carrying an engine figure", async () => {
  await seedChallenge();
  for (const planted of [
    { total: 999999 },
    { dayValues: { "2026-10-01": 50000 } },
    { targetReachedDayKey: "2026-10-01" },
    { finalRank: 1 },
    { total: 0 }, // absent, not merely zero
  ]) {
    await assertFails(
      setDoc(doc(db(CREATOR), "challenges/c1/participants", CREATOR), {
        ...standingStart(CREATOR, "c1", "active"),
        ...planted,
      }),
      JSON.stringify(planted)
    );
    await assertFails(
      setDoc(doc(db(CREATOR), "challenges/c1/participants", FRIEND), {
        ...standingStart(FRIEND, "c1", "invited"),
        ...planted,
      }),
      JSON.stringify(planted)
    );
  }
});

test("an accepting invitee cannot write their own total", async () => {
  await seedChallenge();
  await setDoc(
    doc(db(CREATOR), "challenges/c1/participants", FRIEND),
    standingStart(FRIEND, "c1", "invited")
  );
  await assertFails(
    updateDoc(doc(db(FRIEND), "challenges/c1/participants", FRIEND), {
      status: "active",
      total: 100000,
    })
  );
  await assertSucceeds(
    updateDoc(doc(db(FRIEND), "challenges/c1/participants", FRIEND), {
      status: "active",
      joinedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    })
  );
});
