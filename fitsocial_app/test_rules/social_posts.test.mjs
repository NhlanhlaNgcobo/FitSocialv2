// Poll votes and meetup RSVPs.
//
// Both are written by people who don't own the post, one key at a time, the
// way FirestoreContentRepository.setPollVote and setMeetupRsvp send them. The
// rules have to let exactly that through and nothing that rides along with it.
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
  deleteField,
  serverTimestamp,
  Timestamp,
} from "firebase/firestore";

const AUTHOR = "author-uid";
const VOTER = "voter-uid";
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
    await setDoc(doc(db, "posts", "poll"), {
      authorId: AUTHOR,
      postType: "poll",
      caption: "Legs or back?",
      poll: { question: "Legs or back?", options: ["Legs", "Back"] },
      pollVotes: { [OTHER]: 1 },
      likesCount: 0,
      commentsCount: 0,
    });
    await setDoc(doc(db, "posts", "meetup"), {
      authorId: AUTHOR,
      postType: "meetup",
      caption: "Beachfront run",
      meetup: {
        title: "Beachfront run",
        place: "Durban",
        startsAt: Timestamp.fromDate(new Date("2026-09-27T04:00:00Z")),
      },
      rsvps: {},
      likesCount: 0,
      commentsCount: 0,
    });
    await setDoc(doc(db, "posts", "text"), {
      authorId: AUTHOR,
      postType: "text",
      caption: "Rest day",
      likesCount: 0,
      commentsCount: 0,
    });
  });
});

const as = (uid, id) => doc(env.authenticatedContext(uid).firestore(), "posts", id);

test("a voter can vote, change their vote and take it back", async () => {
  await assertSucceeds(updateDoc(as(VOTER, "poll"), { [`pollVotes.${VOTER}`]: 0 }));
  await assertSucceeds(updateDoc(as(VOTER, "poll"), { [`pollVotes.${VOTER}`]: 1 }));
  await assertSucceeds(
    updateDoc(as(VOTER, "poll"), { [`pollVotes.${VOTER}`]: deleteField() })
  );
});

test("nobody can vote for someone else or remove their vote", async () => {
  await assertFails(updateDoc(as(VOTER, "poll"), { [`pollVotes.${OTHER}`]: 0 }));
  await assertFails(
    updateDoc(as(VOTER, "poll"), { [`pollVotes.${OTHER}`]: deleteField() })
  );
});

test("a vote must be one of the poll's answers", async () => {
  await assertFails(updateDoc(as(VOTER, "poll"), { [`pollVotes.${VOTER}`]: 2 }));
  await assertFails(updateDoc(as(VOTER, "poll"), { [`pollVotes.${VOTER}`]: -1 }));
  await assertFails(
    updateDoc(as(VOTER, "poll"), { [`pollVotes.${VOTER}`]: "Legs" })
  );
});

test("a vote can't carry another change with it", async () => {
  await assertFails(
    updateDoc(as(VOTER, "poll"), {
      [`pollVotes.${VOTER}`]: 0,
      caption: "Something else",
    })
  );
});

test("only a poll takes votes", async () => {
  await assertFails(updateDoc(as(VOTER, "text"), { [`pollVotes.${VOTER}`]: 0 }));
});

test("anyone can say they're in for a meetup, and take it back", async () => {
  await assertSucceeds(
    updateDoc(as(VOTER, "meetup"), { [`rsvps.${VOTER}`]: serverTimestamp() })
  );
  await assertSucceeds(
    updateDoc(as(VOTER, "meetup"), { [`rsvps.${VOTER}`]: deleteField() })
  );
});

test("an RSVP is for yourself, and stamped by the server", async () => {
  await assertFails(
    updateDoc(as(VOTER, "meetup"), { [`rsvps.${OTHER}`]: serverTimestamp() })
  );
  await assertFails(
    updateDoc(as(VOTER, "meetup"), {
      [`rsvps.${VOTER}`]: Timestamp.fromDate(new Date("2020-01-01")),
    })
  );
});

test("only a meetup takes RSVPs", async () => {
  await assertFails(
    updateDoc(as(VOTER, "poll"), { [`rsvps.${VOTER}`]: serverTimestamp() })
  );
});
