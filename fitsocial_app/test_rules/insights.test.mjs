// Weekly Insights and their feedback: owner-only read, server-only write for
// the insight itself, and a narrow, owner-only shape for the rating.
import fs from "node:fs";
import test, { before, after, beforeEach } from "node:test";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, deleteDoc, serverTimestamp } from "firebase/firestore";

const ME = "insight-owner";
const OTHER = "someone-else";
const WEEK = "2026-W39";

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
    await setDoc(doc(db, `users/${ME}/insights/${WEEK}`), {
      weekId: WEEK,
      status: "ready",
      insight: { headline: "A good week" },
    });
    await setDoc(doc(db, `insightFeedback/${OTHER}_${WEEK}`), {
      userId: OTHER,
      weekId: WEEK,
      rating: "unhelpful",
    });
  });
});

const as = (uid) => env.authenticatedContext(uid).firestore();
const rating = (overrides = {}) => ({
  userId: ME,
  weekId: WEEK,
  rating: "very_helpful",
  updatedAt: serverTimestamp(),
  ...overrides,
});

// --- The insight ------------------------------------------------------------

test("the owner reads their insight", async () => {
  await assertSucceeds(getDoc(doc(as(ME), `users/${ME}/insights/${WEEK}`)));
});

test("nobody else reads it, signed in or not", async () => {
  await assertFails(getDoc(doc(as(OTHER), `users/${ME}/insights/${WEEK}`)));
  await assertFails(
    getDoc(doc(env.unauthenticatedContext().firestore(), `users/${ME}/insights/${WEEK}`))
  );
});

test("not even the owner writes an insight", async () => {
  const ref = doc(as(ME), `users/${ME}/insights/${WEEK}`);
  await assertFails(setDoc(ref, { status: "ready", insight: { headline: "Mine now" } }));
  await assertFails(setDoc(doc(as(ME), `users/${ME}/insights/2026-W40`), { status: "ready" }));
  await assertFails(deleteDoc(ref));
});

// --- Feedback ---------------------------------------------------------------

test("the owner rates their own insight, and can change the rating", async () => {
  const ref = doc(as(ME), `insightFeedback/${ME}_${WEEK}`);
  await assertSucceeds(setDoc(ref, rating()));
  await assertSucceeds(setDoc(ref, rating({ rating: "offensive" })));
  await assertSucceeds(getDoc(ref));
});

test("a rating that does not exist yet can be looked for", async () => {
  await assertSucceeds(getDoc(doc(as(ME), `insightFeedback/${ME}_2026-W01`)));
});

test("nobody reads or overwrites someone else's rating", async () => {
  const ref = doc(as(ME), `insightFeedback/${OTHER}_${WEEK}`);
  await assertFails(getDoc(ref));
  await assertFails(setDoc(ref, rating({ userId: OTHER })));
  await assertFails(setDoc(ref, rating()));
});

test("a rating keeps its shape", async () => {
  const db = as(ME);
  const ref = doc(db, `insightFeedback/${ME}_${WEEK}`);
  await assertFails(setDoc(ref, rating({ rating: "meh" })));
  await assertFails(setDoc(ref, rating({ comment: "free text" })));
  await assertFails(setDoc(ref, rating({ updatedAt: new Date(0) })));
  await assertFails(setDoc(ref, rating({ weekId: "last week" })));
  // The id has to name the week the body names.
  await assertFails(setDoc(doc(db, `insightFeedback/${ME}_2026-W40`), rating()));
});

test("a rating is never deleted from the app", async () => {
  const ref = doc(as(ME), `insightFeedback/${ME}_${WEEK}`);
  await assertSucceeds(setDoc(ref, rating()));
  await assertFails(deleteDoc(ref));
});
