/**
 * Aggregates entry-link taps from the running calendar.
 *
 * The app records a tap on the user's own document and nothing else. This module
 * is what turns those private records into a number worth showing an entry
 * platform: `raceEntryStats/{eventId}`, server-written, carrying no identity.
 *
 * That split is the whole design. The obvious alternative -- a public
 * `entryClicks` collection the client appends to -- would be a client-writable
 * log of what every user is interested in entering, which is both a collection
 * somebody has to police and personal information sitting where it does not
 * need to. Here the client can only ever touch its own counters, and the
 * aggregate is derived rather than submitted.
 *
 * What it measures is intent, not sales. Once a runner leaves for the entry
 * page, only that platform knows whether they paid -- so nothing here should
 * ever be reported as a conversion.
 */

// The modular subpaths, not the `admin.firestore()` namespace: the root export
// dropped `.firestore` in firebase-admin v14, and these work from v11 onward.
const { initializeApp, getApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");

const STATS = "raceEntryStats";

/**
 * How long before the same person tapping the same race counts again.
 *
 * Somebody who taps a race four times while deciding is one interested runner,
 * and a number that counted them four times is a number a partner is right to
 * distrust. An hour is long enough to collapse a single sitting and short
 * enough that genuinely coming back tomorrow still registers.
 */
const COOLDOWN_MS = 60 * 60 * 1000;

/**
 * Creates the default Admin app if nothing has yet, and hands back Firestore.
 *
 * `getApps().length === 0` was the guard, and it was wrong: this is a Firestore
 * trigger, and firebase-functions installs its own **named** app before the
 * handler runs in order to build `event.data`. That made the count non-zero
 * while the default app -- the one `getFirestore()` goes looking for -- still
 * did not exist, so this threw on every cold start. Ask for the default by name
 * instead. challenges.js carries the full account; it had the same bug.
 */
function db() {
  try {
    getApp();
  } catch (_) {
    initializeApp();
  }
  return getFirestore();
}

/**
 * The month a tap belongs to, in South African local time.
 *
 * SAST is UTC+2 with no daylight saving, so a fixed offset is exact here rather
 * than an approximation -- a tap at 01:00 on the 1st belongs to the new month
 * for the reader, and would be filed under the old one by UTC.
 */
function monthKey(date) {
  const sast = new Date(date.getTime() + 2 * 60 * 60 * 1000);
  return `${sast.getUTCFullYear()}-${String(sast.getUTCMonth() + 1).padStart(2, "0")}`;
}

function toDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  return null;
}

/**
 * Decides what one write to a user's tap document should add to the aggregate.
 *
 * Pure, and separated from the trigger so the counting rule can be tested
 * without a Firestore. Returns null when the write should not count.
 */
function plan({ before, after }) {
  if (!after) return null; // deleted: the tap still happened, so nothing moves

  const lastTapAt = toDate(after.lastTapAt);
  if (!lastTapAt) return null;

  if (!before) {
    return { taps: 1, tappers: 1, month: monthKey(lastTapAt), at: lastTapAt };
  }

  const previous = toDate(before.lastTapAt);
  // No previous timestamp to compare against, or the counter did not move:
  // this is the function's own firstTapAt write coming back round, or a field
  // edit that is not a new tap.
  if (!previous) return null;
  if (lastTapAt.getTime() - previous.getTime() < COOLDOWN_MS) return null;

  return { taps: 1, tappers: 0, month: monthKey(lastTapAt), at: lastTapAt };
}

exports.onRaceEntryTap = onDocumentWritten(
  "users/{userId}/entryTaps/{eventId}",
  async (event) => {
    const before = event.data?.before?.exists ? event.data.before.data() : null;
    const after = event.data?.after?.exists ? event.data.after.data() : null;

    const change = plan({ before, after });
    if (!change) return;

    const { eventId } = event.params;
    const update = {
      eventId,
      taps: FieldValue.increment(change.taps),
      lastTapAt: change.at,
      [`byMonth.${change.month}`]: FieldValue.increment(change.taps),
    };
    if (change.tappers > 0) {
      update.tappers = FieldValue.increment(change.tappers);
    }
    if (after.platform) {
      // Copied from the tap rather than read off the race: the client already
      // knows it, and a read per tap would cost more than the field is worth.
      update.platform = after.platform;
    }

    await db().collection(STATS).doc(eventId).set(update, { merge: true });

    // firstTapAt is set here rather than by the client so the client write stays
    // a single unconditional merge. Written only when absent, so it records the
    // first tap and never moves afterwards.
    if (!before && !after.firstTapAt) {
      await event.data.after.ref.set(
        { firstTapAt: change.at },
        { merge: true }
      );
    }
  }
);

// `db` is here for test/admin_app_init.js -- see the note in challenges.js.
exports._internals = { db, plan, monthKey, COOLDOWN_MS, STATS };
