/**
 * Safety: contacts, panic alerts and location-share expiry. Spec part A.
 *
 * The rule this whole module exists to enforce: **only an accepted safety
 * contact is ever sent an alert.** The client never names recipients. A panic
 * event arrives with a user id and a position, and the list of people to wake
 * up is read here, server-side, from the raiser's own accepted contacts. A
 * client-supplied list would let anyone push emergency-priority notifications
 * at anyone.
 *
 * Paths:
 *   users/{uid}/safetyContacts/{contactUid}  -- people I asked. Client creates
 *                                               a pending row; everything else
 *                                               is written here.
 *   users/{uid}/safetyContactOf/{ownerUid}   -- the mirror, people who asked me.
 *                                               Written here only.
 *   panicEvents/{eventId}                    -- one per panic.
 *   panicEvents/{eventId}/acknowledgements/{uid}
 *   locationShares/{shareId}
 *
 * Push tokens are read from users/{uid}/fcmTokens, the same registry push.js
 * sends the inbox from. The spec calls it `devices`; there is one registry in
 * this app and a second would drift.
 *
 * Invites, acceptances and revocations are written into the ordinary
 * notification inbox, so push.js delivers them like any other row. Panic
 * alerts are NOT: they go out from here, on their own Android channel and at
 * iOS time-sensitive priority, so that muting likes can never mute an
 * emergency.
 */

const { onDocumentCreated, onDocumentUpdated, onDocumentWritten } =
  require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

const { db } = require("./challenges")._internals;
const { DEAD_TOKEN_CODES, MAX_TOKENS } = require("./push")._internals;
const email = require("./safety_email")._internals;

/**
 * Must match maxAcceptedSafetyContacts in safety_models.dart. Counts FitSocial
 * and email contacts together: three people in total, however each is reached.
 */
const MAX_ACCEPTED_CONTACTS = email.MAX_CONTACTS;

/** Outstanding invites at once. Stops the invite itself being a spam channel. */
const MAX_PENDING_INVITES = 10;

const PANIC_RATE_LIMIT = 5;
const PANIC_RATE_WINDOW_MS = 60 * 60 * 1000;

/** Re-send until somebody acknowledges, this many sends in total. */
const MAX_PANIC_PUSHES = 10;
const PANIC_RESEND_INTERVAL_MS = 60 * 1000;

const MAX_SHARE_MS = 4 * 60 * 60 * 1000;

/**
 * The Android notification channel panic alerts are posted on. Created by the
 * app at start-up with IMPORTANCE_HIGH; must match `panicChannelId` in
 * lib/features/safety/application/panic_push.dart.
 */
const PANIC_CHANNEL_ID = "panic_alerts";

function serverTimestamp() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function messaging() {
  db();
  return admin.messaging();
}

/** Name, handle and avatar, denormalised onto contact rows and events. */
async function profileOf(uid) {
  const doc = await db().collection("users").doc(uid).get();
  if (!doc.exists) return null;
  return {
    displayName: doc.get("displayName") || doc.get("username") || "Someone",
    handle: doc.get("username") || "",
    avatarUrl: doc.get("photoUrl") || doc.get("avatarUrl") || null,
  };
}

/** A row in the ordinary inbox, delivered by push.js. */
async function notifyInbox(recipientId, actorId, type, id) {
  if (!recipientId || recipientId === actorId) return;
  const actor = await profileOf(actorId);
  await db()
    .collection("users")
    .doc(recipientId)
    .collection("notifications")
    .doc(id)
    .set({
      type,
      actorId,
      actorName: actor?.displayName ?? "Someone",
      ...(actor?.avatarUrl ? { actorAvatarUrl: actor.avatarUrl } : {}),
      createdAt: serverTimestamp(),
      read: false,
    });
}

function contactsOf(uid) {
  return db().collection("users").doc(uid).collection("safetyContacts");
}

function contactOf(uid) {
  return db().collection("users").doc(uid).collection("safetyContactOf");
}

async function acceptedContactIds(uid) {
  const snap = await contactsOf(uid).where("status", "==", "accepted").get();
  return snap.docs.map((d) => d.id);
}

// --- Contacts ---------------------------------------------------------------

