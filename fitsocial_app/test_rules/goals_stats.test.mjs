// Personal goals and the stats they are judged on.
//
// Both are the server's. The one thing a client may do is archive its own
// goal; everything that says how far somebody got -- progress, completion, a
// period record, a day's stats -- must be refused to every client, the owner
// included. Stats are health data, so only their owner reads them.
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
  updateDoc,
  deleteDoc,
  serverTimestamp,
} from "firebase/firestore";

const ME = "goal-owner";
const OTHER = "someone-else";
const GOAL = `users/${ME}/goals/g1`;

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
    await setDoc(doc(db, GOAL), {
      userId: ME,
      metric: "workouts",
      period: "weekly",
      target: 4,
      status: "active",
      progress: 2,
      completedCurrent: false,
      completions: 0,
    });
    await setDoc(doc(db, `${GOAL}/periods/2026-W40`), {
      periodId: "2026-W40",
      progress: 2,
      completed: false,
    });
    for (const [collection, id] of [
      ["dailyStats", `${ME}_2026-09-30`],
      ["weeklyStats", `${ME}_2026-W40`],
      ["monthlyStats", `${ME}_2026-09`],
    ]) {
      await setDoc(doc(db, collection, id), { userId: ME, steps: 9000 });
    }
  });
});

const db = (uid) => env.authenticatedContext(uid).firestore();

test("the owner reads their goal and its periods", async () => {
  await assertSucceeds(getDoc(doc(db(ME), GOAL)));
  await assertSucceeds(getDoc(doc(db(ME), `${GOAL}/periods/2026-W40`)));
});

test("nobody else reads them", async () => {
  await assertFails(getDoc(doc(db(OTHER), GOAL)));
  await assertFails(getDoc(doc(db(OTHER), `${GOAL}/periods/2026-W40`)));
});

test("the owner may archive a goal", async () => {
  await assertSucceeds(
    updateDoc(doc(db(ME), GOAL), {
      status: "archived",
      updatedAt: serverTimestamp(),
    })
  );
});

test("the owner may not write progress, completion or the target", async () => {
  for (const change of [
    { progress: 4 },
    { completedCurrent: true },
    { completions: 10 },
    { target: 1 },
    { status: "completed" },
    { status: "archived", progress: 4 },
  ]) {
    await assertFails(updateDoc(doc(db(ME), GOAL), change));
  }
});

test("an archived goal cannot be brought back by the client", async () => {
  await updateDoc(doc(db(ME), GOAL), { status: "archived" });
  await assertFails(updateDoc(doc(db(ME), GOAL), { status: "active" }));
});

test("goals are created by the server, not the client", async () => {
  await assertFails(
    setDoc(doc(db(ME), `users/${ME}/goals/mine`), {
      userId: ME,
      metric: "steps",
      period: "weekly",
      target: 1,
      status: "active",
      progress: 1,
      completedCurrent: true,
    })
  );
  await assertFails(deleteDoc(doc(db(ME), GOAL)));
});

test("period records are closed to every client write", async () => {
  await assertFails(
    updateDoc(doc(db(ME), `${GOAL}/periods/2026-W40`), { completed: true })
  );
  await assertFails(
    setDoc(doc(db(ME), `${GOAL}/periods/2026-W41`), { completed: true })
  );
});

for (const [collection, id] of [
  ["dailyStats", `${ME}_2026-09-30`],
  ["weeklyStats", `${ME}_2026-W40`],
  ["monthlyStats", `${ME}_2026-09`],
]) {
  test(`${collection}: owner reads, nobody writes, nobody else reads`, async () => {
    await assertSucceeds(getDoc(doc(db(ME), collection, id)));
    await assertFails(getDoc(doc(db(OTHER), collection, id)));
    await assertFails(
      setDoc(doc(db(ME), collection, id), { userId: ME, steps: 999999 })
    );
    await assertFails(
      setDoc(doc(db(ME), collection, `${ME}_2026-10-01`), {
        userId: ME,
        steps: 1,
      })
    );
  });
}
