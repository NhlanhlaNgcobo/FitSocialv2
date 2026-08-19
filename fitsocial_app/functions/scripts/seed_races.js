#!/usr/bin/env node
/**
 * Loads a JSON file of races into the Firestore `raceEvents` collection.
 *
 * This is how the running calendar is populated. The collection is closed to
 * clients by firestore.rules, so this script — running under the Admin SDK,
 * which bypasses rules — and a moderator promoting a submission are the only two
 * ways a race gets listed.
 *
 * Usage (from fitsocial_app/functions):
 *   npm run seed:races                        # validate and print, write nothing
 *   npm run seed:races -- --write             # actually write to Firestore
 *   npm run seed:races -- --file ../my.json   # validate some other file
 *   node scripts/seed_races.js --write --prune  # also delete listings dropped
 *                                               # from the file
 *
 * Validation is the default and writing needs --write, because this script
 * writes to the live project and a shell that swallows an argument should cost
 * you a re-run rather than a production write.
 *
 * Start from data/race_events.example.json:
 *   cp data/race_events.example.json data/race_events.json
 *
 * Where the real data comes from — none of it is scraped:
 *   - Provincial fixture lists published by the ASA affiliates (AGN, CGA, WPA,
 *     KZNA and the rest). Annual, authoritative, and PDF, so transcription is
 *     a human job.
 *   - Entry platform listings (Entry Ninja, RaceTec, Racelink) for fees, entry
 *     links and status changes.
 *   - Submissions from users and organisers, which land in `raceSubmissions`
 *     and are promoted into a row of this file once checked.
 *
 * Auth: needs Application Default Credentials with write access to the project.
 *   gcloud auth application-default login
 *   set GOOGLE_CLOUD_PROJECT=fitsocialv2
 * or point GOOGLE_APPLICATION_CREDENTIALS at a service-account key file.
 *
 * Renaming a race needs --prune. Ids are derived from the name, so a rename writes
 * a new document and leaves the old one behind as a duplicate the app will happily
 * show. --prune deletes any curated listing that is no longer in the file, which is
 * the only way to retire one. It never touches a listing whose source is not
 * 'curated', so a race a moderator promoted out of raceSubmissions is safe from it.
 *
 * Re-running is safe. Document ids are derived from the race name and its date,
 * so editing a fee in the file and running again updates that race rather than
 * listing it twice. Writes use merge, so a field removed from the file keeps its
 * old value in Firestore — to clear one, set it explicitly or delete the
 * document in the console.
 */

const fs = require("node:fs");
const path = require("node:path");
// The modular subpaths rather than the `admin.firestore()` namespace. Both are
// available from firebase-admin v11 onwards, and only these still exist in v14 —
// the root export dropped `.firestore` entirely, which is what made an earlier
// version of this script die with "admin.firestore is not a function".
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { COLLECTION, normaliseAll } = require("../races_ingest");

const BATCH_LIMIT = 400;
const DEFAULT_FILE = path.join(__dirname, "..", "data", "race_events.json");

/**
 * Reads the arguments, defaulting to validate-only.
 *
 * Writing needs an explicit `--write`. That is the opposite of the obvious
 * design, and deliberately so: `npm run seed:races -- --dry-run` does not
 * reliably deliver its `--` through every shell, and a safety flag that can be
 * silently dropped in front of a script that writes to the live project is not a
 * safety flag. Losing `--write` costs a re-run; losing `--dry-run` used to cost
 * a production write nobody asked for.
 *
 * `--dry-run` is still accepted so the habit and the older docs keep working.
 */
