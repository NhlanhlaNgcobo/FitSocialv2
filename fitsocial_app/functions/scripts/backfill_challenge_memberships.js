#!/usr/bin/env node
/**
 * Copies every existing participant row to `users/{uid}/challengeMemberships`.
 *
 * REQUIRED once, alongside the deploy that adds mirrorMembership to
 * `running_challenges.js`. The engine writes that copy whenever a participant
 * row changes, but nothing changes the rows of people who joined before it
 * existed — so without this pass, everybody already on a challenge stays
 * missing from their own hub until the next time their standing moves.
 *
 * Why the copy exists at all: the hub used to answer "which challenges am I
 * on?" with a collection-group query across every challenge's participants,
 * and that query cannot be authorised. On a collection-group list, security
 * rules see neither the document nor the path wildcards, so the only rule that
 * admits the query admits any signed-in caller to every participant row in the
 * database. The query was refused for everyone and the list rendered empty from
 * the day it shipped. See the note in firestore.rules.
 *
 * Usage (from fitsocial_app/functions):
 *   node scripts/backfill_challenge_memberships.js          # report only
 *   node scripts/backfill_challenge_memberships.js --commit # actually write
 *
 * Call node directly for the write, NOT `npm run backfill:memberships --
 * --commit`. npm expands a bare `--commit` into its own `--commit-hooks`
 * option and never passes it on, so that form silently runs the report and
 * writes nothing -- it looks like it worked, and the last line is what tells
 * you it did not. The npm alias is for the report.
 *
 * Auth: needs Application Default Credentials with write access to the project.
 *   gcloud auth application-default login
 *   set GOOGLE_CLOUD_PROJECT=fitsocialv2
 *
 * Re-running is safe. Each copy is written at a derived id — the challenge's —
 * so a second pass overwrites what the first one wrote rather than doubling it,
 * and a copy the engine has since refreshed is simply rewritten with the same
 * contents it already had.
 */

const admin = require("firebase-admin");

const BATCH_LIMIT = 400;

async function main() {
  const commit = process.argv.includes("--commit");

  const projectId =
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.GCLOUD_PROJECT ||
    process.env.FIREBASE_PROJECT;

  admin.initializeApp(projectId ? { projectId } : undefined);
  const db = admin.firestore();

  // The Admin SDK bypasses security rules, which is exactly why the sweep the
  // app can no longer make is still available here.
  const participants = await db.collectionGroup("participants").get();
  if (participants.empty) {
    console.log("No participant rows found — nothing to back-fill.");
    return;
  }

  const pending = [];
  const skipped = [];

  for (const doc of participants.docs) {
    const challengeRef = doc.ref.parent.parent;
    // A participant row is always two levels under a challenge. One that is not
    // says the tree is shaped differently than this script believes, and
    // guessing where the copy belongs is not a script's call to make.
    if (!challengeRef) {
      skipped.push(`${doc.ref.path} (no parent challenge)`);
      continue;
    }

    // The document id is the uid — every write rule pins it — so it is trusted
    // over the field, which is a copy.
    const userId = doc.id;
    const data = doc.data() || {};
    if (!userId) {
      skipped.push(`${doc.ref.path} (no user id)`);
      continue;
    }

    pending.push({
      ref: db
        .collection("users")
        .doc(userId)
        .collection("challengeMemberships")
        .doc(challengeRef.id),
      data: {
        ...data,
        challengeId: challengeRef.id,
        userId,
        mirroredAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      label: `${userId.slice(0, 8)} -> ${challengeRef.id} (${
        data.status || "?"
      })`,
    });
  }

  console.log(`participant rows: ${participants.size}`);
  console.log(`copies to write:  ${pending.length}`);
  for (const item of pending) console.log(`  ${item.label}`);

  if (skipped.length) {
    console.log(`\nskipped ${skipped.length}:`);
    for (const line of skipped) console.log(`  ${line}`);
  }

  if (!commit) {
    console.log("\nReport only. Re-run with --commit to write.");
    return;
  }

  let written = 0;
  for (let i = 0; i < pending.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    for (const item of pending.slice(i, i + BATCH_LIMIT)) {
      batch.set(item.ref, item.data);
    }
    await batch.commit();
    written += Math.min(BATCH_LIMIT, pending.length - i);
  }

  console.log(`\nWrote ${written} membership copies.`);
}

main().then(
  () => process.exit(0),
  (err) => {
    console.error(err);
    process.exit(1);
  }
);
