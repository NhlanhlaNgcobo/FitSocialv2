const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

/**
 * Account deletion.
 *
 * Two things force this to be a Cloud Function rather than client code.
 *
 * The first is reach. A user's data is not confined to documents they own:
 * their reactions sit under other people's posts, their comments under other
 * people's threads, their name in other people's follower lists and Pulse
 * viewer lists. The security rules correctly refuse a client most of those
 * writes, so a client-side delete would leave the account's traces scattered
 * across the database with no way to reach them.
 *
 * The second is finality. Deletion has to survive the client disappearing
 * mid-way. So the order below is deliberate: everything is purged first and
 * the Auth account is deleted last. A run that fails partway leaves the user
 * still signed in and able to try again, whereas deleting the account first
 * would strip the credential that authorises the rest of the sweep and strand
 * the remainder with nothing able to reach it.
 *
 * data_export.js reads the same collections this sweeps. A collection added
 * here belongs there too, or the export silently stops being complete.
 *
 * What is intentionally NOT deleted:
 *
 *  - The username reservation, which is stamped with a release date instead.
 *    Freeing a handle the instant an account closes lets somebody take the
 *    name of a person who just left and answer to their mentions. The hold is
 *    the same one a rename already uses.
 *  - Counters on other people's documents are corrected, not cleared —
 *    followersCount, likesCount and commentsCount are decremented so the
 *    surviving documents stay consistent with what is left under them.
 */

/**
 * Creates the default Admin app if nothing has yet.
 *
 * By name, not by counting `admin.apps` -- firebase-functions installs a
 * **named** app of its own when it has to build a trigger's snapshot, and a
 * count cannot tell that apart from the default app existing. See the long
 * version of this in challenges.js, where counting broke every challenge
 * trigger in production.
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

/** Matches the grace period a rename gets — see USERNAME_HOLD in the app. */
const USERNAME_HOLD_DAYS = 14;

/**
 * Firestore caps a write batch at 500 operations. 400 leaves room for the
 * counter updates that ride along with some of these sweeps.
 */
const BATCH_LIMIT = 400;

/**
 * Applies a counter correction to a document that may since have been deleted.
 *
 * `update` rather than `set(..., { merge: true })`, and the distinction is the
 * point: a merging set on a missing document CREATES it. Correcting
 * followersCount on somebody who deleted their own account last week would
 * resurrect them as a profile with one field and no name — a ghost in
 * everybody's follower list. `update` throws instead, and a counter on a
 * document nobody can reach is not worth failing a deletion over.
 */
async function adjustCounters(corrections) {
  const entries = [...corrections.values()];

  // Twenty at a time. These are independent single-document writes, so they
  // want to overlap, but firing several hundred at once is how a delete run
  // starts competing with itself for the same connection pool.
  for (let i = 0; i < entries.length; i += 20) {
    await Promise.all(
      entries.slice(i, i + 20).map(async (correction) => {
        try {
          await correction.ref.update(correction.updates);
        } catch (error) {
          console.warn(
            `deleteAccount: skipped counter fix on ${correction.ref.path}`,
            error.message
          );
        }
      })
    );
  }
}

/**
 * Records a counter change against [ref], coalescing repeats.
 *
 * Coalescing is what keeps this cheap: five comments on one post become one
 * write of -5 rather than five writes of -1.
 */
function noteCounterChange(corrections, ref, field, delta) {
  const existing = corrections.get(ref.path);
  if (existing) {
    existing.deltas[field] = (existing.deltas[field] ?? 0) + delta;
    return;
  }
  corrections.set(ref.path, { ref, deltas: { [field]: delta } });
}

/** Turns the accumulated deltas into Firestore increment sentinels. */
function materialiseCounters(corrections) {
  for (const correction of corrections.values()) {
    correction.updates = Object.fromEntries(
      Object.entries(correction.deltas).map(([field, delta]) => [
        field,
        admin.firestore.FieldValue.increment(delta),
      ])
    );
  }
  return corrections;
}

/**
 * Deletes every document a query matches, in batches, with an optional
 * per-document hook for recording the counter changes a deletion implies.
 *
 * The hook records rather than writes: the corrections are applied afterwards
 * by [adjustCounters], so that one aimed at a document which has since
 * vanished cannot fail the batch doing the actual work.
 *
 * Returns the number of documents removed, which is what the audit line at the
 * end of the run is assembled from.
 */
