// Up Next: owner-only read, server-written suggestions, and the one thing the
// owner may do -- add to the day's dismissed list.
import fs from "node:fs";
import test, { before, after, beforeEach } from "node:test";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc, deleteDoc, arrayUnion } from "firebase/firestore";

const ME = "up-next-owner";
const OTHER = "someone-else";
const DAY = "2026-10-01";
const PATH = `users/${ME}/upNext/${DAY}`;

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
    await setDoc(doc(ctx.firestore(), PATH), {
      dayKey: DAY,
      suggestions: [{ id: "streak", title: "Keep it going" }],
      dismissed: ["meal"],
    });
  });
});

const as = (uid) => env.authenticatedContext(uid).firestore();

test("the owner reads today's suggestions; nobody else does", async () => {
  await assertSucceeds(getDoc(doc(as(ME), PATH)));
  await assertFails(getDoc(doc(as(OTHER), PATH)));
});

test("the owner dismisses a suggestion", async () => {
  await assertSucceeds(updateDoc(doc(as(ME), PATH), { dismissed: arrayUnion("streak") }));
});

test("a dismissal cannot be taken back or used to rewrite the suggestions", async () => {
  const ref = doc(as(ME), PATH);
  await assertFails(updateDoc(ref, { dismissed: [] }));
  await assertFails(updateDoc(ref, { suggestions: [] }));
  await assertFails(
    updateDoc(ref, { dismissed: arrayUnion("x"), suggestions: [{ id: "fake" }] })
  );
  await assertFails(
    updateDoc(ref, { dismissed: Array.from({ length: 21 }, (_, i) => `id${i}`) })
  );
});

test("nobody creates, deletes or touches someone else's", async () => {
  await assertFails(setDoc(doc(as(ME), `users/${ME}/upNext/2026-10-02`), { suggestions: [] }));
  await assertFails(deleteDoc(doc(as(ME), PATH)));
  await assertFails(updateDoc(doc(as(OTHER), PATH), { dismissed: arrayUnion("streak") }));
});
