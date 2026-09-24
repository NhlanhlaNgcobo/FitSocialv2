/**
 * Safety: the consent handshake and the panic fan-out.
 *
 * The case that matters most is "a hand-crafted event naming a non-accepted
 * recipient": whatever the client writes, only accepted contacts are pushed.
 */

const test = require("node:test");
const assert = require("node:assert");
const Module = require("node:module");

const { createFakeAdmin } = require("./fake_admin");

class HttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function loadSafety(seed = {}) {
  const fake = createFakeAdmin(seed);
  const originalLoad = Module._load;
  Module._load = function (request, parent, isMain) {
    if (request === "firebase-admin") return fake.admin;
    if (request === "firebase-functions/v2/firestore") {
      const t = (path, handler) => ({ path, handler });
      return { onDocumentCreated: t, onDocumentUpdated: t, onDocumentWritten: t };
    }
    if (request === "firebase-functions/v2/https") {
      return {
        onCall: (opts, handler) => ({ handler: handler ?? opts }),
        onRequest: (opts, handler) => ({ handler: handler ?? opts }),
        HttpsError,
      };
    }
    if (request === "firebase-functions/params") {
      return { defineSecret: (name) => ({ name, value: () => "test-key" }) };
    }
    if (request === "firebase-functions/v2/scheduler") {
      return { onSchedule: (opts, handler) => ({ opts, handler }) };
    }
    if (request === "./challenges") {
      return { _internals: { db: () => fake.admin.firestore() } };
    }
    return originalLoad(request, parent, isMain);
  };
  try {
    delete require.cache[require.resolve("../safety")];
    delete require.cache[require.resolve("../safety_email")];
    delete require.cache[require.resolve("../push")];
    delete require.cache[require.resolve("../notification_copy")];
    const safety = require("../safety")._internals;
    const email = require("../safety_email")._internals;
    // Every email is captured rather than sent.
    const emails = [];
    email.setMailer(async (message) => {
      emails.push(message);
    });
    return { safety, email, emails, fcm: fake.admin.messaging(), ...fake };
  } finally {
    Module._load = originalLoad;
  }
}

const USERS = {
  "users/owner": { displayName: "Naledi", username: "naledi" },
  "users/friend": { displayName: "Thandi", username: "thandi" },
  "users/stranger": { displayName: "Stranger", username: "stranger" },
  "users/friend/fcmTokens/tok_friend": { platform: "android" },
  "users/stranger/fcmTokens/tok_stranger": { platform: "ios" },
};

function accepted(owner, contact) {
  return {
    [`users/${owner}/safetyContacts/${contact}`]: { status: "accepted" },
    [`users/${contact}/safetyContactOf/${owner}`]: { status: "accepted" },
  };
}

// ── handshake ────────────────────────────────────────────────────────────────

test("an invite is mirrored to the invitee and lands in their inbox", async () => {
  const { safety, store } = loadSafety({
    ...USERS,
    "users/owner/safetyContacts/friend": { status: "pending" },
  });
  const result = await safety.handleContactWrite("owner", "friend", null, {
    status: "pending",
  });
  assert.equal(result, "mirrored");
  const mirror = store.get("users/friend/safetyContactOf/owner");
  assert.equal(mirror.status, "pending");
  assert.equal(mirror.displayName, "Naledi");
  assert.equal(store.get("users/owner/safetyContacts/friend").displayName, "Thandi");
  assert.equal(
    store.get("users/friend/notifications/safetyInvite_owner").type,
    "safetyInvite"
  );
});

test("a created row that is not pending is thrown away", async () => {
  const { safety, store } = loadSafety({
    ...USERS,
    "users/owner/safetyContacts/friend": { status: "accepted" },
  });
  const result = await safety.handleContactWrite("owner", "friend", null, {
    status: "accepted",
  });
  assert.equal(result, "rejected:status");
  assert.equal(store.has("users/owner/safetyContacts/friend"), false);
  assert.equal(store.has("users/friend/safetyContactOf/owner"), false);
});

test("inviting a user who does not exist is thrown away", async () => {
  const { safety, store } = loadSafety({
    ...USERS,
    "users/owner/safetyContacts/ghost": { status: "pending" },
  });
  const result = await safety.handleContactWrite("owner", "ghost", null, {
    status: "pending",
  });
  assert.equal(result, "rejected:unknown-user");
  assert.equal(store.has("users/owner/safetyContacts/ghost"), false);
});