async function deleteMatching(query, onDoc) {
  const firestore = db();
  const corrections = new Map();
  let removed = 0;

  // Re-queried rather than paged with a cursor: each pass deletes the
  // documents it read, so the "first N matches" the next pass sees are the
  // ones that are left.
  for (;;) {
    const snapshot = await query.limit(BATCH_LIMIT).get();
    if (snapshot.empty) break;

    const batch = firestore.batch();
    for (const doc of snapshot.docs) {
      if (onDoc) onDoc(doc, corrections);
      batch.delete(doc.ref);
    }
    await batch.commit();
    removed += snapshot.size;

    // A short final page means the query is exhausted. Without this the loop
    // would spend one more round trip proving what this already shows.
    if (snapshot.size < BATCH_LIMIT) break;
  }

  await adjustCounters(materialiseCounters(corrections));
  return removed;
}

/**
 * Deletes a document and everything beneath it.
 *
 * Firestore leaves subcollections behind when a document goes, so posts,
 * Pulses and challenge enrollments — each of which carries its own comments,
 * views, reactions or day records — have to come out this way.
 */
async function deleteTree(ref) {
  await db().recursiveDelete(ref);
}

/**
 * Removes the user from the two halves of every follow edge they are part of,
 * and corrects the counter on the profile at the other end.
 *
 * The edges are stored twice — `users/{me}/following/{them}` and
 * `users/{them}/followers/{me}` — and only one of each pair lives under the
 * departing user's own document. The other half is what this reaches: a
 * collection-group query on the `userId` field, which both documents carry.
 */
async function severFollowEdges(uid) {
  const firestore = db();

  // Their followers' "following" lists, i.e. everyone who followed them.
  // Each of those people loses one from followingCount.
  const followedBy = await deleteMatching(
    firestore.collectionGroup("following").where("userId", "==", uid),
    (doc, corrections) => {
      const owner = doc.ref.parent.parent;
      if (owner) noteCounterChange(corrections, owner, "followingCount", -1);
    }
  );

  // The mirror: everyone they followed loses one from followersCount.
  const following = await deleteMatching(
    firestore.collectionGroup("followers").where("userId", "==", uid),
    (doc, corrections) => {
      const owner = doc.ref.parent.parent;
      if (owner) noteCounterChange(corrections, owner, "followersCount", -1);
    }
  );

  return { followedBy, following };
}

/**
 * Takes back every reaction the user left on somebody else's post.
 *
 * Found through the post's own `likedBy` array rather than a collection-group
 * query, for a specific reason: the reaction records live at
 * `likes/{postId}/users/{uid}` and carry no uid field of their own — the uid is
 * the document id. A collection-group query on "users" would also sweep the
 * top-level /users collection, which is every profile in the app. Reading the
 * posts instead is both correct and what makes the counters fixable, since the
 * post is already in hand.
 */
async function withdrawReactions(uid) {
  const firestore = db();
  const FieldValue = admin.firestore.FieldValue;
  let withdrawn = 0;

  for (;;) {
    const snapshot = await firestore
      .collection("posts")
      .where("likedBy", "array-contains", uid)
      .limit(BATCH_LIMIT)
      .get();
    if (snapshot.empty) return withdrawn;

    const batch = firestore.batch();
    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      const reactionKey = (data.reactionsBy || {})[uid];

      batch.update(doc.ref, {
        likedBy: FieldValue.arrayRemove(uid),
        likesCount: FieldValue.increment(-1),
        [`reactionsBy.${uid}`]: FieldValue.delete(),
        // Only when the post recorded which reaction it was. An older like
        // predating reactions has nothing to decrement, and blindly moving a
        // counter that was never incremented would drive it negative.
        ...(reactionKey
          ? { [`reactionCounts.${reactionKey}`]: FieldValue.increment(-1) }
          : {}),
      });
      batch.delete(
        firestore.collection("likes").doc(doc.id).collection("users").doc(uid)
      );
    }
    await batch.commit();
    withdrawn += snapshot.size;

    if (snapshot.size < BATCH_LIMIT) return withdrawn;
  }
}

/**
 * Deletes the user's comments from other people's posts and Pulses, and
 * decrements the parent's comment counter.
 *
 * Comments under the user's own posts are not reached here — those posts are
 * deleted whole, subcollections and all, by [deleteTree].
 */
async function removeComments(uid) {
  return deleteMatching(
    db().collectionGroup("comments").where("authorId", "==", uid),
    (doc, corrections) => {
      const parent = doc.ref.parent.parent;
      // Posts only. A Pulse has no commentsCount, and writing one onto it
      // would invent a field the rest of the app neither reads nor maintains.
      if (!parent || parent.parent.id !== "posts") return;
      noteCounterChange(corrections, parent, "commentsCount", -1);
    }
  );
}