/**
 * A client created, or deleted, one of its own contact rows.
 *
 * Create: validate, fill in the authoritative profile, write the mirror and
 * tell the invitee. An invalid invite is deleted rather than left for the
 * client to believe in.
 *
 * Delete: take the mirror down with it -- unless the row has already been
 * re-created, which is how a re-invite after a decline arrives (delete, then
 * create) and the two triggers can land in either order.
 *
 * Updates are ignored: they are this module's own writes.
 */
async function handleContactWrite(ownerId, contactUid, before, after) {
  const source = contactsOf(ownerId).doc(contactUid);
  const mirror = contactOf(contactUid).doc(ownerId);

  if (!after) {
    const current = await source.get();
    if (!current.exists) await mirror.delete();
    return "mirror-removed";
  }
  if (before) return "ignored";
  if (after.status !== "pending") {
    await source.delete();
    return "rejected:status";
  }
  if (contactUid === ownerId) {
    await source.delete();
    return "rejected:self";
  }

  const [contact, owner, pending, used] = await Promise.all([
    profileOf(contactUid),
    profileOf(ownerId),
    contactsOf(ownerId).where("status", "==", "pending").get(),
    email.usedSlots(ownerId),
  ]);
  if (!contact || !owner) {
    await source.delete();
    return "rejected:unknown-user";
  }
  if (pending.size > MAX_PENDING_INVITES) {
    await source.delete();
    return "rejected:too-many-pending";
  }
  // `used` already counts this new pending row.
  if (used > MAX_ACCEPTED_CONTACTS) {
    await source.delete();
    return "rejected:full";
  }

  const batch = db().batch();
  batch.set(
    source,
    { contactUid, ...contact, respondedAt: null },
    { merge: true }
  );
  batch.set(mirror, {
    contactUid: ownerId,
    status: "pending",
    ...owner,
    invitedAt: after.invitedAt ?? serverTimestamp(),
    respondedAt: null,
  });
  await batch.commit();
  await notifyInbox(contactUid, ownerId, "safetyInvite", `safetyInvite_${ownerId}`);
  return "mirrored";
}

/**
 * The invitee accepts or declines. Writes both sides, so the two can never
 * disagree about where a handshake stands.
 */
async function respond(callerId, ownerId, accept) {
  if (!callerId) throw new HttpsError("unauthenticated", "Sign in first.");
  if (typeof ownerId !== "string" || ownerId === "" || ownerId === callerId) {
    throw new HttpsError("invalid-argument", "ownerId is required.");
  }
  const source = contactsOf(ownerId).doc(callerId);
  const mirror = contactOf(callerId).doc(ownerId);
  const [s, m] = await Promise.all([source.get(), mirror.get()]);
  if (!s.exists || !m.exists || s.get("status") !== "pending") {
    throw new HttpsError("failed-precondition", "There is no pending invite.");
  }

  if (accept) {
    if ((await email.activeSlots(ownerId)) >= MAX_ACCEPTED_CONTACTS) {
      throw new HttpsError(
        "resource-exhausted",
        "They already have the maximum number of safety contacts."
      );
    }
  }

  const status = accept ? "accepted" : "declined";
  const batch = db().batch();
  const change = { status, respondedAt: serverTimestamp() };
  batch.set(source, change, { merge: true });
  batch.set(mirror, change, { merge: true });
  await batch.commit();

  if (accept) {
    await notifyInbox(ownerId, callerId, "safetyAccepted", `safety_${callerId}`);
  }
  return { status };
}

/**
 * Either party ends an accepted (or pending) relationship.
 *
 * When the *contact* revokes, the owner is told. This is the opposite of the
 * usual privacy default and deliberately so: if the safety net has a hole the
 * owner has to know, or they will believe they are covered when they are not.
 */
