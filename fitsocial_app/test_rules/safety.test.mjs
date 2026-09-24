// Safety contacts, location shares and panic events, through the real rules.
//
// The property under test throughout: nobody can be made a recipient of an
// emergency alert, or a viewer of someone's position, without having accepted
// the handshake -- and a client can never mark that handshake accepted itself.
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
  deleteDoc,
  getDoc,
  serverTimestamp,
  Timestamp,
} from "firebase/firestore";

const OWNER = "owner-uid";
const FRIEND = "friend-uid";
const STRANGER = "stranger-uid";

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
  await seed({
    [`users/${OWNER}`]: { displayName: "Naledi" },
    [`users/${FRIEND}`]: { displayName: "Thandi" },
    [`users/${STRANGER}`]: { displayName: "Stranger" },
    [`users/${OWNER}/safetyContacts/${FRIEND}`]: { contactUid: FRIEND, status: "accepted" },
    [`users/${FRIEND}/safetyContactOf/${OWNER}`]: { contactUid: OWNER, status: "accepted" },
  });
});

function asUser(uid) {
  return env.authenticatedContext(uid).firestore();
}

async function seed(docs) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    for (const [path, data] of Object.entries(docs)) {
      await setDoc(doc(ctx.firestore(), path), data);
    }
  });
}

// ── safety contacts ──────────────────────────────────────────────────────────

function invite(overrides = {}) {
  return {
    contactUid: STRANGER,
    status: "pending",
    invitedAt: serverTimestamp(),
    ...overrides,
  };
}

test("a user can invite someone as a pending contact", async () => {
  await assertSucceeds(
    setDoc(doc(asUser(OWNER), `users/${OWNER}/safetyContacts/${STRANGER}`), invite())
  );
});

test("an invite cannot arrive already accepted", async () => {
  await assertFails(
    setDoc(
      doc(asUser(OWNER), `users/${OWNER}/safetyContacts/${STRANGER}`),
      invite({ status: "accepted" })
    )
  );
});

test("nobody can invite themselves, or a user who does not exist", async () => {
  await assertFails(
    setDoc(
      doc(asUser(OWNER), `users/${OWNER}/safetyContacts/${OWNER}`),
      invite({ contactUid: OWNER })
    )
  );
  await assertFails(
    setDoc(
      doc(asUser(OWNER), `users/${OWNER}/safetyContacts/ghost`),
      invite({ contactUid: "ghost" })
    )
  );
});

test("a pending invite cannot be promoted by the client", async () => {
  await seed({ [`users/${OWNER}/safetyContacts/${STRANGER}`]: { status: "pending" } });
  await assertFails(
    updateDoc(doc(asUser(OWNER), `users/${OWNER}/safetyContacts/${STRANGER}`), {
      status: "accepted",
    })
  );
  await assertFails(
    updateDoc(doc(asUser(STRANGER), `users/${OWNER}/safetyContacts/${STRANGER}`), {
      status: "accepted",
    })
  );
});

test("nobody writes into another user's contact lists", async () => {
  await assertFails(
    setDoc(
      doc(asUser(STRANGER), `users/${OWNER}/safetyContacts/${STRANGER}`),
      invite()
    )
  );
  await assertFails(
    setDoc(doc(asUser(OWNER), `users/${STRANGER}/safetyContactOf/${OWNER}`), {
      status: "accepted",
    })
  );
});

test("contact lists are private to their owner", async () => {
  await assertSucceeds(getDoc(doc(asUser(OWNER), `users/${OWNER}/safetyContacts/${FRIEND}`)));
  await assertFails(getDoc(doc(asUser(STRANGER), `users/${OWNER}/safetyContacts/${FRIEND}`)));
  await assertSucceeds(getDoc(doc(asUser(FRIEND), `users/${FRIEND}/safetyContactOf/${OWNER}`)));
  await assertFails(getDoc(doc(asUser(OWNER), `users/${FRIEND}/safetyContactOf/${OWNER}`)));
});