test("deleting an invite removes the mirror", async () => {
  const { safety, store } = loadSafety({
    ...USERS,
    "users/friend/safetyContactOf/owner": { status: "pending" },
  });
  await safety.handleContactWrite("owner", "friend", { status: "pending" }, null);
  assert.equal(store.has("users/friend/safetyContactOf/owner"), false);
});

test("the invitee accepts; both sides move together and the owner is told", async () => {
  const { safety, store } = loadSafety({
    ...USERS,
    "users/owner/safetyContacts/friend": { status: "pending" },
    "users/friend/safetyContactOf/owner": { status: "pending" },
  });
  await safety.respond("friend", "owner", true);
  assert.equal(store.get("users/owner/safetyContacts/friend").status, "accepted");
  assert.equal(store.get("users/friend/safetyContactOf/owner").status, "accepted");
  assert.equal(store.get("users/owner/notifications/safety_friend").type, "safetyAccepted");
});

test("nobody can accept an invite that was not sent to them", async () => {
  const { safety } = loadSafety({
    ...USERS,
    "users/owner/safetyContacts/friend": { status: "pending" },
    "users/friend/safetyContactOf/owner": { status: "pending" },
  });
  await assert.rejects(() => safety.respond("stranger", "owner", true), {
    code: "failed-precondition",
  });
});

test("a fourth accepted contact is refused", async () => {
  const seed = { ...USERS };
  for (let i = 0; i < 3; i++) Object.assign(seed, accepted("owner", `c${i}`));
  seed["users/owner/safetyContacts/friend"] = { status: "pending" };
  seed["users/friend/safetyContactOf/owner"] = { status: "pending" };
  const { safety } = loadSafety(seed);
  await assert.rejects(() => safety.respond("friend", "owner", true), {
    code: "resource-exhausted",
  });
});

test("when the contact revokes, the owner is told", async () => {
  const { safety, store } = loadSafety({ ...USERS, ...accepted("owner", "friend") });
  await safety.revoke("friend", "owner");
  assert.equal(store.get("users/owner/safetyContacts/friend").status, "revoked");
  assert.equal(store.get("users/friend/safetyContactOf/owner").status, "revoked");
  assert.equal(store.get("users/owner/notifications/safety_friend").type, "safetyRevoked");
});

test("the owner can revoke too", async () => {
  const { safety, store } = loadSafety({ ...USERS, ...accepted("owner", "friend") });
  await safety.revoke("owner", "friend");
  assert.equal(store.get("users/owner/safetyContacts/friend").status, "revoked");
  assert.equal(store.has("users/friend/notifications/safety_owner"), false);
});

// ── panic fan-out ────────────────────────────────────────────────────────────

test("only accepted contacts are pushed, whatever the client wrote", async () => {
  const { safety, store, sentMessages, fcm } = loadSafety({
    ...USERS,
    ...accepted("owner", "friend"),
    // Pending and revoked contacts get nothing.
    "users/owner/safetyContacts/stranger": { status: "pending" },
    "panicEvents/e1": {
      userId: "owner",
      status: "active",
      notifiedUserIds: ["stranger"],
      raisedAt: new Date(),
    },
  });
  const result = await safety.handlePanicCreated(
    "e1",
    store.get("panicEvents/e1"),
    fcm
  );
  assert.equal(result, "pushed");
  assert.deepEqual(store.get("panicEvents/e1").notifiedUserIds, ["friend"]);
  const tokens = sentMessages.flatMap((m) => m.tokens);
  assert.deepEqual(tokens, ["tok_friend"]);
  assert.equal(sentMessages[0].android.notification.channelId, "panic_alerts");
  assert.equal(
    sentMessages[0].apns.payload.aps["interruption-level"],
    "time-sensitive"
  );
});

test("zero contacts: recorded, nobody pushed, no resend", async () => {
  const { safety, store, sentMessages, fcm } = loadSafety({
    ...USERS,
    "panicEvents/e1": { userId: "owner", status: "active", raisedAt: new Date() },
  });
  const result = await safety.handlePanicCreated("e1", store.get("panicEvents/e1"), fcm);
  assert.equal(result, "no-contacts");
  assert.equal(sentMessages.length, 0);
  assert.equal(store.get("panicEvents/e1").resendDue, false);
});

test("a sixth event inside an hour is recorded but not pushed", async () => {
  const now = new Date("2026-09-23T18:00:00Z");
  const seed = { ...USERS, ...accepted("owner", "friend") };
  for (let i = 0; i < 6; i++) {
    seed[`panicEvents/e${i}`] = {
      userId: "owner",
      status: "active",
      raisedAt: new Date(now.getTime() - i * 60_000),
    };
  }
  const { safety, store, sentMessages, fcm } = loadSafety(seed);
  const result = await safety.handlePanicCreated("e0", store.get("panicEvents/e0"), fcm, now);
  assert.equal(result, "rate-limited");
  assert.equal(sentMessages.length, 0);
});