async function revoke(callerId, otherUid) {
  if (!callerId) throw new HttpsError("unauthenticated", "Sign in first.");
  if (typeof otherUid !== "string" || otherUid === "" || otherUid === callerId) {
    throw new HttpsError("invalid-argument", "otherUid is required.");
  }

  // Which way round is it? The caller may be the owner or the contact.
  const asOwner = contactsOf(callerId).doc(otherUid);
  const asContact = contactsOf(otherUid).doc(callerId);
  const [ownerSnap, contactSnap] = await Promise.all([asOwner.get(), asContact.get()]);

  const change = { status: "revoked", respondedAt: serverTimestamp() };
  const live = (snap) =>
    snap.exists && ["pending", "accepted"].includes(snap.get("status"));

  const batch = db().batch();
  let touched = false;
  let ownerToTell = null;
  if (live(ownerSnap)) {
    batch.set(asOwner, change, { merge: true });
    batch.set(contactOf(otherUid).doc(callerId), change, { merge: true });
    touched = true;
  }
  if (live(contactSnap)) {
    batch.set(asContact, change, { merge: true });
    batch.set(contactOf(callerId).doc(otherUid), change, { merge: true });
    if (contactSnap.get("status") === "accepted") ownerToTell = otherUid;
    touched = true;
  }
  if (!touched) {
    throw new HttpsError("failed-precondition", "Nothing to revoke.");
  }
  await batch.commit();

  if (ownerToTell) {
    await notifyInbox(ownerToTell, callerId, "safetyRevoked", `safety_${callerId}`);
  }
  return { status: "revoked" };
}

// --- Panic ------------------------------------------------------------------

async function tokensOf(uid) {
  const snap = await db().collection("users").doc(uid).collection("fcmTokens").get();
  return snap.docs.slice(0, MAX_TOKENS).map((d) => d.id);
}

/**
 * Sends one panic-family push to each of [recipientIds]. Returns how many
 * devices accepted it. Dead tokens are pruned exactly as push.js prunes them.
 */
async function pushTo(recipientIds, { title, body, data }, fcm) {
  let delivered = 0;
  for (const uid of recipientIds) {
    const tokens = await tokensOf(uid);
    if (tokens.length === 0) {
      console.log(`Panic push: ${uid} has no registered device.`);
      continue;
    }
    const response = await fcm.sendEachForMulticast({
      tokens,
      notification: { title, body },
      data,
      android: {
        priority: "high",
        notification: {
          channelId: PANIC_CHANNEL_ID,
          tag: data.eventId,
          sound: "default",
        },
      },
      apns: {
        headers: { "apns-priority": "10" },
        payload: {
          aps: {
            // Breaks through Focus without the critical-alerts entitlement.
            "interruption-level": "time-sensitive",
            sound: "default",
          },
        },
      },
    });
    delivered += response.successCount ?? 0;
    const dead = [];
    (response.responses ?? []).forEach((r, i) => {
      if (!r?.success && DEAD_TOKEN_CODES.has(r?.error?.code)) dead.push(tokens[i]);
    });
    await Promise.all(
      dead.map((t) =>
        db().collection("users").doc(uid).collection("fcmTokens").doc(t).delete()
      )
    );
  }
  return delivered;
}

function alertCopy(name) {
  return {
    title: `${name} needs help`,
    body: `${name} raised a panic alert. Tap to see where they are.`,
  };
}

/**
 * A panic event was created. Works out -- here, never from the client -- who
 * is to be told, records it on the event so the rules can let them read it,
 * and sends the first push.
 */
