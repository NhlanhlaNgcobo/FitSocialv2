// The two counters a Pulse 75 user moves by hand.
//
// Written the way the app writes them: one task key at a time, merged onto a
// document that does not exist yet on the first tap of the day. That shape is
// the whole point of the file — a rule that reads correctly but demands both
// counters at once refuses every tap ever made, which is what shipped.
import fs from "node:fs";
import test, { before, after, beforeEach } from "node:test";
import assert from "node:assert";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import { doc, setDoc, getDoc, serverTimestamp } from "firebase/firestore";

const UID = "tester-uid";
const OTHER = "someone-else";
const ENROLLMENT = `${UID}_pulse75_2026-08-18`;
const DAY = "2026-08-18";

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "fitsocial-rules-test",
    firestore: {
      rules: fs.readFileSync(new URL("../firestore.rules", import.meta.url), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

after(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  // The run itself, seeded past the rules: these tests are about the counters.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "challengeEnrollments", ENROLLMENT), {
      userId: UID,
      challengeKey: "pulse75",
      startDayKey: DAY,
      status: "active",
    });
  });
});

/** Exactly what FirestoreChallengeRepository.setManualTask sends. */
const tap = (uid, task, value) =>
  setDoc(
    doc(env.authenticatedContext(uid).firestore(),
        "challengeEnrollments", ENROLLMENT, "manual", DAY),
    { dayKey: DAY, [task]: value, updatedAt: serverTimestamp() },
    { merge: true },
  );

const stored = async () => {
  let snap;
  await env.withSecurityRulesDisabled(async (ctx) => {
    snap = await getDoc(doc(ctx.firestore(),
      "challengeEnrollments", ENROLLMENT, "manual", DAY));
  });
  return snap.data();
};

test("the first water tap of the day creates the document", async () => {
  await assertSucceeds(tap(UID, "water", 1));
});

test("reading merges onto a document water already created", async () => {
  await assertSucceeds(tap(UID, "water", 2));
  await assertSucceeds(tap(UID, "reading", 10));
  assert.deepStrictEqual(
    { water: (await stored()).water, reading: (await stored()).reading },
    { water: 2, reading: 10 },
  );
});

test("reading can go first too", async () => {
  await assertSucceeds(tap(UID, "reading", 4));
});

test("a counter can be taken back down", async () => {
  await assertSucceeds(tap(UID, "water", 3));
  await assertSucceeds(tap(UID, "water", 2));
  assert.strictEqual((await stored()).water, 2);
});

test("honest over-counting is allowed, nonsense is not", async () => {
  await assertSucceeds(tap(UID, "water", 12));
  await assertFails(tap(UID, "water", 31));
  await assertFails(tap(UID, "reading", 501));
});

test("a count must be a whole number, and not negative", async () => {
  await assertFails(tap(UID, "water", -1));
  await assertFails(tap(UID, "water", "eight"));
  await assertFails(tap(UID, "water", 2.5));
});

test("no other task can ride along on a manual write", async () => {
  await assertFails(setDoc(
    doc(env.authenticatedContext(UID).firestore(),
        "challengeEnrollments", ENROLLMENT, "manual", DAY),
    { dayKey: DAY, water: 3, steps: 99999 },
    { merge: true },
  ));
});

test("the entry must be filed under the day it names", async () => {
  await assertFails(setDoc(
    doc(env.authenticatedContext(UID).firestore(),
        "challengeEnrollments", ENROLLMENT, "manual", DAY),
    { dayKey: "2026-01-01", water: 3 },
    { merge: true },
  ));
});

test("only the owner of a run may move its counters", async () => {
  await assertFails(tap(OTHER, "water", 8));
});