test("the owner can withdraw a contact row", async () => {
  await assertSucceeds(
    deleteDoc(doc(asUser(OWNER), `users/${OWNER}/safetyContacts/${FRIEND}`))
  );
});

// ── email contacts ───────────────────────────────────────────────────────────

test("email contacts are readable by their owner only", async () => {
  await seed({
    [`users/${OWNER}/emailContacts/c1`]: { name: "Mom", email: "mom@example.com", status: "confirmed" },
  });
  await assertSucceeds(getDoc(doc(asUser(OWNER), `users/${OWNER}/emailContacts/c1`)));
  await assertFails(getDoc(doc(asUser(FRIEND), `users/${OWNER}/emailContacts/c1`)));
});

test("a client cannot add or confirm an email contact directly", async () => {
  await assertFails(
    setDoc(doc(asUser(OWNER), `users/${OWNER}/emailContacts/c1`), {
      name: "Mom",
      email: "mom@example.com",
      status: "confirmed",
    })
  );
});

test("tracking tokens and email recipients are closed to every client", async () => {
  await seed({
    "emailLinks/tok123": { kind: "alert", ownerId: OWNER, eventId: "e1" },
    "panicEvents/e1": { userId: OWNER, status: "active", notifiedUserIds: [FRIEND] },
    "panicEvents/e1/emailRecipients/c1": { email: "mom@example.com", token: "tok123" },
  });
  await assertFails(getDoc(doc(asUser(OWNER), "emailLinks/tok123")));
  await assertFails(getDoc(doc(asUser(OWNER), "panicEvents/e1/emailRecipients/c1")));
  await assertFails(getDoc(doc(asUser(FRIEND), "panicEvents/e1/emailRecipients/c1")));
});

// ── PIN settings ─────────────────────────────────────────────────────────────

test("safety settings are unreadable to other users", async () => {
  await seed({
    [`users/${OWNER}/private/safety`]: { pinSalt: "s", safePinHash: "a", duressPinHash: "b" },
  });
  await assertSucceeds(getDoc(doc(asUser(OWNER), `users/${OWNER}/private/safety`)));
  await assertFails(getDoc(doc(asUser(FRIEND), `users/${OWNER}/private/safety`)));
});

// ── panic events ─────────────────────────────────────────────────────────────

function panic(overrides = {}) {
  return {
    userId: OWNER,
    status: "active",
    duress: false,
    location: { lat: -26.2, lng: 28.04, accuracy: 8, isLastKnown: false },
    batteryPercent: 64,
    raisedAt: serverTimestamp(),
    closedAt: null,
    clientRaisedAtMillis: Date.now(),
    ...overrides,
  };
}

test("a user can raise a panic event as themselves", async () => {
  await assertSucceeds(setDoc(doc(asUser(OWNER), "panicEvents/e1"), panic()));
});

test("with no location, the event is still accepted", async () => {
  await assertSucceeds(
    setDoc(doc(asUser(OWNER), "panicEvents/e1"), panic({ location: null }))
  );
});

test("an event naming its own recipients is refused", async () => {
  await assertFails(
    setDoc(doc(asUser(OWNER), "panicEvents/e1"), panic({ notifiedUserIds: [STRANGER] }))
  );
});

test("an event cannot be raised on someone else's behalf", async () => {
  await assertFails(setDoc(doc(asUser(STRANGER), "panicEvents/e1"), panic()));
});

test("an event cannot arrive already resolved or backdated", async () => {
  await assertFails(
    setDoc(doc(asUser(OWNER), "panicEvents/e1"), panic({ status: "resolved" }))
  );
  await assertFails(
    setDoc(
      doc(asUser(OWNER), "panicEvents/e1"),
      panic({ raisedAt: Timestamp.fromDate(new Date("2026-01-01")) })
    )
  );
});