async function handlePanicCreated(eventId, data, fcm, now = new Date()) {
  const userId = data?.userId;
  const ref = db().collection("panicEvents").doc(eventId);
  if (!userId) return "ignored";

  // Rate limit, counting this event. A sixth panic in an hour is recorded but
  // not pushed: past that point it is somebody abusing the channel, and the
  // contacts have already been woken five times. Counted on the server
  // timestamp -- the rules pin raisedAt to request.time -- never on the
  // client's own clock, which a client can set to anything.
  const since = admin.firestore.Timestamp.fromDate(
    new Date(now.getTime() - PANIC_RATE_WINDOW_MS)
  );
  const recent = await db()
    .collection("panicEvents")
    .where("userId", "==", userId)
    .where("raisedAt", ">=", since)
    .count()
    .get();
  if (recent.data().count > PANIC_RATE_LIMIT) {
    await ref.set({ notifiedUserIds: [], rateLimited: true, resendDue: false }, { merge: true });
    return "rate-limited";
  }

  const [recipients, owner] = await Promise.all([
    acceptedContactIds(userId),
    profileOf(userId),
  ]);
  const notified = await Promise.all(
    recipients.map(async (uid) => ({ uid, ...(await profileOf(uid)) }))
  );
  const name = owner?.displayName ?? "Someone";
  // Email contacts are told first: their links must exist before anything
  // else can fail. Each gets a private tracking link; see safety_email.js.
  const emailed = await email.emailAlert(eventId, userId, name, now);
  const anyone = recipients.length > 0 || emailed.length > 0;

  // Overwrites anything the client put there. The rules refuse a non-empty
  // list on create already; this is the second lock on the same door.
  await ref.set(
    {
      notifiedUserIds: recipients,
      // Names only. Email addresses never leave the owner's own subtree.
      notifiedContacts: [
        ...notified.map((c) => ({ uid: c.uid, displayName: c.displayName ?? "Someone" })),
        ...emailed.map((c) => ({ uid: `email_${c.id}`, displayName: c.name ?? "A contact" })),
      ],
      emailedCount: emailed.length,
      userName: name,
      userHandle: owner?.handle ?? "",
      userAvatarUrl: owner?.avatarUrl ?? null,
      pushAttempts: anyone ? 1 : 0,
      lastPushAt: now,
      resendDue: anyone,
      acknowledged: false,
    },
    { merge: true }
  );

  if (!anyone) return "no-contacts";
  if (recipients.length === 0) return "emailed";
  await pushTo(
    recipients,
    {
      ...alertCopy(name),
      data: { type: "panic", eventId, route: `/safety/alert/${eventId}` },
    },
    fcm
  );
  return "pushed";
}

/**
 * The raiser's own status change: duress or resolved.
 *
 * Duress tells contacts the cancellation was coerced, and leaves re-sends
 * running. Resolved tells them the user is safe, and stops them.
 */
async function handlePanicUpdated(eventId, before, after, fcm) {
  if (!before || !after || before.status === after.status) return "ignored";
  const recipients = after.notifiedUserIds ?? [];
  const name = after.userName ?? "Someone";
  const ref = db().collection("panicEvents").doc(eventId);

  if (after.status === "duress") {
    await email.emailDuress(eventId, name);
    await pushTo(
      recipients,
      {
        title: `${name}'s alert was cancelled under pressure`,
        body: `${name} used their duress code. The alert is still active.`,
        data: { type: "panicDuress", eventId, route: `/safety/alert/${eventId}` },
      },
      fcm
    );
    return "duress";
  }
  if (after.status === "resolved") {
    await ref.set({ resendDue: false, closedAt: serverTimestamp() }, { merge: true });
    await email.emailSafe(eventId, name);
    await pushTo(
      recipients,
      {
        title: `${name} is safe`,
        body: `${name} confirmed they are safe.`,
        data: { type: "panicResolved", eventId, route: `/safety/alert/${eventId}` },
      },
      fcm
    );
    return "resolved";
  }
  return "ignored";
}

/**
 * Re-sends every open, unacknowledged alert once a minute, up to
 * MAX_PANIC_PUSHES in total.
 */
async function resendDue(fcm, now = new Date()) {
  const snap = await db().collection("panicEvents").where("resendDue", "==", true).get();
  let sent = 0;
  for (const doc of snap.docs) {
    const e = doc.data();
    const last = e.lastPushAt?.toDate ? e.lastPushAt.toDate() : new Date(e.lastPushAt ?? 0);
    const attempts = e.pushAttempts ?? 0;
    const open = e.status === "active" || e.status === "duress";
    if (!open || e.acknowledged || attempts >= MAX_PANIC_PUSHES) {
      await doc.ref.set({ resendDue: false }, { merge: true });
      continue;
    }
    // A little slack, so a scheduler that fires a second early does not skip
    // a whole minute.
    if (now.getTime() - last.getTime() < PANIC_RESEND_INTERVAL_MS - 5000) continue;

    await pushTo(
      e.notifiedUserIds ?? [],
      {
        ...alertCopy(e.userName ?? "Someone"),
        data: { type: "panic", eventId: doc.id, route: `/safety/alert/${doc.id}` },
      },
      fcm
    );
    // Email is gentler than push, and an inbox flooded every minute gets
    // filtered: a reminder every third attempt, so every three minutes.
    if ((attempts + 1) % email.EMAIL_REMINDER_EVERY === 0) {
      await email.emailReminder(doc.id, e.userName ?? "Someone");
    }
    await doc.ref.set(
      {
        pushAttempts: attempts + 1,
        lastPushAt: now,
        resendDue: attempts + 1 < MAX_PANIC_PUSHES,
      },
      { merge: true }
    );
    sent += 1;
  }
  return sent;
}

