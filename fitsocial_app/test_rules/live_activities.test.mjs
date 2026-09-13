// Live activity shares, tested through the real rules file.
//
// The security model here is one line long — the document id is the secret —
// and everything below exists to make sure the rules do not quietly widen it.
// A `get` by id is open to any signed-in user; a `list` is closed to everyone,
// because a listable collection of live locations is a different product.
import fs from "node:fs";
import test, { before, after, beforeEach } from "node:test";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import {
  doc,
  collection,
  setDoc,
  updateDoc,
  deleteDoc,
  getDoc,
  getDocs,
  serverTimestamp,
} from "firebase/firestore";

const SHARER = "sharer-uid";
const VIEWER = "viewer-uid";
const SHARE = "3f2c8b1e-6a4d-4e9f-9b2a-1c5d7e8f9a0b";

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
});

/** A share shaped the way FirestoreLiveShareRepository.begin writes one. */
function share(overrides = {}) {
  const startedAt = new Date("2026-09-12T06:30:00Z");
  return {
    authorId: SHARER,
    authorName: "Bear",
    activityType: "run",
    status: "live",
    startedAt,
    updatedAt: serverTimestamp(),
    expiresAt: new Date(startedAt.getTime() + 24 * 60 * 60 * 1000),
    distanceKm: 0,
    elapsedSeconds: 0,
    paceLabel: "--",
    isPaused: false,
    trail: [],
    ...overrides,
  };
}

function asUser(uid) {
  return env.authenticatedContext(uid).firestore();
}

async function seedShare(overrides = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "liveActivities", SHARE), share(overrides));
  });
}

// ── opening a share ──────────────────────────────────────────────────────────

test("a signed-in user can open a share as themselves", async () => {
  await assertSucceeds(setDoc(doc(asUser(SHARER), "liveActivities", SHARE), share()));
});

test("a share cannot be opened in somebody else's name", async () => {
  await assertFails(
    setDoc(doc(asUser(VIEWER), "liveActivities", SHARE), share({ authorId: SHARER }))
  );
});

test("a share cannot be opened with a status the app does not write", async () => {
  await assertFails(
    setDoc(doc(asUser(SHARER), "liveActivities", SHARE), share({ status: "hidden" }))
  );
});

test("a signed-out visitor cannot open one at all", async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertFails(setDoc(doc(db, "liveActivities", SHARE), share()));
});

// ── watching a share ─────────────────────────────────────────────────────────

test("anyone signed in who holds the id can watch", async () => {
  await seedShare();
  await assertSucceeds(getDoc(doc(asUser(VIEWER), "liveActivities", SHARE)));
});

test("a signed-out visitor cannot watch, even with the id", async () => {
  // The link lands in the app, which signs the viewer in first. The rule is
  // what makes the id a capability for members rather than for the internet.
  await seedShare();
  const db = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, "liveActivities", SHARE)));
});

test("nobody can list the collection — not a viewer, not the sharer", async () => {
  // The whole model. If this ever passes, every live location in the app is
  // one query away from anyone with an account.
  await seedShare();
  await assertFails(getDocs(collection(asUser(VIEWER), "liveActivities")));
  await assertFails(getDocs(collection(asUser(SHARER), "liveActivities")));
});

// ── keeping it current ───────────────────────────────────────────────────────

test("the sharer can update the position and end the share", async () => {
  await seedShare();
  const ref = doc(asUser(SHARER), "liveActivities", SHARE);
  await assertSucceeds(
    updateDoc(ref, {
      lat: -26.2,
      lng: 28.0,
      distanceKm: 1.25,
      elapsedSeconds: 420,
      paceLabel: "5:36",
      isPaused: false,
      trail: [{ lat: -26.1, lng: 28.0 }, { lat: -26.2, lng: 28.0 }],
      updatedAt: serverTimestamp(),
    })
  );
  await assertSucceeds(
    updateDoc(ref, {
      status: "ended",
      endedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    })
  );
});

test("a viewer cannot move the marker or end the share", async () => {
  await seedShare();
  const ref = doc(asUser(VIEWER), "liveActivities", SHARE);
  await assertFails(updateDoc(ref, { lat: 0, lng: 0, updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { status: "ended" }));
});

test("the sharer cannot hand the share to another account", async () => {
  await seedShare();
  await assertFails(
    updateDoc(doc(asUser(SHARER), "liveActivities", SHARE), { authorId: VIEWER })
  );
});

// ── stopping ─────────────────────────────────────────────────────────────────

test("only the sharer can remove the share", async () => {
  await seedShare();
  await assertFails(deleteDoc(doc(asUser(VIEWER), "liveActivities", SHARE)));
  await assertSucceeds(deleteDoc(doc(asUser(SHARER), "liveActivities", SHARE)));
});