async function seedEvent(overrides = {}) {
  await seed({
    "panicEvents/e1": {
      userId: OWNER,
      status: "active",
      duress: false,
      closedAt: null,
      notifiedUserIds: [FRIEND],
      ...overrides,
    },
  });
}

test("the raiser and notified contacts can read the event; nobody else", async () => {
  await seedEvent();
  await assertSucceeds(getDoc(doc(asUser(OWNER), "panicEvents/e1")));
  await assertSucceeds(getDoc(doc(asUser(FRIEND), "panicEvents/e1")));
  await assertFails(getDoc(doc(asUser(STRANGER), "panicEvents/e1")));
});

test("the raiser can mark duress, which leaves the event open", async () => {
  await seedEvent();
  await assertSucceeds(
    updateDoc(doc(asUser(OWNER), "panicEvents/e1"), { status: "duress", duress: true })
  );
});

test("the raiser can resolve", async () => {
  await seedEvent();
  await assertSucceeds(
    updateDoc(doc(asUser(OWNER), "panicEvents/e1"), {
      status: "resolved",
      closedAt: serverTimestamp(),
    })
  );
});

test("a duress event can be resolved later with the safe PIN", async () => {
  await seedEvent({ status: "duress", duress: true });
  await assertSucceeds(
    updateDoc(doc(asUser(OWNER), "panicEvents/e1"), {
      status: "resolved",
      closedAt: serverTimestamp(),
    })
  );
});

test("a resolved event cannot be reopened or moved", async () => {
  await seedEvent({ status: "resolved" });
  await assertFails(
    updateDoc(doc(asUser(OWNER), "panicEvents/e1"), { status: "active" })
  );
  await assertFails(
    updateDoc(doc(asUser(OWNER), "panicEvents/e1"), {
      current: { lat: 1, lng: 2, accuracy: 5, batteryPercent: 50, updatedAt: serverTimestamp() },
    })
  );
});

test("the raiser sends live position while active and after duress", async () => {
  const tick = {
    current: { lat: 1, lng: 2, accuracy: 5, batteryPercent: 50, updatedAt: serverTimestamp() },
  };
  await seedEvent();
  await assertSucceeds(updateDoc(doc(asUser(OWNER), "panicEvents/e1"), tick));
  await seedEvent({ status: "duress", duress: true });
  await assertSucceeds(updateDoc(doc(asUser(OWNER), "panicEvents/e1"), tick));
});

test("nobody else can move the pin, and a tick cannot smuggle other fields", async () => {
  await seedEvent();
  const current = { lat: 1, lng: 2, accuracy: 5, batteryPercent: 50, updatedAt: serverTimestamp() };
  await assertFails(updateDoc(doc(asUser(FRIEND), "panicEvents/e1"), { current }));
  await assertFails(
    updateDoc(doc(asUser(OWNER), "panicEvents/e1"), { current, status: "resolved" })
  );
});

test("the raiser cannot rewrite who was notified", async () => {
  await seedEvent();
  await assertFails(
    updateDoc(doc(asUser(OWNER), "panicEvents/e1"), { notifiedUserIds: [STRANGER] })
  );
});

test("a contact cannot close someone else's event", async () => {
  await seedEvent();
  await assertFails(
    updateDoc(doc(asUser(FRIEND), "panicEvents/e1"), {
      status: "resolved",
      closedAt: serverTimestamp(),
    })
  );
});

test("only a notified contact can acknowledge, and only as themselves", async () => {
  await seedEvent();
  const ack = { displayName: "Thandi", acknowledgedAt: serverTimestamp() };
  await assertSucceeds(
    setDoc(doc(asUser(FRIEND), `panicEvents/e1/acknowledgements/${FRIEND}`), ack)
  );
  await assertFails(
    setDoc(doc(asUser(STRANGER), `panicEvents/e1/acknowledgements/${STRANGER}`), ack)
  );
  await assertFails(
    setDoc(doc(asUser(STRANGER), `panicEvents/e1/acknowledgements/${FRIEND}`), ack)
  );
});

