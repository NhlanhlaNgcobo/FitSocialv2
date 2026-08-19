// The running calendar's three doors, tested through the real rules file.
//
// The Flutter suite stubs the repository out, so a rule that refuses a write the
// app makes every day looks exactly like a passing test run — see README.md.
// That matters more here than almost anywhere else in the app, because
// raceSubmissions is the one client-writable path into calendar data and the
// rules on it are the only thing standing between a moderation queue and a
// spam target.
import fs from "node:fs";
import test, { before, after, beforeEach } from "node:test";
import assert from "node:assert";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import {
  doc,
  addDoc,
  collection,
  setDoc,
  deleteDoc,
  getDoc,
  getDocs,
  serverTimestamp,
  increment,
} from "firebase/firestore";

const UID = "tester-uid";
const OTHER = "someone-else";
const EVENT = "2026-10-03-example-road-race";

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
  // Clears the whole emulator, not just this file's data. Safe only because the
  // test script pins --test-concurrency=1 — see README.md, where the failure
  // this caused is written up.
  await env.clearFirestore();
  // A listing, seeded past the rules — which is the only way one can exist,
  // and the point of the first test below.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "raceEvents", EVENT), {
      name: "Example Road Race",
      startAt: new Date("2026-10-03T04:30:00Z"),
      province: "GP",
      city: "Midrand",
      distances: [{ km: 10, label: "10 km", priceCents: 9000 }],
      distanceBuckets: ["10k"],
      tags: ["road"],
      status: "scheduled",
      source: "curated",
    });
  });
});

/** A submission shaped exactly the way raceSubmissionToDoc builds one. */
function submission(overrides = {}) {
  return {
    submittedBy: UID,
    submittedAt: serverTimestamp(),
    reviewState: "pending",
    name: "Chamberlain Country Classic",
    startAt: new Date("2027-03-14T04:30:00Z"),
    city: "Midrand",
    province: "GP",
    ...overrides,
  };
}

function asUser(uid = UID) {
  return env.authenticatedContext(uid).firestore();
}

// ── raceEvents ──────────────────────────────────────────────────────────────

test("a signed-in user can read the calendar", async () => {
  await assertSucceeds(getDoc(doc(asUser(), "raceEvents", EVENT)));
});

test("a signed-out visitor cannot read the calendar", async () => {
  // No user meets this in the app: the router sends an unauthenticated session
  // to /welcome, so /races is only reachable once signed in. It is asserted
  // anyway because the rule is what makes that true at the database rather than
  // only in the navigation.
  const db = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, "raceEvents", EVENT)));
});

test("nobody can write a listing, not even to their own advantage", async () => {
  // The whole trust model. A runner drives to a start line on the strength of a
  // date in here, and a collection anybody could write would make it worthless.
  const db = asUser();
  await assertFails(
    setDoc(doc(db, "raceEvents", "2026-12-25-my-invented-race"), {
      name: "My Invented Race",
      startAt: new Date("2026-12-25T04:00:00Z"),
      province: "GP",
      city: "Midrand",
      distances: [{ km: 10, label: "10 km" }],
    })
  );
  await assertFails(
    setDoc(doc(db, "raceEvents", EVENT), { status: "cancelled" }, { merge: true })
  );
  await assertFails(deleteDoc(doc(db, "raceEvents", EVENT)));
});

// ── savedRaces ──────────────────────────────────────────────────────────────

test("a user can save and unsave a race", async () => {
  const db = asUser();
  const ref = doc(db, "users", UID, "savedRaces", EVENT);
  await assertSucceeds(setDoc(ref, { savedAt: serverTimestamp() }));
  await assertSucceeds(getDoc(ref));
  await assertSucceeds(deleteDoc(ref));
});

test("a user can list their own saved races", async () => {
  await assertSucceeds(getDocs(collection(asUser(), "users", UID, "savedRaces")));
});

test("saved races are private to their owner", async () => {
  // Which races somebody is eyeing is their own business. Nothing in the app
  // reads another user's list, and the rules say so rather than relying on that.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users", OTHER, "savedRaces", EVENT), {
      savedAt: new Date(),
    });
  });

  const db = asUser();
  await assertFails(getDoc(doc(db, "users", OTHER, "savedRaces", EVENT)));
  await assertFails(getDocs(collection(db, "users", OTHER, "savedRaces")));
  await assertFails(
    setDoc(doc(db, "users", OTHER, "savedRaces", "sneaky"), {
      savedAt: serverTimestamp(),
    })
  );
});