function parseArgs(argv) {
  const args = { write: false, prune: false, file: DEFAULT_FILE };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--write") args.write = true;
    else if (argv[i] === "--dry-run") args.write = false;
    else if (argv[i] === "--prune") args.prune = true;
    else if (argv[i] === "--file") args.file = argv[++i];
    else throw new Error(`Unknown argument: ${argv[i]}`);
  }
  if (args.prune && !args.write) {
    // Refused rather than ignored: somebody who typed --prune means to delete,
    // and silently not deleting would leave them believing the calendar is clean.
    throw new Error("--prune only works with --write.");
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (!fs.existsSync(args.file)) {
    console.error(`No such file: ${args.file}`);
    console.error(
      "Copy data/race_events.example.json to data/race_events.json to start."
    );
    process.exitCode = 1;
    return;
  }

  let rows;
  try {
    rows = JSON.parse(fs.readFileSync(args.file, "utf8"));
  } catch (error) {
    console.error(`${args.file} is not valid JSON: ${error.message}`);
    process.exitCode = 1;
    return;
  }

  // Validated before Firebase is touched, so a bad file costs nothing and the
  // default validate-only run needs no credentials at all.
  let events;
  try {
    events = normaliseAll(rows);
  } catch (error) {
    console.error(`Validation failed — nothing was written.\n  ${error.message}`);
    process.exitCode = 1;
    return;
  }

  const now = new Date();
  const past = events.filter((event) => (event.doc.endAt ?? event.doc.startAt) < now);
  if (past.length > 0) {
    // A warning rather than an error. Loading a past race is legitimate — it is
    // how last season stays on the record — but it is also what a mistyped year
    // looks like, so it gets said out loud.
    console.warn(
      `Note: ${past.length} race(s) are already in the past and will not appear ` +
        `in the app's upcoming list:`
    );
    for (const event of past.slice(0, 5)) {
      console.warn(`  ${event.doc.startAt.toISOString().slice(0, 10)} ${event.doc.name}`);
    }
  }

  console.log(`${events.length} race(s) validated from ${path.basename(args.file)}.`);

  if (!args.write) {
    for (const event of events) {
      console.log(
        `  ${event.doc.startAt.toISOString().slice(0, 10)}  ` +
          `${event.doc.province.padEnd(3)}  ` +
          `${event.doc.distanceBuckets.join(",").padEnd(22)}  ${event.doc.name}`
      );
    }
    console.log(
      "Nothing written. Re-run with --write to load these into Firestore."
    );
    return;
  }

  const projectId =
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.GCLOUD_PROJECT ||
    process.env.FIREBASE_PROJECT;

  initializeApp(projectId ? { projectId } : undefined);
  const db = getFirestore();

  console.log(
    `Writing to ${COLLECTION}` + (projectId ? ` (project ${projectId})...` : "...")
  );

  let written = 0;
  for (let start = 0; start < events.length; start += BATCH_LIMIT) {
    const batch = db.batch();
    for (const event of events.slice(start, start + BATCH_LIMIT)) {
      batch.set(
        db.collection(COLLECTION).doc(event.id),
        {
          ...event.doc,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }
    await batch.commit();
    written += Math.min(BATCH_LIMIT, events.length - start);
    console.log(`  ${written}/${events.length}`);
  }

  if (args.prune) await prune(db, events);

  console.log("Done. Pull to refresh on the Races screen to see them.");
}

/**
 * Deletes curated listings that are no longer in the seed file.
 *
 * Scoped to source == 'curated' on purpose. That is the set this file owns; a
 * listing promoted out of a user submission was never in the file and must not be
 * deleted for being absent from it.
 */
async function prune(db, events) {
  const keep = new Set(events.map((event) => event.id));
  const snapshot = await db
    .collection(COLLECTION)
    .where("source", "==", "curated")
    .get();

  const stale = snapshot.docs.filter((doc) => !keep.has(doc.id));
  if (stale.length === 0) {
    console.log("Nothing to prune.");
    return;
  }

  console.log(`Pruning ${stale.length} listing(s) no longer in the file:`);
  for (const doc of stale) {
    console.log(`  ${doc.id}  ${doc.data().name ?? ""}`);
  }

  for (let start = 0; start < stale.length; start += BATCH_LIMIT) {
    const batch = db.batch();
    for (const doc of stale.slice(start, start + BATCH_LIMIT)) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }
}

main().catch((error) => {
  console.error("Seeding failed:", error);
  process.exitCode = 1;
});
