// The security rules for a day's health record, dailySteps/{uid}_{dayKey}.
//
// Build 11 grows this document from a step count into the day record the
// goals, Compare and the friends leaderboard read. Two things must hold:
//
// Builds 10 and earlier keep working. They write exactly the original five
// fields, inside a transaction that reads first, and that write must still be
// accepted -- the Pulse 75 steps task depends on it.
//
// And the numbers a leaderboard ranks on stay inside what is possible. The
// phone is the only thing that can read a step count, so the rule is the one
// check a modified client cannot skip.
//
// The payloads are what FirestoreChallengeRepository.recordDailyHealth sends.
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
  getDoc,
  deleteDoc,
  runTransaction,
  serverTimestamp,
} from "firebase/firestore";

const ME = "walker-uid";
const OTHER = "other-uid";
const DAY = "2026-09-30";
const ID = `${ME}_${DAY}`;

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

/** What builds 10 and earlier send. */
const legacy = (steps = 8000) => ({
  userId: ME,
  dayKey: DAY,
  steps,
  source: "health_connect",
  updatedAt: serverTimestamp(),
});

/** What Build 11 sends when a watch is paired and some steps were typed in. */
const full = (overrides = {}) => ({
  ...legacy(),
  manualSteps: 1200,
  avgHeartRate: 72,
  maxHeartRate: 151,
  heartRateCoverageMinutes: 610,
  utcOffsetMinutes: 120,
  ...overrides,
});

test("a build 10 write is still accepted, first write of the day included", async () => {
  // The transaction the app runs: read the (missing) document, then write.
  const firestore = db(ME);
  await assertSucceeds(
    runTransaction(firestore, async (tx) => {
      const ref = doc(firestore, "dailySteps", ID);
      await tx.get(ref);
      tx.set(ref, legacy(), { merge: true });
    })
  );
});

test("a build 11 write with every new field is accepted", async () => {
  await assertSucceeds(
    setDoc(doc(db(ME), "dailySteps", ID), full(), { merge: true })
  );
});

test("an older build can still write over a build 11 document", async () => {
  await setDoc(doc(db(ME), "dailySteps", ID), full(), { merge: true });
  await assertSucceeds(
    setDoc(doc(db(ME), "dailySteps", ID), legacy(9000), { merge: true })
  );
});

test("more hand-typed steps than the day's total is refused", async () => {
  await assertFails(
    setDoc(doc(db(ME), "dailySteps", ID), full({ manualSteps: 8001 }), {
      merge: true,
    })
  );
});

test("a merge cannot lower the total beneath the stored manual steps", async () => {
  await setDoc(doc(db(ME), "dailySteps", ID), full(), { merge: true });
  // manualSteps stays 1200 from the stored document; 1000 steps would be less.
  await assertFails(
    setDoc(doc(db(ME), "dailySteps", ID), legacy(1000), { merge: true })
  );
});

test("each new field is bounded", async () => {
  const refused = [
    { manualSteps: -1 },
    { manualSteps: 10.5 },
    { avgHeartRate: 10 },
    { avgHeartRate: 300 },
    { maxHeartRate: 400 },
    { heartRateCoverageMinutes: 2000 },
    { utcOffsetMinutes: 900 },
    { avgHeartRate: "72" },
  ];
  for (const bad of refused) {
    await assertFails(
      setDoc(doc(db(ME), "dailySteps", ID), full(bad), { merge: true })
    );
  }
});

test("the step ceiling still holds", async () => {
  await assertFails(
    setDoc(doc(db(ME), "dailySteps", ID), legacy(200001), { merge: true })
  );
});

test("fields the app does not send are refused", async () => {
  // In particular nothing that looks like a server verdict.
  for (const extra of [{ rankable: true }, { isFlagged: false }, { rank: 1 }]) {
    await assertFails(
      setDoc(doc(db(ME), "dailySteps", ID), full(extra), { merge: true })
    );
  }
});

test("nobody writes or reads another user's day", async () => {
  await setDoc(doc(db(ME), "dailySteps", ID), full(), { merge: true });
  await assertFails(
    setDoc(doc(db(OTHER), "dailySteps", ID), full({ userId: OTHER }), {
      merge: true,
    })
  );
  await assertFails(getDoc(doc(db(OTHER), "dailySteps", ID)));
  await assertSucceeds(getDoc(doc(db(ME), "dailySteps", ID)));
});

test("a day is never deleted by a client", async () => {
  await setDoc(doc(db(ME), "dailySteps", ID), full(), { merge: true });
  await assertFails(deleteDoc(doc(db(ME), "dailySteps", ID)));
});
