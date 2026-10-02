const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const zlib = require("node:zlib");

/**
 * Data export: everything a user has put into FitSocial, as one JSON file.
 *
 * A Cloud Function rather than client code for the same reason account
 * deletion is one: reach. A good part of what a user owns -- their daily and
 * weekly stats, points, leaderboard rows, comments under other people's posts
 * -- is closed to clients by the security rules, and an export that left it
 * out would not be an export of their data.
 *
 * The collections below mirror the sweep in account_deletion.js. What one
 * deletes, the other should hand over; a collection added to one belongs in
 * the other.
 *
 * Left out on purpose:
 *  - fcmTokens: device push tokens, meaningless outside the app and the one
 *    thing here that is closer to a credential than to data.
 *  - safetyContactOf: other people's safety lists that name this user. That
 *    is their data about them, not this user's.
 *  - pulseSeen: read markers the Pulse strip keeps for itself.
 *  - routePoints on posts: a shared run's post carries a copy of the route
 *    already exported with the run itself, and routes are most of the bytes.
 *
 * The JSON goes back gzipped and base64-encoded. A run stores up to 1,500 GPS
 * points, so a keen runner's history is megabytes of JSON, and callable
 * responses have a size ceiling; GPS text compresses several times over.
 */

function ensureDefaultApp() {
  try {
    admin.app();
  } catch (_) {
    admin.initializeApp();
  }
}

function db() {
  ensureDefaultApp();
  return admin.firestore();
}

/** Bumped when the file's shape changes, so a reader can tell versions apart. */
const EXPORT_VERSION = 1;

/** Subcollections of users/{uid} that are exported. See the header. */
const USER_SUBCOLLECTIONS = [
  "private",
  "goals",
  "badges",
  "insights",
  "bookmarks",
  "savedRaces",
  "following",
  "followers",
  "notifyFor",
  "challengeMemberships",
  "safetyContacts",
  "emailContacts",
  "entryTaps",
  "notifications",
];

/** Subcollections one level further down, by parent subcollection. */
const NESTED_SUBCOLLECTIONS = { goals: ["periods"] };

/** Top-level collections exported by owner, as [name, owner field]. */
const OWNED_COLLECTIONS = [
  ["meals", "authorId"],
  ["workouts", "authorId"],
  ["runs", "authorId"],
  ["posts", "authorId"],
  ["pulses", "authorId"],
  ["challengeEnrollments", "userId"],
  ["dailySteps", "userId"],
  ["dailyStats", "userId"],
  ["weeklyStats", "userId"],
  ["monthlyStats", "userId"],
  ["pointsLedger", "userId"],
  ["leaderboardEntries", "userId"],
  ["insightFeedback", "userId"],
];

/** Fields dropped from documents of a collection. See the header. */
const DROPPED_FIELDS = { posts: ["routePoints"] };

/**
 * Turns Firestore values into plain JSON: timestamps become ISO strings,
 * geopoints {latitude, longitude}, references their path.
 */
function toJson(value) {
  if (value === null || value === undefined) return null;
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.map(toJson);
  if (typeof value === "object") {
    if (typeof value.toDate === "function") return value.toDate().toISOString();
    if (
      typeof value.latitude === "number" &&
      typeof value.longitude === "number" &&
      Object.keys(value).length <= 2
    ) {
      return { latitude: value.latitude, longitude: value.longitude };
    }
    if (typeof value.path === "string" && value.firestore) return value.path;
    if (Buffer.isBuffer(value)) return value.toString("base64");
    const out = {};
    for (const [key, inner] of Object.entries(value)) out[key] = toJson(inner);
    return out;
  }
  return value;
}

function docJson(snapshot, dropped = []) {
  const data = { ...snapshot.data() };
  for (const field of dropped) delete data[field];
  return { id: snapshot.id, ...toJson(data) };
}

async function readUserSubcollection(userRef, name) {
  const snapshot = await userRef.collection(name).get();
  const nested = NESTED_SUBCOLLECTIONS[name] ?? [];
  return Promise.all(
    snapshot.docs.map(async (doc) => {
      const entry = docJson(doc);
      for (const child of nested) {
        const children = await doc.ref.collection(child).get();
        entry[child] = children.docs.map((inner) => docJson(inner));
      }
      return entry;
    })
  );
}

/** Builds the export object for one user. Exposed for tests. */
async function collectExport(uid, now = new Date()) {
  const firestore = db();
  const userRef = firestore.collection("users").doc(uid);

  const profileSnapshot = await userRef.get();
  const account = {};
  for (const name of USER_SUBCOLLECTIONS) {
    account[name] = await readUserSubcollection(userRef, name);
  }

  const owned = {};
  for (const [name, field] of OWNED_COLLECTIONS) {
    const snapshot = await firestore
      .collection(name)
      .where(field, "==", uid)
      .get();
    owned[name] = snapshot.docs.map((doc) =>
      docJson(doc, DROPPED_FIELDS[name])
    );
  }

  // Comments live under other people's posts, so each carries its path: an
  // id alone would not say which post it was left on.
  const comments = await firestore
    .collectionGroup("comments")
    .where("authorId", "==", uid)
    .get();
  owned.comments = comments.docs.map((doc) => ({
    path: doc.ref.path,
    ...docJson(doc),
  }));

  return {
    format: "fitsocial-export",
    version: EXPORT_VERSION,
    exportedAt: now.toISOString(),
    userId: uid,
    profile: profileSnapshot.exists ? toJson(profileSnapshot.data()) : null,
    account,
    ...owned,
  };
}

/** How many entries each section holds, for the app to show. */
function countsOf(exported) {
  const counts = {};
  for (const [key, value] of Object.entries(exported)) {
    if (Array.isArray(value)) counts[key] = value.length;
  }
  return counts;
}

/**
 * Exports the calling user's data.
 *
 * No arguments: the uid comes from the verified auth context only, so there
 * is no parameter through which one account could ask for another's data.
 *
 * Returns { fileName, gzipBase64, counts }.
 */
exports.exportMyData = onCall(
  { timeoutSeconds: 300, memory: "512MiB" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError(
        "unauthenticated",
        "You have to be signed in to export your data."
      );
    }

    try {
      const now = new Date();
      const exported = await collectExport(uid, now);
      const json = JSON.stringify(exported, null, 2);
      const gzipBase64 = zlib.gzipSync(Buffer.from(json, "utf8")).toString(
        "base64"
      );
      return {
        fileName: `fitsocial-data-${now.toISOString().slice(0, 10)}.json`,
        gzipBase64,
        counts: countsOf(exported),
      };
    } catch (error) {
      console.error(`exportMyData: failed for ${uid}`, error);
      throw new HttpsError(
        "internal",
        "Your data could not be exported. Please try again."
      );
    }
  }
);

// Test seam, skipped by the export loop in index.js.
exports._internals = {
  db,
  collectExport,
  countsOf,
  toJson,
  USER_SUBCOLLECTIONS,
  OWNED_COLLECTIONS,
};
