// The friends leaderboard's entries: who may read one, and that nobody writes
// one.
//
// The whole feature's privacy rests on this file. An entry holds figures taken
// out of a stats document that is otherwise owner-only, and it is published to
// the people who follow its owner -- so the two things worth proving are that a
// follower gets in and a stranger does not, per document, including inside a
// query that asks for both at once.
import assert from "node:assert/strict";
import fs from "node:fs";
import test, { before, after, beforeEach } from "node:test";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import {
  doc,
  documentId,
  getDoc,
  getDocs,
  collection,
  query,
  where,
  setDoc,
  deleteDoc,
} from "firebase/firestore";

const ME = "board-viewer";
const FRIEND = "followed-by-me";
const STRANGER = "follows-nobody";
const WEEK = "2026-W40";

const entryId = (uid) => `${uid}_${WEEK}`;
const entryPath = (uid) => `leaderboardEntries/${entryId(uid)}`;

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

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    // I follow FRIEND, which is recorded on FRIEND's followers list -- the half
    // of the edge the rule reads.
    await setDoc(doc(db, `users/${FRIEND}/followers/${ME}`), { userId: ME });
    for (const uid of [ME, FRIEND, STRANGER]) {
      await setDoc(doc(db, entryPath(uid)), {
        userId: uid,
        periodId: WEEK,
        scope: "week",
        steps: 52000,
        activeMinutes: 320,
        sessions: 5,
        streak: 4,
        activeDays: 4,
      });
    }
  });
});

const db = (uid) => env.authenticatedContext(uid).firestore();

test("you read your own entry", async () => {
  await assertSucceeds(getDoc(doc(db(ME), entryPath(ME))));
});

test("your own missing entry reads as missing, not as refused", async () => {
  // A week nothing was logged in. The app has to get an empty answer here; a
  // permission error would show as "the board could not load".
  await assertSucceeds(
    getDoc(doc(db(ME), `leaderboardEntries/${ME}_2026-W01`))
  );
});

test("you read the entry of somebody you follow", async () => {
  await assertSucceeds(getDoc(doc(db(ME), entryPath(FRIEND))));
});

test("you cannot read the entry of somebody you do not follow", async () => {
  await assertFails(getDoc(doc(db(ME), entryPath(STRANGER))));
});

test("being followed is not the same as following", async () => {
  // STRANGER is followed by nobody; here ME is read by STRANGER, who does not
  // follow ME. The edge is directional and so is the rule.
  await assertFails(getDoc(doc(db(STRANGER), entryPath(ME))));
});

test("a signed-out reader gets nothing", async () => {
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anon, entryPath(FRIEND))));
});

test("a board query for yourself and the people you follow is allowed", async () => {
  const board = query(
    collection(db(ME), "leaderboardEntries"),
    where(documentId(), "in", [entryId(ME), entryId(FRIEND)])
  );
  const snapshot = await assertSucceeds(getDocs(board));
  // Both rows come back: the ranking needs the figures, not just permission.
  assert.deepEqual(
    snapshot.docs.map((d) => d.id).sort(),
    [entryId(FRIEND), entryId(ME)].sort()
  );
});

test("a query that reaches for a stranger fails outright", async () => {
  // Rules are not filters. One unreadable document in the result set refuses the
  // whole query, which is what keeps the client's board scoped to the follow
  // graph rather than trusting it to ask nicely.
  const greedy = query(
    collection(db(ME), "leaderboardEntries"),
    where(documentId(), "in", [entryId(FRIEND), entryId(STRANGER)])
  );
  await assertFails(getDocs(greedy));
});

test("an unscoped sweep of the whole collection fails", async () => {
  await assertFails(getDocs(collection(db(ME), "leaderboardEntries")));
});

test("nobody writes an entry, not even its owner", async () => {
  await assertFails(
    setDoc(doc(db(ME), entryPath(ME)), { userId: ME, steps: 999999 })
  );
  await assertFails(deleteDoc(doc(db(ME), entryPath(ME))));
  // And certainly not somebody else's.
  await assertFails(
    setDoc(doc(db(ME), entryPath(FRIEND)), { userId: FRIEND, steps: 0 })
  );
});

test("the opt-out lives on your own profile, which only you may set", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `users/${ME}`), { displayName: "Me", handle: "me" });
  });
  await assertSucceeds(
    setDoc(
      doc(db(ME), `users/${ME}`),
      { displayName: "Me", handle: "me", leaderboardOptOut: true },
      { merge: true }
    )
  );
  await assertFails(
    setDoc(
      doc(db(STRANGER), `users/${ME}`),
      { leaderboardOptOut: false },
      { merge: true }
    )
  );
});