test("a dead token is pruned, and the send does not crash", async () => {
  const { safety, store, fcm, tokenFailures } = loadSafety({
    ...USERS,
    ...accepted("owner", "friend"),
    "panicEvents/e1": { userId: "owner", status: "active", raisedAt: new Date() },
  });
  tokenFailures.set("tok_friend", "messaging/registration-token-not-registered");
  await safety.handlePanicCreated("e1", store.get("panicEvents/e1"), fcm);
  assert.equal(store.has("users/friend/fcmTokens/tok_friend"), false);
});

test("re-sends once a minute until acknowledged, at most ten times", async () => {
  const start = new Date("2026-09-23T18:00:00Z");
  const { safety, store, sentMessages, fcm } = loadSafety({
    ...USERS,
    ...accepted("owner", "friend"),
    "panicEvents/e1": { userId: "owner", status: "active", raisedAt: start },
  });
  await safety.handlePanicCreated("e1", store.get("panicEvents/e1"), fcm, start);
  assert.equal(sentMessages.length, 1);

  // Too soon.
  await safety.resendDue(fcm, new Date(start.getTime() + 20_000));
  assert.equal(sentMessages.length, 1);

  for (let minute = 1; minute <= 15; minute++) {
    await safety.resendDue(fcm, new Date(start.getTime() + minute * 60_000));
  }
  assert.equal(sentMessages.length, 10);
  assert.equal(store.get("panicEvents/e1").resendDue, false);
});

test("an acknowledgement stops the re-sends", async () => {
  const start = new Date("2026-09-23T18:00:00Z");
  const { safety, store, sentMessages, fcm } = loadSafety({
    ...USERS,
    ...accepted("owner", "friend"),
    "panicEvents/e1": { userId: "owner", status: "active", raisedAt: start },
  });
  await safety.handlePanicCreated("e1", store.get("panicEvents/e1"), fcm, start);
  await safety.handleAcknowledged("e1");
  await safety.resendDue(fcm, new Date(start.getTime() + 120_000));
  assert.equal(sentMessages.length, 1);
});

test("duress tells contacts the cancellation was coerced and keeps resending", async () => {
  const { safety, store, sentMessages, fcm } = loadSafety({
    ...USERS,
    "panicEvents/e1": {
      userId: "owner",
      status: "duress",
      notifiedUserIds: ["friend"],
      userName: "Naledi",
      resendDue: true,
    },
  });
  await safety.handlePanicUpdated(
    "e1",
    { status: "active" },
    store.get("panicEvents/e1"),
    fcm
  );
  assert.equal(sentMessages[0].data.type, "panicDuress");
  assert.match(sentMessages[0].notification.body, /duress/);
  assert.equal(store.get("panicEvents/e1").resendDue, true);
});

test("resolved tells contacts the user is safe and stops resending", async () => {
  const { safety, store, sentMessages, fcm } = loadSafety({
    ...USERS,
    "panicEvents/e1": {
      userId: "owner",
      status: "resolved",
      notifiedUserIds: ["friend"],
      userName: "Naledi",
      resendDue: true,
    },
  });
  await safety.handlePanicUpdated("e1", { status: "active" }, store.get("panicEvents/e1"), fcm);
  assert.equal(sentMessages[0].data.type, "panicResolved");
  assert.equal(store.get("panicEvents/e1").resendDue, false);
});

// ── location shares ──────────────────────────────────────────────────────────

test("shares past their expiry are closed", async () => {
  const now = new Date("2026-09-23T18:00:00Z");
  const { safety, store } = loadSafety({
    "locationShares/old": { status: "active", expiresAt: new Date(now.getTime() - 1) },
    "locationShares/live": { status: "active", expiresAt: new Date(now.getTime() + 60_000) },
  });
  assert.equal(await safety.expireShares(now), 1);
  assert.equal(store.get("locationShares/old").status, "expired");
  assert.equal(store.get("locationShares/live").status, "active");
});

// ── email contacts ───────────────────────────────────────────────────────────

/** Pulls the token out of the first link in an email. */
function tokenIn(message, route) {
  const match = message.text.match(new RegExp(`/s/${route}/([A-Za-z0-9_-]+)`));
  assert.ok(match, `no /s/${route}/ link in: ${message.text}`);
  return match[1];
}