// ── raceSubmissions ─────────────────────────────────────────────────────────

test("a user can file a submission the app's shape", async () => {
  // The write the app actually makes. If this fails, the submit button is broken
  // for everybody and no Dart test would have noticed.
  await assertSucceeds(
    addDoc(collection(asUser(), "raceSubmissions"), submission())
  );
});

test("a submission accepts the optional fields", async () => {
  await assertSucceeds(
    addDoc(
      collection(asUser(), "raceSubmissions"),
      submission({
        organiser: "Midrand Striders",
        entryUrl: "https://www.entryninja.com/events",
        distancesNote: "5, 10 and 21.1 km",
        notes: "Comrades qualifier, 06:30 start",
      })
    )
  );
});

test("nobody can read the moderation queue", async () => {
  // Not even the person who filed it. An unreviewed claim about a public event
  // must not become a second, unvetted calendar.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await addDoc(collection(ctx.firestore(), "raceSubmissions"), {
      ...submission(),
      submittedAt: new Date(),
    });
  });

  const db = asUser();
  await assertFails(getDocs(collection(db, "raceSubmissions")));
});

test("a submission cannot be filed under somebody else's name", async () => {
  await assertFails(
    addDoc(
      collection(asUser(), "raceSubmissions"),
      submission({ submittedBy: OTHER })
    )
  );
});

test("a submission cannot arrive pre-approved", async () => {
  // The field that would matter most if it were writable: a submitter who could
  // set their own reviewState would have written to the calendar.
  await assertFails(
    addDoc(
      collection(asUser(), "raceSubmissions"),
      submission({ reviewState: "approved" })
    )
  );
});

test("a submission cannot backdate or forge its own timestamp", async () => {
  await assertFails(
    addDoc(
      collection(asUser(), "raceSubmissions"),
      submission({ submittedAt: new Date("2020-01-01T00:00:00Z") })
    )
  );
});

test("a submission for a past race is refused", async () => {
  await assertFails(
    addDoc(
      collection(asUser(), "raceSubmissions"),
      submission({ startAt: new Date("2020-05-01T04:30:00Z") })
    )
  );
});

test("a submission years out is refused", async () => {
  // A date this far ahead is somebody testing the form, not a fixture list.
  const farFuture = new Date(Date.now() + 1200 * 24 * 60 * 60 * 1000);
  await assertFails(
    addDoc(
      collection(asUser(), "raceSubmissions"),
      submission({ startAt: farFuture })
    )
  );
});

test("a submission with a junk name or missing place is refused", async () => {
  const db = asUser();
  await assertFails(
    addDoc(collection(db, "raceSubmissions"), submission({ name: "x" }))
  );
  await assertFails(
    addDoc(collection(db, "raceSubmissions"), submission({ city: "" }))
  );
  await assertFails(
    addDoc(
      collection(db, "raceSubmissions"),
      submission({ name: "A".repeat(200) })
    )
  );
  const withoutCity = submission();
  delete withoutCity.city;
  await assertFails(addDoc(collection(db, "raceSubmissions"), withoutCity));
});

test("a submission cannot smuggle in extra fields", async () => {
  // The keys().hasOnly clause. Without it a submission could carry anything at
  // all into a document a moderator is about to read and act on.
  await assertFails(
    addDoc(
      collection(asUser(), "raceSubmissions"),
      submission({ verifiedAt: new Date(), source: "curated" })
    )
  );
});

test("a submission cannot be edited or deleted once filed", async () => {
  let id;
  await env.withSecurityRulesDisabled(async (ctx) => {
    const ref = await addDoc(collection(ctx.firestore(), "raceSubmissions"), {
      ...submission(),
      submittedAt: new Date(),
    });
    id = ref.id;
  });

  const db = asUser();
  await assertFails(
    setDoc(doc(db, "raceSubmissions", id), { notes: "actually" }, { merge: true })
  );
  await assertFails(deleteDoc(doc(db, "raceSubmissions", id)));
});

