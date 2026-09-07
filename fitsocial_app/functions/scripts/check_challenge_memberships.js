#!/usr/bin/env node
/**
 * Checks the challenge-membership copies against the rows they came from.
 *
 * The hub reads `users/{uid}/challengeMemberships`, which the engine keeps as a
 * copy of each participant row (see mirrorMembership in running_challenges.js).
 * A copy is an index, never the truth — so the failure worth watching for is
 * drift: a row with no copy, which hides a challenge from the person on it, or
 * a copy that disagrees with its row, which shows them a stale standing.
 *
 * Reads only. Run it after the backfill, and any time the hub looks wrong:
 *
 *   npm run check:memberships
 *
 * Auth: Application Default Credentials, as the backfill needs.
 *   gcloud auth application-default login
 *   set GOOGLE_CLOUD_PROJECT=fitsocialv2
 *
 * A row missing its copy is repaired by re-running
 * `npm run backfill:memberships -- --commit`, which is safe to repeat.
 */

const admin = require("firebase-admin");

const projectId =
  process.env.GOOGLE_CLOUD_PROJECT ||
  process.env.GCLOUD_PROJECT ||
  process.env.FIREBASE_PROJECT;

admin.initializeApp(projectId ? { projectId } : undefined);
const db = admin.firestore();

const iso = (v) => (v && v.toDate ? v.toDate().toISOString() : "-");

async function main() {
  const participants = await db.collectionGroup("participants").get();
  const mirrored = await db.collectionGroup("challengeMemberships").get();

  console.log(`participant rows : ${participants.size}`);
  console.log(`membership copies: ${mirrored.size}\n`);

  if (mirrored.empty) {
    console.log("No copies exist -- the backfill has not been run.");
    return;
  }

  // Every participant row must have a copy, and every copy must agree with the
  // row it was taken from. A copy that disagrees is worse than a missing one.
  const copies = new Map();
  for (const doc of mirrored.docs) {
    const d = doc.data();
    copies.set(`${d.userId}/${d.challengeId}`, d);
  }

  let missing = 0;
  let disagreeing = 0;
  for (const doc of participants.docs) {
    const challengeId = doc.ref.parent.parent?.id;
    const key = `${doc.id}/${challengeId}`;
    const copy = copies.get(key);
    if (!copy) {
      console.log(`  MISSING  ${key}`);
      missing += 1;
      continue;
    }
    const row = doc.data();
    const same =
      copy.status === row.status &&
      copy.rank === row.rank &&
      copy.totalDistanceKm === row.totalDistanceKm;
    if (!same) {
      console.log(
        `  STALE    ${key}  copy=${copy.status}/${copy.rank}/${copy.totalDistanceKm}` +
          `  row=${row.status}/${row.rank}/${row.totalDistanceKm}`
      );
      disagreeing += 1;
      continue;
    }
    console.log(
      `  ok       ${doc.id.slice(0, 8)} -> ${challengeId}  ${row.status}  ` +
        `mirroredAt=${iso(copy.mirroredAt)}`
    );
  }

  const orphans = copies.size - (participants.size - missing);
  console.log(
    `\nmissing: ${missing}   stale: ${disagreeing}   copies with no row: ${orphans}`
  );
}

main().then(() => process.exit(0), (e) => { console.error(e.message); process.exit(1); });