test("the raiser sees acknowledgements; strangers do not", async () => {
  await seedEvent();
  await seed({ [`panicEvents/e1/acknowledgements/${FRIEND}`]: { displayName: "Thandi" } });
  await assertSucceeds(
    getDoc(doc(asUser(OWNER), `panicEvents/e1/acknowledgements/${FRIEND}`))
  );
  await assertFails(
    getDoc(doc(asUser(STRANGER), `panicEvents/e1/acknowledgements/${FRIEND}`))
  );
});

// ── location shares ──────────────────────────────────────────────────────────

function share(overrides = {}) {
  return {
    ownerId: OWNER,
    viewerIds: [FRIEND],
    startedAt: serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + 60 * 60 * 1000),
    endedAt: null,
    status: "active",
    ...overrides,
  };
}

test("a share with accepted viewers can be opened", async () => {
  await assertSucceeds(setDoc(doc(asUser(OWNER), "locationShares/s1"), share()));
});

test("a share with more than three viewers is refused", async () => {
  await seed({
    [`users/${OWNER}/safetyContacts/a`]: { status: "accepted" },
    [`users/${OWNER}/safetyContacts/b`]: { status: "accepted" },
    [`users/${OWNER}/safetyContacts/c`]: { status: "accepted" },
  });
  await assertFails(
    setDoc(doc(asUser(OWNER), "locationShares/s1"), share({ viewerIds: [FRIEND, "a", "b", "c"] }))
  );
});

test("a share naming a non-accepted viewer is refused", async () => {
  await assertFails(
    setDoc(doc(asUser(OWNER), "locationShares/s1"), share({ viewerIds: [FRIEND, STRANGER] }))
  );
});

test("a share longer than four hours is refused", async () => {
  await assertFails(
    setDoc(
      doc(asUser(OWNER), "locationShares/s1"),
      share({ expiresAt: Timestamp.fromMillis(Date.now() + 5 * 60 * 60 * 1000) })
    )
  );
});

async function seedShare(overrides = {}) {
  await seed({
    "locationShares/s1": {
      ownerId: OWNER,
      viewerIds: [FRIEND],
      status: "active",
      expiresAt: Timestamp.fromMillis(Date.now() + 60 * 60 * 1000),
      endedAt: null,
      ...overrides,
    },
  });
}

test("viewers can read a share; strangers cannot", async () => {
  await seedShare();
  await assertSucceeds(getDoc(doc(asUser(FRIEND), "locationShares/s1")));
  await assertFails(getDoc(doc(asUser(STRANGER), "locationShares/s1")));
});

test("the owner can move the position and stop the share", async () => {
  await seedShare();
  await assertSucceeds(
    updateDoc(doc(asUser(OWNER), "locationShares/s1"), {
      current: { lat: 1, lng: 2, accuracy: 5, batteryPercent: 50, updatedAt: serverTimestamp() },
    })
  );
  await assertSucceeds(
    updateDoc(doc(asUser(OWNER), "locationShares/s1"), {
      status: "ended",
      endedAt: serverTimestamp(),
    })
  );
});

test("a share cannot be extended or widened after it starts", async () => {
  await seedShare();
  await assertFails(
    updateDoc(doc(asUser(OWNER), "locationShares/s1"), {
      expiresAt: Timestamp.fromMillis(Date.now() + 3 * 60 * 60 * 1000),
    })
  );
  await assertFails(
    updateDoc(doc(asUser(OWNER), "locationShares/s1"), { viewerIds: [FRIEND, STRANGER] })
  );
});

test("an ended share cannot be restarted", async () => {
  await seedShare({ status: "ended" });
  await assertFails(
    updateDoc(doc(asUser(OWNER), "locationShares/s1"), { status: "active" })
  );
});