test("a signed-out visitor cannot file a submission", async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertFails(addDoc(collection(db, "raceSubmissions"), submission()));
});

// ── entryTaps ───────────────────────────────────────────────────────────────
//
// The one client write behind entry-link attribution. It has to succeed exactly
// as the app makes it, stay private to its owner, and refuse the two things that
// would corrupt the aggregate: a client-set timestamp, and an update that does
// not actually increment.

/** The write FirestoreRaceRepository.recordEntryTap makes. */
function tap(overrides = {}) {
  return {
    eventId: EVENT,
    lastTapAt: serverTimestamp(),
    taps: increment(1),
    ref: "abcdefgh12345678",
    entryPlatform: "entryninja",
    ...overrides,
  };
}

test("a user can record a tap on a race", async () => {
  // The write the Enter button makes. If this fails, attribution silently
  // records nothing and no Dart test would notice.
  await assertSucceeds(
    setDoc(doc(asUser(), "users", UID, "entryTaps", EVENT), tap(), {
      merge: true,
    })
  );
});

test("tapping the same race again increments", async () => {
  const ref = doc(asUser(), "users", UID, "entryTaps", EVENT);
  await assertSucceeds(setDoc(ref, tap(), { merge: true }));
  await assertSucceeds(setDoc(ref, tap(), { merge: true }));
  const after = await getDoc(ref);
  assert.equal(after.get("taps"), 2);
});

test("a tap cannot carry a client-chosen timestamp", async () => {
  // The cooldown that keeps the public total honest is computed from lastTapAt.
  // A client that could set it could defeat the cooldown at will.
  await assertFails(
    setDoc(
      doc(asUser(), "users", UID, "entryTaps", EVENT),
      tap({ lastTapAt: new Date("2020-01-01T00:00:00Z") }),
      { merge: true }
    )
  );
});

test("a tap cannot be filed under another user", async () => {
  await assertFails(
    setDoc(doc(asUser(), "users", OTHER, "entryTaps", EVENT), tap(), {
      merge: true,
    })
  );
});

test("taps are private to their owner", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users", OTHER, "entryTaps", EVENT), {
      eventId: EVENT,
      lastTapAt: new Date(),
      taps: 3,
      ref: "abcdefgh12345678",
    });
  });
  const db = asUser();
  await assertFails(getDoc(doc(db, "users", OTHER, "entryTaps", EVENT)));
  await assertFails(getDocs(collection(db, "users", OTHER, "entryTaps")));
});

test("a tap document id must match the race it names", async () => {
  await assertFails(
    setDoc(
      doc(asUser(), "users", UID, "entryTaps", EVENT),
      tap({ eventId: "some-other-race" }),
      { merge: true }
    )
  );
});

test("a tap cannot smuggle in extra fields", async () => {
  await assertFails(
    setDoc(
      doc(asUser(), "users", UID, "entryTaps", EVENT),
      tap({ commission: 4200 }),
      { merge: true }
    )
  );
});

test("an update that does not increment is refused", async () => {
  // Otherwise a client could move lastTapAt forward without tapping, which is a
  // fabricated tap as far as the aggregate is concerned.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users", UID, "entryTaps", EVENT), {
      eventId: EVENT,
      lastTapAt: new Date(),
      taps: 5,
      ref: "abcdefgh12345678",
    });
  });
  await assertFails(
    setDoc(
      doc(asUser(), "users", UID, "entryTaps", EVENT),
      tap({ taps: 5 }),
      { merge: true }
    )
  );
});

test("nobody can read or write the aggregate", async () => {
  // raceEntryStats is reporting data, server-written. No screen needs it, and a
  // per-race popularity figure is not something to hand out by default.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "raceEntryStats", EVENT), {
      eventId: EVENT,
      taps: 12,
      tappers: 9,
    });
  });
  const db = asUser();
  await assertFails(getDoc(doc(db, "raceEntryStats", EVENT)));
  await assertFails(getDocs(collection(db, "raceEntryStats")));
  await assertFails(
    setDoc(doc(db, "raceEntryStats", EVENT), { taps: 9999 }, { merge: true })
  );
});