/**
 * Releases the user's handle on a delay instead of deleting the reservation.
 *
 * `uid` is kept on the document on purpose. Once the account is gone it names
 * nobody, and it is what the existing rules use to tell an owner's own re-claim
 * from a stranger's during the hold.
 */
async function releaseUsername(uid) {
  const firestore = db();
  const claims = await firestore
    .collection("usernames")
    .where("uid", "==", uid)
    .get();
  if (claims.empty) return 0;

  const releaseAt = new Date(Date.now() + USERNAME_HOLD_DAYS * 86400000);
  const batch = firestore.batch();
  for (const doc of claims.docs) {
    batch.set(doc.ref, { releaseAt }, { merge: true });
  }
  await batch.commit();
  return claims.size;
}

/** Every Storage prefix the app writes user media under. */
const STORAGE_PREFIXES = ["profiles", "posts", "meals", "pulses"];

async function deleteStorage(uid) {
  const bucket = admin.storage().bucket();
  let deleted = 0;

  for (const prefix of STORAGE_PREFIXES) {
    // Best-effort per prefix. A Storage failure must not abort a run that has
    // already removed the database records — the account would be left half
    // deleted with no way for the user to ask again.
    try {
      const [files] = await bucket.getFiles({ prefix: `${prefix}/${uid}/` });
      await Promise.all(files.map((file) => file.delete()));
      deleted += files.length;
    } catch (error) {
      console.error(`deleteAccount: storage sweep failed for ${prefix}`, error);
    }
  }

  return deleted;
}

/**
 * Deletes every document in a top-level collection owned by [uid] via [field],
 * taking any subcollections with it.
 */
async function deleteOwnedTrees(collection, field, uid) {
  const firestore = db();
  let removed = 0;

  for (;;) {
    const snapshot = await firestore
      .collection(collection)
      .where(field, "==", uid)
      .limit(BATCH_LIMIT)
      .get();
    if (snapshot.empty) return removed;

    // Sequential rather than parallel: recursiveDelete opens its own
    // BulkWriter per call, and firing hundreds at once is how a delete run
    // starts contending with itself.
    for (const doc of snapshot.docs) {
      await deleteTree(doc.ref);
    }
    removed += snapshot.size;

    if (snapshot.size < BATCH_LIMIT) return removed;
  }
}

/**
 * Deletes the user's own posts, each with its comments and its reaction
 * records.
 *
 * Separate from [deleteOwnedTrees] because a post's reactions do not live
 * under the post. They sit at `likes/{postId}/users/{uid}`, hanging off a
 * top-level document keyed by post id, so deleting the post recursively leaves
 * them behind — every reaction anyone ever left on this user's posts, orphaned
 * under an id that now points at nothing.
 */
async function deleteOwnPosts(uid) {
  const firestore = db();
  let removed = 0;

  for (;;) {
    const snapshot = await firestore
      .collection("posts")
      .where("authorId", "==", uid)
      .limit(BATCH_LIMIT)
      .get();
    if (snapshot.empty) return removed;

    for (const doc of snapshot.docs) {
      await deleteTree(firestore.collection("likes").doc(doc.id));
      await deleteTree(doc.ref);
    }
    removed += snapshot.size;

    if (snapshot.size < BATCH_LIMIT) return removed;
  }
}