async function addConfirmed(loaded, name = "Mom", address = "mom@example.com") {
  const { email, emails } = loaded;
  await email.addContact("owner", "owner@example.com", name, address);
  const token = tokenIn(emails[emails.length - 1], "confirm");
  assert.equal(await email.answerConfirmation(token, true), "confirmed");
}

test("adding an email contact sends a confirmation, not an alert-ready contact", async () => {
  const loaded = loadSafety({ ...USERS });
  const { email, emails, store } = loaded;
  const { contactId } = await email.addContact("owner", null, "Mom", " Mom@Example.com ");
  assert.equal(emails.length, 1);
  assert.equal(emails[0].to, "mom@example.com");
  assert.match(emails[0].subject, /Naledi added you as a safety contact/);
  assert.equal(store.get(`users/owner/emailContacts/${contactId}`).status, "pending");
});

test("an unconfirmed email contact receives no alert", async () => {
  const loaded = loadSafety({
    ...USERS,
    "panicEvents/e1": { userId: "owner", status: "active", raisedAt: new Date() },
  });
  const { safety, email, emails, store, fcm } = loaded;
  await email.addContact("owner", null, "Mom", "mom@example.com");
  emails.length = 0;
  const result = await safety.handlePanicCreated("e1", store.get("panicEvents/e1"), fcm);
  assert.equal(result, "no-contacts");
  assert.equal(emails.length, 0);
});

test("a confirmed email contact is emailed a tracking link on panic", async () => {
  const loaded = loadSafety({
    ...USERS,
    "panicEvents/e1": { userId: "owner", status: "active", raisedAt: new Date() },
  });
  const { safety, emails, store, fcm } = loaded;
  await addConfirmed(loaded);
  emails.length = 0;
  const result = await safety.handlePanicCreated("e1", store.get("panicEvents/e1"), fcm);
  assert.equal(result, "emailed");
  assert.equal(emails.length, 1);
  assert.match(emails[0].subject, /^URGENT: Naledi needs help/);
  assert.ok(tokenIn(emails[0], "track"));
  const event = store.get("panicEvents/e1");
  assert.equal(event.resendDue, true);
  assert.deepEqual(event.notifiedContacts.map((c) => c.displayName), ["Mom"]);
  // The address itself never lands on the event.
  assert.ok(!JSON.stringify(event).includes("mom@example.com"));
});

test("the tracking link shows the live position while open, and nothing once safe", async () => {
  const loaded = loadSafety({
    ...USERS,
    "panicEvents/e1": {
      userId: "owner",
      status: "active",
      raisedAt: new Date(),
      location: { lat: -26.2, lng: 28.04, accuracy: 8 },
    },
  });
  const { safety, email, emails, store, fcm } = loaded;
  await addConfirmed(loaded);
  await safety.handlePanicCreated("e1", store.get("panicEvents/e1"), fcm);
  const token = tokenIn(emails[emails.length - 1], "track");

  store.set("panicEvents/e1", {
    ...store.get("panicEvents/e1"),
    current: { lat: -26.3, lng: 28.1, accuracy: 5, batteryPercent: 41, updatedAt: new Date() },
  });
  let state = await email.trackingState(token);
  assert.equal(state.position.lat, -26.3);
  assert.equal(state.batteryPercent, 41);
  assert.equal(state.userName, "Naledi");

  store.set("panicEvents/e1", { ...store.get("panicEvents/e1"), status: "resolved" });
  state = await email.trackingState(token);
  assert.equal(state.status, "resolved");
  assert.equal(state.position, undefined);
});

test("a made-up token shows nothing", async () => {
  const { email } = loadSafety({ ...USERS });
  assert.equal(await email.trackingState("x".repeat(32)), null);
  assert.equal(await email.trackingState("../../etc"), null);
});

test("on-my-way from the page reaches the raiser", async () => {
  const loaded = loadSafety({
    ...USERS,
    "panicEvents/e1": { userId: "owner", status: "active", raisedAt: new Date() },
  });
  const { safety, email, emails, store, fcm } = loaded;
  await addConfirmed(loaded);
  await safety.handlePanicCreated("e1", store.get("panicEvents/e1"), fcm);
  const token = tokenIn(emails[emails.length - 1], "track");
  assert.equal(await email.respondFromLink(token), true);
  const acks = [...store.keys()].filter((k) => k.startsWith("panicEvents/e1/acknowledgements/"));
  assert.equal(acks.length, 1);
  assert.equal(store.get(acks[0]).displayName, "Mom");
  assert.equal((await email.trackingState(token)).youResponded, true);
});

