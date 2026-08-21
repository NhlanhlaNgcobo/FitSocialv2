// The security rules for user-created running challenges.
//
// Two things are being checked, and they are the two the design turns on.
//
// A private challenge must not leak. Not through discovery, not by reading it
// directly, not through its participant list, and not through the attribution
// records the totals are built from.
//
// And the server must own every number. A participant may create their own row
// and move their own status; they may not write a distance, a streak, a
// completion percentage or a rank. A challenge whose participants can write
// their own rank is not a challenge.
//
// Written the way the app writes them — the payloads below are what
// FirestoreRunningChallengeRepository actually sends, because a rule that reads
// correctly but refuses the real write is the failure mode this file exists
// for. That is exactly what shipped with the dailySteps read rule.
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
  collection,
  setDoc,
  updateDoc,
  getDoc,
  getDocs,
  query,
  where,
  deleteDoc,
  serverTimestamp,
} from "firebase/firestore";

const OWNER = "owner-uid";
const MEMBER = "member-uid";
const INVITEE = "invitee-uid";
const STRANGER = "stranger-uid";

const PUBLIC = "public-challenge";
const PRIVATE = "private-challenge";

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

const challengeDoc = (visibility) => ({
  creatorId: OWNER,
  title: "September 100",
  description: "",
  type: "running",
  goalType: "distance",
  goalValueKm: 100,
  dailyMinimumKm: 1,
  startDayKey: "2026-09-01",
  endDayKey: "2026-09-30",
  utcOffsetMinutes: 120,
  visibility,
  maxParticipants: 500,
  status: "active",
  participantCount: 1,
});

/** Exactly the payload FirestoreRunningChallengeRepository._standingStart sends. */
const standingStart = (userId, challengeId, visibility, status) => ({
  challengeId,
  userId,
  status,
  visibility,
  totalDistanceKm: 0,
  completedDays: 0,
  currentStreak: 0,
  longestStreak: 0,
  completionPercentage: 0,
  rank: 0,
  runCount: 0,
  totalDurationSeconds: 0,
  joinedAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
});

const as = (uid) => env.authenticatedContext(uid).firestore();

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [id, visibility] of [
      [PUBLIC, "public"],
      [PRIVATE, "private"],
    ]) {
      await setDoc(doc(db, "challenges", id), challengeDoc(visibility));
      // The owner is on both; a member is on the private one so there is
      // somebody other than the creator who is entitled to read it.
      await setDoc(
        doc(db, "challenges", id, "participants", OWNER),
        standingStart(OWNER, id, visibility, "active")
      );
      await setDoc(
        doc(db, "challenges", id, "attributions", "run-1"),
        { activityId: "run-1", userId: OWNER, dayKey: "2026-09-02", distanceKm: 5 }
      );
    }
    await setDoc(
      doc(db, "challenges", PRIVATE, "participants", MEMBER),
      standingStart(MEMBER, PRIVATE, "private", "active")
    );
    await setDoc(
      doc(db, "challenges", PRIVATE, "participants", INVITEE),
      standingStart(INVITEE, PRIVATE, "private", "invited")
    );
  });
});

// --- Privacy ---------------------------------------------------------------

test("a public challenge is readable by anyone signed in", async () => {
  await assertSucceeds(getDoc(doc(as(STRANGER), "challenges", PUBLIC)));
});

test("a private challenge is unreadable by a stranger", async () => {
  await assertFails(getDoc(doc(as(STRANGER), "challenges", PRIVATE)));
});

test("a private challenge is readable by its creator, members and invitees", async () => {
  for (const uid of [OWNER, MEMBER, INVITEE]) {
    await assertSucceeds(getDoc(doc(as(uid), "challenges", PRIVATE)));
  }
});

test("signed-out callers read nothing at all", async () => {
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anon, "challenges", PUBLIC)));
  await assertFails(getDoc(doc(anon, "challenges", PRIVATE)));
});

test("discovery pinned to public+active succeeds and returns only public", async () => {
  const snapshot = await assertSucceeds(
    getDocs(
      query(
        collection(as(STRANGER), "challenges"),
        where("visibility", "==", "public"),
        where("status", "==", "active")
      )
    )
  );
  assert.deepEqual(snapshot.docs.map((d) => d.id), [PUBLIC]);
});

test("an unpinned query over challenges fails rather than leaking one", async () => {
  // The property the whole discovery design rests on: rules cannot filter a
  // list, so a query that COULD return a private challenge is refused outright.
  await assertFails(getDocs(collection(as(STRANGER), "challenges")));
  await assertFails(
    getDocs(
      query(
        collection(as(STRANGER), "challenges"),
        where("status", "==", "active")
      )
    )
  );
});

