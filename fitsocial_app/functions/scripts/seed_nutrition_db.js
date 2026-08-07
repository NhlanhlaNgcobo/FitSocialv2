#!/usr/bin/env node
/**
 * Uploads data/nutrition_foods.json into the Firestore `nutritionFoods`
 * collection, one document per food keyed by its id.
 *
 * Seeding is optional — the Cloud Function falls back to the bundled JSON file
 * when the collection is empty. Seed when you want to edit foods or add your
 * own without redeploying functions.
 *
 * Usage (from fitsocial_app/functions):
 *   npm run seed:nutrition
 *
 * Auth: needs Application Default Credentials with write access to the project.
 *   gcloud auth application-default login
 *   set GOOGLE_CLOUD_PROJECT=fitsocialv2
 * or point GOOGLE_APPLICATION_CREDENTIALS at a service-account key file.
 *
 * Re-running is safe: documents are written with merge, so local edits to the
 * JSON overwrite the matching fields and nothing else is touched.
 */

const admin = require("firebase-admin");
const { readBundled, COLLECTION } = require("../nutrition_db");

const BATCH_LIMIT = 400;

async function main() {
  const projectId =
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.GCLOUD_PROJECT ||
    process.env.FIREBASE_PROJECT;

  admin.initializeApp(projectId ? { projectId } : undefined);
  const db = admin.firestore();

  const foods = readBundled();
  if (foods.length === 0) {
    console.error("No foods found in data/nutrition_foods.json — nothing to do.");
    process.exitCode = 1;
    return;
  }

  const ids = new Set();
  for (const food of foods) {
    if (ids.has(food.id)) {
      console.error(`Duplicate food id in the seed file: ${food.id}`);
      process.exitCode = 1;
      return;
    }
    ids.add(food.id);
  }

  console.log(
    `Seeding ${foods.length} foods into ${COLLECTION}` +
      (projectId ? ` (project ${projectId})...` : "...")
  );

  let written = 0;
  for (let start = 0; start < foods.length; start += BATCH_LIMIT) {
    const batch = db.batch();
    for (const food of foods.slice(start, start + BATCH_LIMIT)) {
      batch.set(
        db.collection(COLLECTION).doc(food.id),
        { ...food, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true }
      );
    }
    await batch.commit();
    written += Math.min(BATCH_LIMIT, foods.length - start);
    console.log(`  ${written}/${foods.length}`);
  }

  console.log("Done. The analyzer picks up changes within 10 minutes (cache TTL).");
}

main().catch((error) => {
  console.error("Seeding failed:", error);
  process.exitCode = 1;
});
