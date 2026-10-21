// Comment likes.
//
// Written by people who don't own the comment, one uid at a time, the way
// FirestoreContentRepository.setCommentLike sends them with arrayUnion and
// arrayRemove. The rules have to let exactly that through and nothing that
// rides along with it.
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
  arrayUnion,
  arrayRemove,
} from "firebase/firestore";

const POST_AUTHOR = "post-author-uid";
const COMMENTER = "commenter-uid";
const LIKER = "liker-uid";
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
    await setDoc(doc(db, "posts", "p1"), { authorId: POST_AUTHOR, caption: "Leg day" });
    // One comment nobody has liked yet, written the way comments were before
    // likes existed — no likedBy field at all.
    await setDoc(doc(db, "posts", "p1", "comments", "fresh"), {
      authorId: COMMENTER,
      text: "Strong!",
    });
    await setDoc(doc(db, "posts", "p1", "comments", "liked"), {
      authorId: COMMENTER,
      text: "Nice",
      likedBy: [OTHER],
    });
  });
});

const comment = (uid, id) =>
  doc(env.authenticatedContext(uid).firestore(), "posts", "p1", "comments", id);

test("anyone can like a comment, including one nobody has liked yet", async () => {
  await assertSucceeds(updateDoc(comment(LIKER, "fresh"), { likedBy: arrayUnion(LIKER) }));
  await assertSucceeds(updateDoc(comment(LIKER, "liked"), { likedBy: arrayUnion(LIKER) }));
});

test("liking twice and unliking are both allowed", async () => {
  await assertSucceeds(updateDoc(comment(LIKER, "liked"), { likedBy: arrayUnion(LIKER) }));
  await assertSucceeds(updateDoc(comment(LIKER, "liked"), { likedBy: arrayUnion(LIKER) }));
  await assertSucceeds(updateDoc(comment(LIKER, "liked"), { likedBy: arrayRemove(LIKER) }));
});

test("nobody can like for someone else or remove their like", async () => {
  await assertFails(updateDoc(comment(LIKER, "fresh"), { likedBy: arrayUnion("ghost") }));
  await assertFails(updateDoc(comment(LIKER, "liked"), { likedBy: arrayRemove(OTHER) }));
  await assertFails(updateDoc(comment(LIKER, "liked"), { likedBy: [LIKER] }));
});

test("a like can't carry another change with it", async () => {
  await assertFails(
    updateDoc(comment(LIKER, "fresh"), { likedBy: arrayUnion(LIKER), text: "edited" }),
  );
  await assertFails(updateDoc(comment(LIKER, "fresh"), { text: "edited" }));
});

test("signed-out visitors can't like", async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertFails(
    updateDoc(doc(db, "posts", "p1", "comments", "fresh"), { likedBy: arrayUnion("anon") }),
  );
});

const notification = (uid, id) =>
  doc(env.authenticatedContext(uid).firestore(), "users", COMMENTER, "notifications", id);

test("the liker can tell the comment's author, and take it back", async () => {
  const id = `commentLike_fresh_${LIKER}`;
  await assertSucceeds(
    setDoc(notification(LIKER, id), {
      type: "commentLike",
      actorId: LIKER,
      actorName: "Liker",
      postId: "p1",
      commentId: "fresh",
      read: false,
    }),
  );
  await assertSucceeds(deleteDoc(notification(LIKER, id)));
});

// Pulse comments: the same like, but only for the Pulse's audience — its
// author and the people who follow them.
async function seedPulse() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "pulses", "u1"), { authorId: POST_AUTHOR });
    await setDoc(doc(db, "pulses", "u1", "comments", "c1"), {
      authorId: COMMENTER,
      text: "Looking strong",
    });
    await setDoc(doc(db, "users", POST_AUTHOR, "followers", LIKER), { createdAt: 1 });
  });
}

const pulseComment = (uid) =>
  doc(env.authenticatedContext(uid).firestore(), "pulses", "u1", "comments", "c1");

test("a follower can like and unlike a Pulse comment", async () => {
  await seedPulse();
  await assertSucceeds(updateDoc(pulseComment(LIKER), { likedBy: arrayUnion(LIKER) }));
  await assertSucceeds(updateDoc(pulseComment(LIKER), { likedBy: arrayRemove(LIKER) }));
  await assertSucceeds(updateDoc(pulseComment(POST_AUTHOR), { likedBy: arrayUnion(POST_AUTHOR) }));
});

test("someone outside the Pulse's audience can't like its comments", async () => {
  await seedPulse();
  await assertFails(updateDoc(pulseComment(OTHER), { likedBy: arrayUnion(OTHER) }));
});

test("a Pulse comment like can't edit the comment or add anyone else", async () => {
  await seedPulse();
  await assertFails(
    updateDoc(pulseComment(LIKER), { likedBy: arrayUnion(LIKER), text: "edited" }),
  );
  await assertFails(updateDoc(pulseComment(LIKER), { likedBy: arrayUnion("ghost") }));
  await assertFails(updateDoc(pulseComment(LIKER), { text: "edited" }));
});

test("nobody can send a comment-like notification in someone else's name", async () => {
  await assertFails(
    setDoc(notification(LIKER, `commentLike_fresh_${OTHER}`), {
      type: "commentLike",
      actorId: OTHER,
      actorName: "Other",
      postId: "p1",
      commentId: "fresh",
      read: false,
    }),
  );
});