test("the private board really is seeded — the leak tests depend on it", async () => {
  // A list query over a collection that happens to be EMPTY succeeds trivially,
  // because there is no document for the rule to be evaluated against. That
  // makes an assertFails on a list silently meaningless if the seed ever stops
  // working. This test exists so that failure mode reports itself here, as
  // "the seed is broken", rather than one test further down as "the rules leak".
  await env.withSecurityRulesDisabled(async (ctx) => {
    const rows = await getDocs(
      collection(ctx.firestore(), "challenges", PRIVATE, "participants")
    );
    assert.equal(
      rows.size,
      3,
      "expected owner, member and invitee on the private challenge"
    );
    for (const row of rows.docs) {
      assert.equal(
        row.get("visibility"),
        "private",
        `${row.id} is missing the denormalised visibility the read rule reads`
      );
    }
  });
});

test("a private challenge's participants and attributions do not leak", async () => {
  // Reported rather than just asserted. When this failed the first time, the
  // question that mattered was whether the rule had allowed three documents
  // through or whether the query had returned none — and a bare assertFails
  // cannot tell those apart.
  let leaked = null;
  try {
    const rows = await getDocs(
      collection(as(STRANGER), "challenges", PRIVATE, "participants")
    );
    leaked = rows.docs.map((d) => d.id);
  } catch {
    // Denied, which is the whole point.
  }
  assert.equal(
    leaked,
    null,
    `a stranger listed a private board and got back: ${JSON.stringify(leaked)}`
  );

  await assertFails(
    getDoc(doc(as(STRANGER), "challenges", PRIVATE, "participants", MEMBER))
  );
  await assertFails(
    getDoc(doc(as(STRANGER), "challenges", PRIVATE, "attributions", "run-1"))
  );
});

test("a member can read the private board they are on", async () => {
  await assertSucceeds(
    getDocs(collection(as(MEMBER), "challenges", PRIVATE, "participants"))
  );
});

// --- Creating --------------------------------------------------------------

test("a valid public challenge can be created by its own creator", async () => {
  await assertSucceeds(
    setDoc(doc(as(MEMBER), "challenges", "new-one"), {
      ...challengeDoc("public"),
      creatorId: MEMBER,
      participantCount: 0,
    })
  );
});

test("a challenge cannot be created for somebody else", async () => {
  await assertFails(
    setDoc(doc(as(MEMBER), "challenges", "new-one"), {
      ...challengeDoc("public"),
      participantCount: 0,
    })
  );
});

test("a challenge cannot be born finished, populated or backwards", async () => {
  const base = { ...challengeDoc("public"), creatorId: MEMBER, participantCount: 0 };

  await assertFails(
    setDoc(doc(as(MEMBER), "challenges", "a"), { ...base, status: "completed" })
  );
  await assertFails(
    setDoc(doc(as(MEMBER), "challenges", "b"), { ...base, participantCount: 40 })
  );
  await assertFails(
    setDoc(doc(as(MEMBER), "challenges", "c"), {
      ...base,
      startDayKey: "2026-09-30",
      endDayKey: "2026-09-01",
    })
  );
  await assertFails(
    setDoc(doc(as(MEMBER), "challenges", "d"), { ...base, goalValueKm: 0 })
  );
  await assertFails(
    setDoc(doc(as(MEMBER), "challenges", "e"), { ...base, title: "hi" })
  );
});

test("the creator may retitle or cancel, and nothing else", async () => {
  const ref = doc(as(OWNER), "challenges", PUBLIC);

  await assertSucceeds(updateDoc(ref, { title: "October 100" }));
  await assertSucceeds(updateDoc(ref, { status: "cancelled" }));

  // The terms of the competition are fixed once people have joined.
  await assertFails(updateDoc(ref, { goalValueKm: 5 }));
  await assertFails(updateDoc(ref, { endDayKey: "2026-12-31" }));
  await assertFails(updateDoc(ref, { visibility: "private" }));
  await assertFails(updateDoc(ref, { participantCount: 999 }));
  // And "completed" is the engine's word, not the creator's.
  await assertFails(updateDoc(ref, { status: "completed" }));
});

test("nobody may update somebody else's challenge, or delete any", async () => {
  await assertFails(
    updateDoc(doc(as(STRANGER), "challenges", PUBLIC), { title: "Mine now" })
  );
  await assertFails(deleteDoc(doc(as(OWNER), "challenges", PUBLIC)));
});

// --- Joining ---------------------------------------------------------------

test("anyone may join a public challenge from a standing start", async () => {
  await assertSucceeds(
    setDoc(
      doc(as(STRANGER), "challenges", PUBLIC, "participants", STRANGER),
      standingStart(STRANGER, PUBLIC, "public", "active")
    )
  );
});