async function purgeAccount(uid) {
  const firestore = db();

  // Content the user authored, each deleted with everything beneath it.
  const posts = await deleteOwnPosts(uid);
  const pulses = await deleteOwnedTrees("pulses", "authorId", uid);
  const enrollments = await deleteOwnedTrees(
    "challengeEnrollments",
    "userId",
    uid
  );

  // Traces left on other people's documents.
  const reactions = await withdrawReactions(uid);
  const comments = await removeComments(uid);
  const follows = await severFollowEdges(uid);
  const pulseReactions = await deleteMatching(
    firestore.collectionGroup("reactions").where("reactorId", "==", uid)
  );
  // Viewer records carry the watcher's display name, not just their id, which
  // is why these are swept rather than left to the Pulse's own expiry.
  const pulseViews = await deleteMatching(
    firestore.collectionGroup("views").where("viewerId", "==", uid)
  );
  // Notifications this user caused in other people's inboxes — "so-and-so
  // followed you" from an account that no longer exists.
  const notifications = await deleteMatching(
    firestore.collectionGroup("notifications").where("actorId", "==", uid)
  );

  // Private logs. Flat collections with no subcollections, so a batched
  // delete is enough.
  const runs = await deleteMatching(
    firestore.collection("runs").where("authorId", "==", uid)
  );
  const workouts = await deleteMatching(
    firestore.collection("workouts").where("authorId", "==", uid)
  );
  const meals = await deleteMatching(
    firestore.collection("meals").where("authorId", "==", uid)
  );
  const dailySteps = await deleteMatching(
    firestore.collection("dailySteps").where("userId", "==", uid)
  );
  const points = await deleteMatching(
    firestore.collection("pointsLedger").where("userId", "==", uid)
  );

  // The Build 11 stats pipeline's own records: what the logs above added up to
  // per day, week and month, and the leaderboard projection taken off the week
  // and month. Derived data, but derived health data -- a deleted account must
  // not leave its step counts behind in a document nothing will ever rebuild.
  // The leaderboard entries matter most: they are the only ones other people
  // can read, so a board would otherwise keep ranking somebody who is gone.
  const dailyStats = await deleteMatching(
    firestore.collection("dailyStats").where("userId", "==", uid)
  );
  const weeklyStats = await deleteMatching(
    firestore.collection("weeklyStats").where("userId", "==", uid)
  );
  const monthlyStats = await deleteMatching(
    firestore.collection("monthlyStats").where("userId", "==", uid)
  );
  const leaderboardEntries = await deleteMatching(
    firestore.collection("leaderboardEntries").where("userId", "==", uid)
  );
  // Their Weekly Insights go with the users/{uid} tree; their ratings of
  // them live at the top level.
  const insightFeedback = await deleteMatching(
    firestore.collection("insightFeedback").where("userId", "==", uid)
  );

  await firestore.collection("earlyWorm").doc(uid).delete();

  const usernames = await releaseUsername(uid);

  // The profile and everything under it — bookmarks, badges, the inbox, the
  // private document holding body metrics. Last of the Firestore work, so a
  // failure above still leaves the profile to explain who the leftovers
  // belonged to.
  await deleteTree(firestore.collection("users").doc(uid));

  const storageFiles = await deleteStorage(uid);

  return {
    posts,
    pulses,
    enrollments,
    reactions,
    comments,
    followers: follows.followedBy,
    following: follows.following,
    pulseReactions,
    pulseViews,
    notifications,
    runs,
    workouts,
    meals,
    dailySteps,
    points,
    dailyStats,
    weeklyStats,
    monthlyStats,
    leaderboardEntries,
    insightFeedback,
    usernames,
    storageFiles,
  };
}

/**
 * Deletes the calling user's account.
 *
 * Takes no arguments — the uid comes from the verified auth context and
 * nowhere else, so there is no parameter through which one account could ask
 * for another to be deleted. The confirmation the user typed is checked on the
 * client, where it belongs: it guards against a mis-tap, not against an
 * attacker, who would have had to be signed in as them to reach this at all.
 */
exports.deleteAccount = onCall(
  { timeoutSeconds: 540, memory: "512MiB" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError(
        "unauthenticated",
        "You have to be signed in to delete your account."
      );
    }

    let summary;
    try {
      summary = await purgeAccount(uid);
    } catch (error) {
      console.error(`deleteAccount: purge failed for ${uid}`, error);
      throw new HttpsError(
        "internal",
        "Your account could not be deleted. Nothing has been changed — " +
          "please try again."
      );
    }

    // Last, and only once the data is gone. Deleting the Auth record first
    // would revoke the session that authorises a retry.
    try {
      await admin.auth().deleteUser(uid);
    } catch (error) {
      // The data is already gone at this point, so reporting failure would be
      // wrong — but an Auth record outliving its data is a real inconsistency
      // and has to be visible to us.
      console.error(`deleteAccount: auth record survived for ${uid}`, error);
      throw new HttpsError(
        "internal",
        "Your data has been deleted but the account itself could not be " +
          "closed. Contact support so we can finish it."
      );
    }

    console.log(`deleteAccount: completed for ${uid}`, summary);
    return { deleted: true };
  }
);

// Test seam. Skipped by the export loop in index.js, which treats every other
// export of a required module as a function to deploy.
exports._internals = {
  // See the note beside `db` in challenges.js's _internals.
  db,
  purgeAccount,
  noteCounterChange,
  withdrawReactions,
  severFollowEdges,
  removeComments,
  releaseUsername,
  deleteMatching,
  USERNAME_HOLD_DAYS,
  BATCH_LIMIT,
};