test("duress and safe are emailed; reminders go every third minute", async () => {
  const start = new Date("2026-09-24T18:00:00Z");
  const loaded = loadSafety({
    ...USERS,
    "panicEvents/e1": { userId: "owner", status: "active", raisedAt: start },
  });
  const { safety, emails, store, fcm } = loaded;
  await addConfirmed(loaded);
  await safety.handlePanicCreated("e1", store.get("panicEvents/e1"), fcm, start);
  emails.length = 0;

  for (let minute = 1; minute <= 6; minute++) {
    await safety.resendDue(fcm, new Date(start.getTime() + minute * 60_000));
  }
  assert.equal(emails.filter((m) => /^STILL ACTIVE/.test(m.subject)).length, 2);

  emails.length = 0;
  store.set("panicEvents/e1", { ...store.get("panicEvents/e1"), status: "duress" });
  await safety.handlePanicUpdated("e1", { status: "active" }, store.get("panicEvents/e1"), fcm);
  assert.match(emails[0].subject, /cancelled under pressure/);

  store.set("panicEvents/e1", { ...store.get("panicEvents/e1"), status: "resolved" });
  await safety.handlePanicUpdated("e1", { status: "duress" }, store.get("panicEvents/e1"), fcm);
  assert.match(emails[1].subject, /Naledi is safe/);
});

test("three contacts in total, FitSocial and email together", async () => {
  const loaded = loadSafety({
    ...USERS,
    ...accepted("owner", "friend"),
    "users/owner/safetyContacts/stranger": { status: "pending" },
  });
  const { email } = loaded;
  await email.addContact("owner", null, "Mom", "mom@example.com");
  await assert.rejects(() => email.addContact("owner", null, "Dad", "dad@example.com"), {
    code: "resource-exhausted",
  });
});

test("a declined address cannot be asked again, and nothing is re-sent", async () => {
  const loaded = loadSafety({ ...USERS });
  const { email, emails } = loaded;
  await email.addContact("owner", null, "Ex", "ex@example.com");
  const token = tokenIn(emails[0], "confirm");
  assert.equal(await email.answerConfirmation(token, false), "declined");
  await assert.rejects(() => email.addContact("owner", null, "Ex", "ex@example.com"), {
    code: "failed-precondition",
  });
  assert.equal(emails.length, 1);
});

test("the same address cannot be added twice, nor your own", async () => {
  const { email } = loadSafety({ ...USERS });
  await email.addContact("owner", null, "Mom", "mom@example.com");
  await assert.rejects(() => email.addContact("owner", null, "Mom", "MOM@example.com"), {
    code: "already-exists",
  });
  await assert.rejects(() => email.addContact("owner", "me@example.com", "Me", "me@example.com"), {
    code: "invalid-argument",
  });
  await assert.rejects(() => email.addContact("owner", null, "X", "not-an-email"), {
    code: "invalid-argument",
  });
});

test("the confirmation page asks with a button; opening the link confirms nothing", async () => {
  const loaded = loadSafety({ ...USERS });
  const { email, emails, store } = loaded;
  const { contactId } = await email.addContact("owner", null, "Mom", "mom@example.com");
  const token = tokenIn(emails[0], "confirm");
  const res = fakeResponse();
  await email.handleWeb({ method: "GET", path: `/s/confirm/${token}` }, res);
  assert.equal(res.statusCode, 200);
  assert.match(res.body, /method="POST"/);
  assert.equal(store.get(`users/owner/emailContacts/${contactId}`).status, "pending");

  const post = fakeResponse();
  await email.handleWeb(
    { method: "POST", path: `/s/confirm/${token}`, body: { answer: "yes" } },
    post
  );
  assert.match(post.body, /safety contact/);
  assert.equal(store.get(`users/owner/emailContacts/${contactId}`).status, "confirmed");
});

test("names are escaped on the pages", () => {
  const { email } = loadSafety({});
  assert.equal(
    email.escapeHtml(`<script>"x"</script>`),
    "&lt;script&gt;&quot;x&quot;&lt;/script&gt;"
  );
});

function fakeResponse() {
  return {
    statusCode: 200,
    headers: {},
    body: "",
    set(k, v) {
      this.headers[k] = v;
      return this;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    send(body) {
      this.body = body;
      return this;
    },
    json(body) {
      this.body = JSON.stringify(body);
      return this;
    },
  };
}
