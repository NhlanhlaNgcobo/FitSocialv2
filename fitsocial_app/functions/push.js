/**
 * Push delivery for the notification inbox.
 *
 * One trigger, on the inbox path itself. Notifications are written from two
 * very different places -- client-side by the actor, batched into the follow or
 * reaction or comment that earned them, and server-side by
 * running_challenges.js -- and teaching both of those to send push would mean
 * two implementations of "who gets told", each able to drift from the other and
 * from the list the user actually sees.
 *
 * Listening to `users/{userId}/notifications/{notificationId}` instead means
 * the tray is a consequence of the inbox rather than a parallel system. Every
 * kind is covered the moment it is written, and a tenth kind added later gets
 * push without anyone remembering to wire it up.
 *
 * Region comes from `setGlobalOptions({ region: "africa-south1" })` in
 * index.js, and must: a v2 Firestore trigger has to run in the region of the
 * database it listens to.
 *
 * `onDocumentCreated`, not `onDocumentWritten`. A reaction notification is
 * rewritten in full whenever somebody changes their mind, which lifts the row
 * back to the top of the list -- worth doing in the inbox, and not worth
 * buzzing the phone a second time for.
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

// The same memoised accessor the challenge engines use. See the comment on
// `db()` in challenges.js: a second initialisation guard written here would be
// a second copy of the bug that once took the whole challenge system down.
const { db } = require("./challenges")._internals;

const { notificationCopy } = require("./notification_copy");

/**
 * Cloud Messaging, with the default app guaranteed to exist first.
 *
 * `admin.messaging()` needs a default app exactly as `admin.firestore()` does,
 * and `db()` is the one place in this codebase that knows how to guarantee one
 * — asking it by name rather than counting apps, which is the mistake that once
 * took the whole challenge engine down. Calling it here costs a memoised lookup
 * and means messaging can never be the call that finds no app.
 */
function messaging() {
  db();
  return admin.messaging();
}

/**
 * Where a user's device tokens live. The document id IS the token and presence
 * is the whole state, the same shape `notifyFor` uses on the client side --
 * there is no enabled flag that could contradict the document's existence.
 */
const TOKENS = "fcmTokens";

/**
 * FCM refuses a multicast of more than 500 tokens.
 *
 * Nobody reaches this: tokens are deleted on sign-out and pruned below when
 * FCM reports them dead, so a real user holds one per device they still use.
 * The slice is here so that a runaway list degrades into a partial send rather
 * than an exception that retries forever.
 */
const MAX_TOKENS = 500;

/**
 * Error codes that mean the token is gone for good, rather than that this send
 * failed.
 *
 * Only these two. A quota error or an unavailable backend must NOT delete
 * anything -- that would turn a transient outage into every user silently
 * losing push until they next reinstall.
 */
const DEAD_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-argument",
  "messaging/invalid-registration-token",
]);

/**
 * Sends one notification document to every device its recipient has registered.
 *
 * Exported through `_internals` so test/push.test.js can call it directly; the
 * trigger below is a thin wrapper that unpacks the event.
 */
async function deliver(userId, notificationId, data, messaging) {
  // Defence in depth. firestore.rules already refuses a notification whose
  // recipient is its own actor, and every writer skips it, but the one thing
  // worse than a missing push is a user being buzzed about themselves.
  if (!userId || !data || data.actorId === userId) return;

  const copy = notificationCopy(data);
  // A `type` this deployment does not recognise -- a row written by a newer
  // client. Skipped rather than sent as a blank, the same way the app's own
  // list drops it.
  if (!copy) return;

  const inbox = db().collection("users").doc(userId).collection(TOKENS);
  const snapshot = await inbox.get();
  if (snapshot.empty) {
    // Logged rather than returned in silence, because this is the single most
    // confusing way for push to "not work": everything succeeds, nothing is
    // sent, and there is nothing in the logs to say why. The recipient simply
    // has no device registered -- they have never opened the app since push
    // shipped, refused the permission, or signed out on the only phone they
    // had it on.
    console.log(`No registered device for ${userId}; nothing to push.`);
    return;
  }

  const tokens = snapshot.docs.slice(0, MAX_TOKENS).map((doc) => doc.id);

  const response = await messaging.sendEachForMulticast({
    tokens,
    // A `notification` block, so Android's system tray draws this itself when
    // the app is backgrounded or killed. While the app is foregrounded Android
    // suppresses it, which is correct here: the bell badge is already live off
    // the same document and does not need a second announcement.
    notification: { title: copy.title, body: copy.body },
    // Every value must be a string -- FCM rejects a data payload that is not
    // entirely strings, and does it at send time rather than at build time.
    data: {
      notificationId: String(notificationId ?? ""),
      type: String(data.type ?? ""),
      // Computed here rather than on the phone so the tap has nothing to
      // re-derive. Empty when the row arrived without the id its destination
      // needs; the client treats that as "just open the app".
      route: copy.route ?? "",
    },
    android: {
      priority: "high",
      notification: {
        // Keyed to the notification document, so a row that is deleted and
        // written again -- an unfollow then a re-follow -- replaces its own
        // entry in the tray instead of stacking a duplicate beneath it.
        tag: String(notificationId ?? ""),
      },
    },
  });

  // One line per send, so "did it go out, and to how many devices" is a log
  // search rather than a database query. Cheap: this fires once per
  // notification, not once per device.
  console.log(
    `Pushed ${data.type} to ${userId}: ` +
      `${response.successCount} delivered, ${response.failureCount} failed, ` +
      `of ${tokens.length} device(s).`
  );

  await pruneDeadTokens(inbox, tokens, response);
}

/**
 * Deletes the tokens FCM has just told us are dead.
 *
 * This is the only thing standing between the token list and unbounded growth.
 * A tester who reinstalls the app gets a new token every time, and the old ones
 * are never mentioned again by anything except a failed send.
 */
async function pruneDeadTokens(inbox, tokens, response) {
  const responses = response?.responses ?? [];
  const dead = [];

  responses.forEach((result, index) => {
    if (result?.success) return;
    const code = result?.error?.code;
    if (DEAD_TOKEN_CODES.has(code)) dead.push(tokens[index]);
  });

  if (dead.length === 0) return;

  await Promise.all(dead.map((token) => inbox.doc(token).delete()));
  console.log(`Pruned ${dead.length} dead FCM token(s).`);
}

exports.onNotificationCreated = onDocumentCreated(
  "users/{userId}/notifications/{notificationId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const { userId, notificationId } = event.params;

    try {
      await deliver(userId, notificationId, snapshot.data(), messaging());
    } catch (error) {
      // Swallowed on purpose. The notification is already in the inbox and the
      // user will see it the moment they open the app; throwing here would
      // retry the send against a document that is not going to change, and a
      // misconfigured Cloud Messaging API would do that on every notification
      // in the system.
      console.error(
        `Push failed for users/${userId}/notifications/${notificationId}:`,
        error
      );
    }
  }
);

exports._internals = {
  deliver,
  pruneDeadTokens,
  messaging,
  DEAD_TOKEN_CODES,
  MAX_TOKENS,
};
