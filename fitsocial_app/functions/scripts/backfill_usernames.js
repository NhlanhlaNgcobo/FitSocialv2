#!/usr/bin/env node
/**
 * Creates a `usernames` reservation for every existing profile.
 *
 * REQUIRED once, before deploying the username security rules. Those rules
 * refuse any profile write whose handle the caller does not hold a reservation
 * for, so an account that predates the reservation collection cannot save its
 * own profile — not even a bio edit — until this has run.
 *
 * Usage (from fitsocial_app/functions):
 *   node scripts/backfill_usernames.js          # report only, writes nothing
 *   node scripts/backfill_usernames.js --commit # actually write
 *
 * Auth: needs Application Default Credentials with write access to the project.
 *   gcloud auth application-default login
 *   set GOOGLE_CLOUD_PROJECT=fitsocialv2
 * or point GOOGLE_APPLICATION_CREDENTIALS at a service-account key file.
 *
 * Collisions are reported, never resolved. Two accounts already displaying the
 * same handle is exactly the situation the reservation collection exists to
 * prevent, and picking a winner is not a script's call to make — the first
 * account to have claimed it keeps it here, and the report tells you who else
 * needs contacting.
 *
 * Re-running is safe: an existing reservation is left alone.
 */

const admin = require("firebase-admin");

const BATCH_LIMIT = 400;

/**
 * Must agree exactly with normalizeUsername in
 * lib/features/auth/domain/username.dart — this decides document ids, and a
 * second opinion about which string a handle maps to would create the very
 * collision the collection prevents.
 */
function normalizeUsername(raw) {
  return String(raw ?? "")
    .trim()
    .replace(/^@+/, "")
    .trim()
    .toLowerCase();
}

async function main() {
  const commit = process.argv.includes("--commit");

  const projectId =
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.GCLOUD_PROJECT ||
    process.env.FIREBASE_PROJECT;

  admin.initializeApp(projectId ? { projectId } : undefined);
  const db = admin.firestore();

  const users = await db.collection("users").get();
  if (users.empty) {
    console.log("No user profiles found — nothing to back-fill.");
    return;
  }

  const existing = await db.collection("usernames").get();
  const reserved = new Map();
  for (const doc of existing.docs) {
    reserved.set(doc.id, doc.data()?.uid ?? null);
  }

  const toWrite = [];
  const toNormalize = [];
  const missingHandle = [];
  const collisions = [];
  let alreadyReserved = 0;

  // Oldest profile first, so that when two accounts share a handle the one
  // that has been using it longest is the one that keeps it.
  const ordered = users.docs.slice().sort((a, b) => {
    const at = a.data()?.createdAt?.toMillis?.() ?? 0;
    const bt = b.data()?.createdAt?.toMillis?.() ?? 0;
    return at - bt;
  });

  for (const doc of ordered) {
    const stored = doc.data()?.handle;
    const handle = normalizeUsername(stored);

    if (!handle) {
      missingHandle.push(doc.id);
      continue;
    }

    // The security rules compare the stored handle against the one being
    // written, as raw strings — they have no way to normalize. A profile still
    // holding "@Bear" would therefore read as a rename every time it saved,
    // and be refused for not stamping a rename it is not making. Writing the
    // normalized form back is what makes "stored handles are normalized" a
    // fact the rules can rely on.
    if (stored !== handle) {
      toNormalize.push({ uid: doc.id, from: stored, to: handle });
    }

    const holder = reserved.get(handle);
    if (holder !== undefined) {
      if (holder === doc.id) {
        alreadyReserved++;
      } else {
        collisions.push({ handle, uid: doc.id, heldBy: holder });
      }
      continue;
    }

    reserved.set(handle, doc.id);
    toWrite.push({ handle, uid: doc.id });
  }

  console.log(`Profiles scanned:        ${users.size}`);
  console.log(`Already reserved:        ${alreadyReserved}`);
  console.log(`Reservations to write:   ${toWrite.length}`);
  console.log(`Handles to normalize:    ${toNormalize.length}`);
  console.log(`Profiles with no handle: ${missingHandle.length}`);
  console.log(`Collisions:              ${collisions.length}`);

  if (toNormalize.length > 0) {
    console.log("\nThese stored handles are not in canonical form:");
    for (const h of toNormalize) {
      console.log(`  ${h.uid}: "${h.from}" -> "${h.to}"`);
    }
  }

  if (missingHandle.length > 0) {
    console.log(
      "\nThese profiles carry no handle. They can still read the app, but " +
        "cannot save a profile until they pick one:"
    );
    for (const uid of missingHandle) console.log(`  ${uid}`);
  }

  if (collisions.length > 0) {
    console.log(
      "\nThese accounts want a handle another account already holds. The " +
        "holder listed keeps it; the uid listed needs a new one and cannot " +
        "save its profile until it picks one:"
    );
    for (const c of collisions) {
      console.log(`  @${c.handle}: ${c.uid} loses to ${c.heldBy}`);
    }
  }

  if (!commit) {
    console.log("\nDry run — nothing written. Re-run with --commit to apply.");
    return;
  }

  for (let i = 0; i < toWrite.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    for (const entry of toWrite.slice(i, i + BATCH_LIMIT)) {
      batch.set(db.collection("usernames").doc(entry.handle), {
        uid: entry.uid,
        claimedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    console.log(
      `Reservations ${Math.min(i + BATCH_LIMIT, toWrite.length)}/${toWrite.length}`
    );
  }

  for (let i = 0; i < toNormalize.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    for (const entry of toNormalize.slice(i, i + BATCH_LIMIT)) {
      // handleChangedAt is deliberately not touched: normalizing the stored
      // form is not a rename, and stamping it here would start a 14-day
      // cooldown against a user who did nothing.
      batch.set(
        db.collection("users").doc(entry.uid),
        { handle: entry.to },
        { merge: true }
      );
    }
    await batch.commit();
    console.log(
      `Normalized ${Math.min(i + BATCH_LIMIT, toNormalize.length)}/${toNormalize.length}`
    );
  }

  console.log("\nDone.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
