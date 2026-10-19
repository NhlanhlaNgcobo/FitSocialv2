// Notes.
//
// One document per person at notes/{uid}, written the way
// FirestoreNoteRepository.publish sends it, listed by the tray with a whereIn
// on authorId, and hearted at notes/{uid}/hearts/{hearterUid}. The rules have
// to keep a Note to its author's followers and keep hearts honest.
import fs from "node:fs";
import test, { before, after, beforeEach } from "node:test";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import {
  doc,
  getDoc,
  getDocs,
  setDoc,
  deleteDoc,
  collection,
  query,
  where,
  serverTimestamp,
  Timestamp,
} from "firebase/firestore";

const AUTHOR = "author-uid";
const FOLLOWER = "follower-uid";
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
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users", AUTHOR, "followers", FOLLOWER), { userId: FOLLOWER });
    await setDoc(doc(db, "notes", AUTHOR), {
      authorId: AUTHOR,
      authorName: "Author",
      noteId: "n1",
      text: "Pap and chakalaka",
      promptId: "2026-10-19",
      promptText: "What's your go-to post-run meal?",
      createdAt: Timestamp.now(),
      expiresAt: Timestamp.fromMillis(Date.now() + 24 * 3600 * 1000),
    });
    await setDoc(doc(db, "notes", AUTHOR, "hearts", FOLLOWER), {
      userId: FOLLOWER,
      userName: "Follower",
      noteId: "n1",
    });
  });
});

const db = (uid) => env.authenticatedContext(uid).firestore();

const note = (overrides = {}) => ({
  authorId: AUTHOR,
  authorName: "Author",
  noteId: "n2",
  text: "Parkrun at Zoo Lake",
  promptId: "2026-10-19",
  promptText: "Parkrun, gym or somewhere else this weekend?",
  createdAt: serverTimestamp(),
  expiresAt: Timestamp.fromMillis(Date.now() + 24 * 3600 * 1000),
  ...overrides,
});

test("the fixture is there, so the list checks below mean something", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const snap = await getDoc(doc(ctx.firestore(), "notes", AUTHOR));
    if (!snap.exists()) throw new Error("fixture missing");
  });
});

test("the author and their followers can read a Note, strangers cannot", async () => {
  await assertSucceeds(getDoc(doc(db(AUTHOR), "notes", AUTHOR)));
  await assertSucceeds(getDoc(doc(db(FOLLOWER), "notes", AUTHOR)));
  await assertFails(getDoc(doc(db(STRANGER), "notes", AUTHOR)));
});

test("the tray's whereIn list works for a follower and not for a stranger", async () => {
  const tray = (uid) =>
    getDocs(query(collection(db(uid), "notes"), where("authorId", "in", [AUTHOR])));
  await assertSucceeds(tray(FOLLOWER));
  await assertFails(tray(STRANGER));
});

test("you can write your own Note, within 60 characters and a day", async () => {
  await assertSucceeds(setDoc(doc(db(AUTHOR), "notes", AUTHOR), note()));
  await assertFails(setDoc(doc(db(AUTHOR), "notes", AUTHOR), note({ text: "" })));
  await assertFails(setDoc(doc(db(AUTHOR), "notes", AUTHOR), note({ text: "x".repeat(61) })));
  await assertFails(
    setDoc(
      doc(db(AUTHOR), "notes", AUTHOR),
      note({ expiresAt: Timestamp.fromMillis(Date.now() + 72 * 3600 * 1000) }),
    ),
  );
  await assertFails(setDoc(doc(db(AUTHOR), "notes", AUTHOR), note({ extra: "nope" })));
});

test("nobody writes a Note for somebody else", async () => {
  await assertFails(setDoc(doc(db(FOLLOWER), "notes", AUTHOR), note()));
  await assertFails(
    setDoc(doc(db(FOLLOWER), "notes", FOLLOWER), note({ authorId: AUTHOR })),
  );
  await assertFails(deleteDoc(doc(db(FOLLOWER), "notes", AUTHOR)));
  await assertSucceeds(deleteDoc(doc(db(AUTHOR), "notes", AUTHOR)));
});

test("followers can heart, strangers and the author cannot", async () => {
  const heart = (uid) => ({ userId: uid, userName: "Someone", noteId: "n1" });
  await assertSucceeds(setDoc(doc(db(FOLLOWER), "notes", AUTHOR, "hearts", FOLLOWER), heart(FOLLOWER)));
  await assertFails(setDoc(doc(db(STRANGER), "notes", AUTHOR, "hearts", STRANGER), heart(STRANGER)));
  await assertFails(setDoc(doc(db(AUTHOR), "notes", AUTHOR, "hearts", AUTHOR), heart(AUTHOR)));
  // Nor in somebody else's name.
  await assertFails(setDoc(doc(db(FOLLOWER), "notes", AUTHOR, "hearts", STRANGER), heart(STRANGER)));
});

test("the author lists hearts; a hearter only reads their own", async () => {
  const hearts = (uid) => getDocs(collection(db(uid), "notes", AUTHOR, "hearts"));
  await assertSucceeds(hearts(AUTHOR));
  await assertFails(hearts(FOLLOWER));
  await assertSucceeds(getDoc(doc(db(FOLLOWER), "notes", AUTHOR, "hearts", FOLLOWER)));
  await assertFails(getDoc(doc(db(STRANGER), "notes", AUTHOR, "hearts", FOLLOWER)));
});

test("a heart is taken back by its giver or cleared by the author", async () => {
  await assertFails(deleteDoc(doc(db(STRANGER), "notes", AUTHOR, "hearts", FOLLOWER)));
  await assertSucceeds(deleteDoc(doc(db(AUTHOR), "notes", AUTHOR, "hearts", FOLLOWER)));
  await assertSucceeds(deleteDoc(doc(db(FOLLOWER), "notes", AUTHOR, "hearts", FOLLOWER)));
});

test("a reply is a notification in the author's inbox, in the replier's own name", async () => {
  const reply = (actorId) => ({
    type: "noteReply",
    actorId,
    actorName: "Follower",
    noteText: "Pap and chakalaka",
    replyText: "Same here!",
    createdAt: serverTimestamp(),
    read: false,
  });
  await assertSucceeds(
    setDoc(doc(db(FOLLOWER), "users", AUTHOR, "notifications", "noteReply_a"), reply(FOLLOWER)),
  );
  await assertFails(
    setDoc(doc(db(FOLLOWER), "users", AUTHOR, "notifications", "noteReply_b"), reply(STRANGER)),
  );
});