test("a join carrying any progress is refused", async () => {
  const cases = {
    totalDistanceKm: 40,
    completedDays: 9,
    currentStreak: 5,
    longestStreak: 5,
    completionPercentage: 80,
    rank: 1,
    runCount: 12,
  };

  for (const [field, value] of Object.entries(cases)) {
    await assertFails(
      setDoc(
        doc(as(STRANGER), "challenges", PUBLIC, "participants", STRANGER),
        { ...standingStart(STRANGER, PUBLIC, "public", "active"), [field]: value }
      ),
      `a join pre-loaded with ${field} must be refused`
    );
  }
});

test("nobody may self-join a private challenge", async () => {
  await assertFails(
    setDoc(
      doc(as(STRANGER), "challenges", PRIVATE, "participants", STRANGER),
      standingStart(STRANGER, PRIVATE, "private", "active")
    )
  );
});

test("nobody may create a participant record for somebody else", async () => {
  await assertFails(
    setDoc(
      doc(as(STRANGER), "challenges", PUBLIC, "participants", MEMBER),
      standingStart(MEMBER, PUBLIC, "public", "active")
    )
  );
});

test("only the creator may invite, and only as an invitation", async () => {
  await assertSucceeds(
    setDoc(
      doc(as(OWNER), "challenges", PRIVATE, "participants", STRANGER),
      standingStart(STRANGER, PRIVATE, "private", "invited")
    )
  );

  // A member is not an inviter.
  await assertFails(
    setDoc(
      doc(as(MEMBER), "challenges", PRIVATE, "participants", "someone-new"),
      standingStart("someone-new", PRIVATE, "private", "invited")
    )
  );

  // And an "invitation" that arrives already active is a forced join.
  await assertFails(
    setDoc(
      doc(as(OWNER), "challenges", PRIVATE, "participants", "another-new"),
      standingStart("another-new", PRIVATE, "private", "active")
    )
  );
});

// --- Status transitions ----------------------------------------------------

test("an invitee may accept or decline their own invitation", async () => {
  await assertSucceeds(
    updateDoc(
      doc(as(INVITEE), "challenges", PRIVATE, "participants", INVITEE),
      { status: "active", joinedAt: serverTimestamp() }
    )
  );

  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(
      doc(ctx.firestore(), "challenges", PRIVATE, "participants", INVITEE),
      standingStart(INVITEE, PRIVATE, "private", "invited")
    );
  });

  await assertSucceeds(
    updateDoc(
      doc(as(INVITEE), "challenges", PRIVATE, "participants", INVITEE),
      { status: "declined" }
    )
  );
});

test("an active member may leave", async () => {
  await assertSucceeds(
    updateDoc(
      doc(as(MEMBER), "challenges", PRIVATE, "participants", MEMBER),
      { status: "left" }
    )
  );
});

test("nobody may move somebody else's status", async () => {
  await assertFails(
    updateDoc(
      doc(as(OWNER), "challenges", PRIVATE, "participants", MEMBER),
      { status: "left" }
    )
  );
});

test("an invitation cannot be jumped straight to completed", async () => {
  await assertFails(
    updateDoc(
      doc(as(INVITEE), "challenges", PRIVATE, "participants", INVITEE),
      { status: "completed" }
    )
  );
});

// --- The numbers the server owns -------------------------------------------

test("a participant cannot write any figure the board is ordered by", async () => {
  const ref = doc(as(MEMBER), "challenges", PRIVATE, "participants", MEMBER);

  for (const field of [
    "totalDistanceKm",
    "completedDays",
    "currentStreak",
    "longestStreak",
    "completionPercentage",
    "rank",
    "runCount",
    "totalDurationSeconds",
    "lastQualifiedDayKey",
  ]) {
    await assertFails(
      updateDoc(ref, { [field]: field === "lastQualifiedDayKey" ? "2026-09-30" : 99 }),
      `${field} must be server-owned`
    );
  }

  // Including smuggled alongside a legitimate status change.
  await assertFails(updateDoc(ref, { status: "left", rank: 1 }));
});

test("nobody may write a day record or an attribution", async () => {
  await assertFails(
    setDoc(
      doc(
        as(MEMBER),
        "challenges", PRIVATE, "participants", MEMBER, "days", "2026-09-02"
      ),
      { dayKey: "2026-09-02", distanceKm: 42, qualified: true }
    )
  );

  // The attribution records are what every total is rebuilt from, so writing
  // one would be manufacturing distance that was never run.
  await assertFails(
    setDoc(
      doc(as(MEMBER), "challenges", PRIVATE, "attributions", "forged"),
      { activityId: "forged", userId: MEMBER, dayKey: "2026-09-02", distanceKm: 99 }
    )
  );
  await assertFails(
    deleteDoc(doc(as(OWNER), "challenges", PRIVATE, "attributions", "run-1"))
  );
});

test("a participant record can never be deleted", async () => {
  await assertFails(
    deleteDoc(doc(as(MEMBER), "challenges", PRIVATE, "participants", MEMBER))
  );
});