/** Somebody pressed "I'm responding": stop re-sending. */
async function handleAcknowledged(eventId) {
  await db()
    .collection("panicEvents")
    .doc(eventId)
    .set({ acknowledged: true, resendDue: false }, { merge: true });
}

// --- Location shares --------------------------------------------------------

/**
 * Closes shares past their expiry. The client stops writing at expiry too,
 * but a phone that died mid-share never gets the chance, and a share must
 * never be left open indefinitely.
 */
async function expireShares(now = new Date()) {
  const snap = await db()
    .collection("locationShares")
    .where("status", "==", "active")
    .where("expiresAt", "<=", now)
    .get();
  await Promise.all(
    snap.docs.map((d) =>
      d.ref.set({ status: "expired", endedAt: now }, { merge: true })
    )
  );
  return snap.size;
}

// --- Exports ----------------------------------------------------------------

exports.onSafetyContactWritten = onDocumentWritten(
  "users/{ownerId}/safetyContacts/{contactUid}",
  async (event) => {
    const { ownerId, contactUid } = event.params;
    const before = event.data?.before?.exists ? event.data.before.data() : null;
    const after = event.data?.after?.exists ? event.data.after.data() : null;
    await handleContactWrite(ownerId, contactUid, before, after);
  }
);

exports.respondToSafetyContact = onCall(async (request) =>
  respond(request.auth?.uid, request.data?.ownerId, request.data?.accept === true)
);

exports.revokeSafetyContact = onCall(async (request) =>
  revoke(request.auth?.uid, request.data?.otherUid)
);

// Every trigger that may send email declares the Resend key.
const withResend = (document) => ({ document, secrets: [email.resendApiKey] });

exports.onPanicEventCreated = onDocumentCreated(
  withResend("panicEvents/{eventId}"),
  async (event) => {
    if (!event.data) return;
    try {
      await handlePanicCreated(event.params.eventId, event.data.data(), messaging());
    } catch (error) {
      // Logged and rethrown: unlike an inbox push, a lost panic alert is worth
      // a retry.
      console.error(`Panic fan-out failed for ${event.params.eventId}:`, error);
      throw error;
    }
  }
);

exports.onPanicEventUpdated = onDocumentUpdated(
  withResend("panicEvents/{eventId}"),
  async (event) => {
    await handlePanicUpdated(
      event.params.eventId,
      event.data?.before?.data(),
      event.data?.after?.data(),
      messaging()
    );
  }
);

exports.onPanicAcknowledged = onDocumentCreated(
  "panicEvents/{eventId}/acknowledgements/{uid}",
  async (event) => handleAcknowledged(event.params.eventId)
);

// us-central1, like every scheduled job here: Cloud Scheduler is not offered
// in africa-south1. See the note at the top of index.js.
exports.resendPanicAlerts = onSchedule(
  { schedule: "every 1 minutes", region: "us-central1", secrets: [email.resendApiKey] },
  async () => {
    await resendDue(messaging());
  }
);

exports.expireLocationShares = onSchedule(
  { schedule: "every 15 minutes", region: "us-central1" },
  async () => {
    await expireShares();
  }
);

exports._internals = {
  handleContactWrite,
  respond,
  revoke,
  handlePanicCreated,
  handlePanicUpdated,
  resendDue,
  handleAcknowledged,
  expireShares,
  MAX_ACCEPTED_CONTACTS,
  MAX_PANIC_PUSHES,
  PANIC_RATE_LIMIT,
  PANIC_CHANNEL_ID,
  MAX_SHARE_MS,
};
