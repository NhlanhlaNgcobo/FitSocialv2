#!/usr/bin/env node
/**
 * Builds dailyStats, weeklyStats and monthlyStats for the recent past.
 *
 * Run once, when the first Build 11 feature that reads stats is switched on.
 * The stats pipeline (stats.js) sleeps while every such feature is off, and
 * even when awake it only builds a day when something on that day changes. So
 * the day a feature goes live there is no history: Compare would set this
 * week against an empty last week and say "not enough data", and a monthly
 * goal would start the month at zero. This fills in the last [--days] days
 * (default 70, which covers this month, last month, and "four weeks ago")
 * for everybody who logged anything in them.
 *
 * Usage (from fitsocial_app/functions):
 *   node scripts/backfill_stats.js                 # report only
 *   node scripts/backfill_stats.js --commit        # actually write
 *   node scripts/backfill_stats.js --days=35 --commit
 *
 * Call node directly, not through npm, for the reason the other backfill
 * scripts give: npm swallows a bare --commit.
 *
 * Auth: Application Default Credentials with write access to the project.
 *   gcloud auth application-default login
 *   set GOOGLE_CLOUD_PROJECT=fitsocialv2
 *
 * Re-running is safe: every document is rebuilt from the logs at a derived
 * id, so a second pass writes the same numbers the first one did.
 */

const admin = require("firebase-admin");

const DEFAULT_DAYS = 70;

function argValue(name, fallback) {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
}

async function main() {
  const commit = process.argv.includes("--commit");
  const days = Math.max(1, Math.min(400, Number(argValue("days", DEFAULT_DAYS))));

  const projectId =
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.GCLOUD_PROJECT ||
    process.env.FIREBASE_PROJECT;
  admin.initializeApp(projectId ? { projectId } : undefined);
  const db = admin.firestore();

  // Required after initializeApp: challenges.js asks for the default app and
  // would otherwise initialise one of its own without the project id.
  const { dayKeyOf, addDays, offsetFor } = require("../challenges")._internals;
  const stats = require("../stats")._internals;
  const periods = require("../period_keys");

  const since = new Date(Date.now() - days * 86400000);
  const sinceStamp = admin.firestore.Timestamp.fromDate(since);

  // Everybody with anything in the window: a step record or a log.
  const users = new Set();
  const steps = await db
    .collection("dailySteps")
    .where("dayKey", ">=", since.toISOString().slice(0, 10))
    .get();
  steps.docs.forEach((d) => d.get("userId") && users.add(d.get("userId")));
  for (const collection of ["runs", "workouts", "meals"]) {
    const logs = await db
      .collection(collection)
      .where("createdAt", ">=", sinceStamp)
      .get();
    logs.docs.forEach((d) => d.get("authorId") && users.add(d.get("authorId")));
  }

  console.log(
    `${users.size} user(s) with activity in the last ${days} days.` +
      (commit ? "" : " Report only: pass --commit to build their stats.")
  );
  if (!commit) return;

  let built = 0;
  for (const uid of users) {
    const offset = await offsetFor(uid);
    const today = dayKeyOf(new Date(), offset);
    const first = addDays(today, -(days - 1));
    const weeks = new Set();
    const months = new Set();

    for (let k = first; k <= today; k = addDays(k, 1)) {
      await stats.recomputeDay(uid, k, offset);
      weeks.add(periods.isoWeekIdOf(k));
      months.add(periods.monthIdOf(k));
    }
    for (const w of weeks) await stats.recomputeWeek(uid, w);
    for (const m of months) await stats.recomputeMonth(uid, m);

    built += 1;
    console.log(`  ${built}/${users.size} ${uid}: ${days} days, ` +
      `${weeks.size} weeks, ${months.size} months`);
  }
  console.log(`Done. Built stats for ${built} user(s).`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
