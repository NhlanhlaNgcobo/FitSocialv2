// Routines and custom exercises: private to their author.
//
// Written the way the app reads them — `where('authorId', '==', uid)` — since a
// rule that allows a document read but refuses the query that fetches it is the
// failure that matters here.
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
  getDocs,
  deleteDoc,
  updateDoc,
  collection,
  query,
  where,
} from "firebase/firestore";

const ME = "tester-uid";
const OTHER = "someone-else";

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
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "routines", "mine"), { authorId: ME, name: "Push" });
    await setDoc(doc(db, "routines", "theirs"), { authorId: OTHER, name: "Pull" });
    await setDoc(doc(db, "customExercises", "mine"), { authorId: ME, name: "Zottman curl" });
    await setDoc(doc(db, "customExercises", "theirs"), { authorId: OTHER, name: "Sled push" });
  });
});

const db = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();

for (const name of ["routines", "customExercises"]) {
  test(`${name}: an author reads their own and lists only their own`, async () => {
    await assertSucceeds(getDoc(doc(db(ME), name, "mine")));
    await assertSucceeds(
      getDocs(query(collection(db(ME), name), where("authorId", "==", ME))),
    );
  });

  test(`${name}: nobody reads someone else's, or lists everything`, async () => {
    await assertFails(getDoc(doc(db(ME), name, "theirs")));
    await assertFails(getDocs(collection(db(ME), name)));
    await assertFails(getDoc(doc(db(null), name, "mine")));
  });

  test(`${name}: create is allowed only as yourself`, async () => {
    await assertSucceeds(setDoc(doc(db(ME), name, "new"), { authorId: ME, name: "x" }));
    await assertFails(setDoc(doc(db(ME), name, "forged"), { authorId: OTHER, name: "x" }));
    await assertFails(setDoc(doc(db(null), name, "anon"), { authorId: ME, name: "x" }));
  });

  test(`${name}: update and delete are the author's, and authorId is fixed`, async () => {
    await assertSucceeds(updateDoc(doc(db(ME), name, "mine"), { name: "renamed" }));
    await assertFails(updateDoc(doc(db(ME), name, "mine"), { authorId: OTHER }));
    await assertFails(updateDoc(doc(db(ME), name, "theirs"), { name: "hijack" }));
    await assertFails(deleteDoc(doc(db(ME), name, "theirs")));
    await assertSucceeds(deleteDoc(doc(db(ME), name, "mine")));
  });
}

// The writes the routine builder and a started routine actually send: a full
// merged save with folder and position, a folder rename, and the lastUsedAt
// stamp, which carries no authorId of its own and relies on the merge.
test("routines: the app's own saves, folder moves and last-used stamps pass", async () => {
  const mine = doc(db(ME), "routines", "mine");
  await assertSucceeds(
    setDoc(
      mine,
      {
        authorId: ME,
        name: "Push Day",
        folder: "Push · Pull · Legs",
        position: 2,
        notes: "Deload every 5th week",
        exercises: [
          {
            name: "Bench Press (Barbell)",
            exerciseId: "bench-press-barbell",
            supersetGroup: null,
            restSeconds: 120,
            notes: "Pause 1s on chest",
            sets: [{ type: "normal", weightKg: 82.5, repsMin: 6, repsMax: 8 }],
          },
        ],
      },
      { merge: true },
    ),
  );
  await assertSucceeds(updateDoc(mine, { folder: "Upper", position: 0 }));
  await assertSucceeds(setDoc(mine, { lastUsedAt: new Date() }, { merge: true }));
  await assertFails(
    setDoc(doc(db(ME), "routines", "theirs"), { lastUsedAt: new Date() }, { merge: true }),
  );
});
