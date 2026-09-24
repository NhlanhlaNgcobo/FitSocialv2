/**
 * Email safety contacts: people without FitSocial.
 *
 * A user may have up to three safety contacts in total, each either a
 * FitSocial account (alerted by push, see safety.js) or an email address
 * (alerted here, through Resend). An email contact:
 *
 *   1. is added by the user through `addEmailSafetyContact`, which emails a
 *      one-time confirmation link;
 *   2. confirms on a web page (a button, not the link itself -- mail scanners
 *      open every link in an email, and a GET that confirmed would confirm on
 *      their behalf);
 *   3. on a panic, receives an email with a private tracking link that opens a
 *      live map in any browser, no app and no account;
 *   4. can press "I'm on my way" on that page, which the user sees exactly as
 *      they see a FitSocial contact's acknowledgement.
 *
 * The confirmation step is not optional. Without it anyone could aim
 * "distress" emails at an address they typed in -- harassment, and the fastest
 * way to get the sending domain marked as spam, after which real alerts land
 * in junk.
 *
 * Links. Every link carries a random token that is the only credential its
 * holder has, and is stored as the document id of emailLinks/{token}. That
 * collection has no rule, so clients can neither read nor list it; the pages
 * below read it through the Admin SDK. An alert link shows the location only
 * while its event is open. Once resolved it says so and shows nothing else.
 *
 * Configuration (functions/.env, or the environment):
 *   SAFETY_EMAIL_FROM  sender, e.g. "FitSocial Safety <alerts@yourdomain>".
 *                      Must be on a domain verified in Resend. Until one is,
 *                      the default below is Resend's test sender, which only
 *                      delivers to the Resend account owner's own address.
 *   SAFETY_LINK_BASE   origin the links point at; defaults to the Firebase
 *                      Hosting site, which rewrites /s/** to `safetyWeb`.
 * Secret:
 *   RESEND_API_KEY     firebase functions:secrets:set RESEND_API_KEY
 */

const crypto = require("node:crypto");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");

const { db } = require("./challenges")._internals;

const resendApiKey = defineSecret("RESEND_API_KEY");

/** Shared with safety.js: FitSocial and email contacts together. */
const MAX_CONTACTS = 3;

/** Confirmation emails one user may trigger per day. */
const MAX_ADDS_PER_DAY = 10;

const CONFIRM_LINK_TTL_MS = 14 * 24 * 60 * 60 * 1000;

/** An email reminder goes out on every Nth push attempt: every 3 minutes. */
const EMAIL_REMINDER_EVERY = 3;

const TOKEN_PATTERN = /^[A-Za-z0-9_-]{24,64}$/;
const EMAIL_PATTERN = /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]{2,}$/;

function fromAddress() {
  return process.env.SAFETY_EMAIL_FROM || "FitSocial Safety <onboarding@resend.dev>";
}

function linkBase() {
  return (process.env.SAFETY_LINK_BASE || "https://fitsocialv2.web.app").replace(/\/$/, "");
}

function serverTimestamp() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function newToken() {
  return crypto.randomBytes(24).toString("base64url");
}

/** One stable id per (owner, address), so the same address cannot be added twice. */
function contactIdFor(email) {
  return crypto.createHash("sha256").update(email).digest("hex").slice(0, 24);
}

function normaliseEmail(raw) {
  return String(raw ?? "").trim().toLowerCase();
}

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// --- Sending ----------------------------------------------------------------

/**
 * Sends one email through Resend. Replaceable for tests via
 * `_internals.setMailer`.
 */
let mailer = async ({ to, subject, html, text }) => {
  const key = resendApiKey.value();
  if (!key) throw new Error("RESEND_API_KEY is not set");
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ from: fromAddress(), to: [to], subject, html, text }),
  });
  if (!response.ok) {
    throw new Error(`Resend ${response.status}: ${await response.text()}`);
  }
  return response.json();
};

/**
 * Sends without ever throwing. One address failing must not stop the others,
 * and must not fail the trigger that is also sending push.
 */
async function sendSafely(message) {
  try {
    await mailer(message);
    return true;
  } catch (error) {
    console.error(`Safety email to a contact failed: ${error.message}`);
    return false;
  }
}

function emailShell(heading, bodyHtml) {
  return `<!DOCTYPE html><html><body style="margin:0;background:#f4f4f4;font-family:Arial,Helvetica,sans-serif;color:#111">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:24px 12px">
<table role="presentation" width="100%" style="max-width:520px;background:#ffffff;border-radius:12px" cellpadding="0" cellspacing="0"><tr><td style="padding:28px 24px">
<h1 style="margin:0 0 16px;font-size:22px;line-height:1.3">${heading}</h1>
${bodyHtml}
<p style="margin:28px 0 0;font-size:12px;color:#777;line-height:1.5">You are getting this because a FitSocial user added this address as a safety contact.</p>
</td></tr></table></td></tr></table></body></html>`;
}

function button(href, label, color = "#d62828") {
  return `<p style="margin:24px 0"><a href="${escapeHtml(href)}" style="display:inline-block;background:${color};color:#ffffff;text-decoration:none;font-weight:bold;padding:14px 22px;border-radius:8px;font-size:16px">${escapeHtml(label)}</a></p>`;
}

function confirmationEmail(ownerName, link) {
  const name = escapeHtml(ownerName);
  return {
    subject: `${ownerName} added you as a safety contact`,
    html: emailShell(
      `${name} added you as a safety contact`,
      `<p style="font-size:16px;line-height:1.5">If ${name} ever raises an emergency alert in the FitSocial app, we will email you a link showing where they are, live, until they are safe.</p>
<p style="font-size:16px;line-height:1.5">You do not need the app or an account. Please confirm you are willing to be contacted.</p>
${button(link, "Review and confirm", "#1f6f68")}
<p style="font-size:14px;color:#555;line-height:1.5">If you do not know ${name}, or would rather not, open the link and choose "No thanks". You will not hear from us again.</p>`
    ),
    text:
      `${ownerName} added you as a safety contact on FitSocial.\n\n` +
      `If they ever raise an emergency alert, we will email you a link showing where they are, live, until they are safe.\n\n` +
      `Confirm or decline here: ${link}\n`,
  };
}

function alertEmail(ownerName, link, { reminder = false } = {}) {
  const name = escapeHtml(ownerName);
  const prefix = reminder ? "STILL ACTIVE: " : "URGENT: ";
  return {
    subject: `${prefix}${ownerName} needs help`,
    html: emailShell(
      `${name} needs help`,
      `<p style="font-size:16px;line-height:1.5">${name} raised an emergency alert in the FitSocial app${reminder ? " and nobody has responded yet" : ""}.</p>
${button(link, `See where ${ownerName} is now`)}
<p style="font-size:16px;line-height:1.5">The map updates every 30 seconds. If you think ${name} is in danger, call <b>10111</b> (police) or <b>112</b>. Both are free, even without airtime.</p>`
    ),
    text:
      `${ownerName} raised an emergency alert in the FitSocial app.\n\n` +
      `See where they are now: ${link}\n\n` +
      `If you think they are in danger, call 10111 (police) or 112. Both are free, even without airtime.\n`,
  };
}

function duressEmail(ownerName, link) {
  const name = escapeHtml(ownerName);
  return {
    subject: `URGENT: ${ownerName}'s alarm was cancelled under pressure`,
    html: emailShell(
      `${name}'s alarm was cancelled under pressure`,
      `<p style="font-size:16px;line-height:1.5">${name} used their emergency code to cancel the alarm. This means they may have been forced to. <b>The alert is still active</b> and their location is still being shared.</p>
${button(link, `See where ${ownerName} is now`)}
<p style="font-size:16px;line-height:1.5">If you think ${name} is in danger, call <b>10111</b> or <b>112</b>.</p>`
    ),
    text:
      `${ownerName} used their emergency code to cancel the alarm. They may have been forced to. The alert is still active.\n\n` +
      `See where they are now: ${link}\n\nCall 10111 or 112 if you think they are in danger.\n`,
  };
}

function safeEmail(ownerName) {
  const name = escapeHtml(ownerName);
  return {
    subject: `${ownerName} is safe`,
    html: emailShell(
      `${name} is safe`,
      `<p style="font-size:16px;line-height:1.5">${name} confirmed they are safe and ended the alert. Their location is no longer being shared.</p>`
    ),
    text: `${ownerName} confirmed they are safe and ended the alert. Their location is no longer being shared.\n`,
  };
}

// --- Contacts ---------------------------------------------------------------

function emailContactsOf(uid) {
  return db().collection("users").doc(uid).collection("emailContacts");
}

async function ownerName(uid) {
  const doc = await db().collection("users").doc(uid).get();
  return doc.exists ? doc.get("displayName") || doc.get("username") || "A FitSocial user" : "A FitSocial user";
}

/** Slots in use: invited or accepted FitSocial contacts, pending or confirmed email ones. */
async function usedSlots(uid) {
  const [app, email] = await Promise.all([
    db().collection("users").doc(uid).collection("safetyContacts")
      .where("status", "in", ["pending", "accepted"]).get(),
    emailContactsOf(uid).where("status", "in", ["pending", "confirmed"]).get(),
  ]);
  return app.size + email.size;
}

/** Contacts who will actually be alerted. */
async function activeSlots(uid) {
  const [app, email] = await Promise.all([
    db().collection("users").doc(uid).collection("safetyContacts")
      .where("status", "==", "accepted").get(),
    emailContactsOf(uid).where("status", "==", "confirmed").get(),
  ]);
  return app.size + email.size;
}

async function addContact(callerId, callerEmail, rawName, rawEmail, now = new Date()) {
  if (!callerId) throw new HttpsError("unauthenticated", "Sign in first.");
  const email = normaliseEmail(rawEmail);
  const name = String(rawName ?? "").trim().slice(0, 60);
  if (!EMAIL_PATTERN.test(email) || email.length > 254) {
    throw new HttpsError("invalid-argument", "That email address does not look right.");
  }
  if (name === "") throw new HttpsError("invalid-argument", "Add their name.");
  if (callerEmail && normaliseEmail(callerEmail) === email) {
    throw new HttpsError("invalid-argument", "You can't add your own email address.");
  }

  const id = contactIdFor(email);
  const ref = emailContactsOf(callerId).doc(id);
  const existing = await ref.get();
  if (existing.exists) {
    const status = existing.get("status");
    if (status === "pending" || status === "confirmed") {
      throw new HttpsError("already-exists", "That address is already one of your contacts.");
    }
    if (status === "declined") {
      // They said no. Asking again would be exactly the nagging the
      // confirmation step exists to prevent.
      throw new HttpsError("failed-precondition", "That person declined to be a safety contact.");
    }
  }

  if ((await usedSlots(callerId)) >= MAX_CONTACTS) {
    throw new HttpsError("resource-exhausted", `You can have up to ${MAX_CONTACTS} safety contacts.`);
  }
  const dayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  const recent = await emailContactsOf(callerId).where("addedAt", ">=", dayAgo).count().get();
  if (recent.data().count >= MAX_ADDS_PER_DAY) {
    throw new HttpsError("resource-exhausted", "Too many invitations today. Try again tomorrow.");
  }

  const token = newToken();
  const batch = db().batch();
  batch.set(ref, {
    name,
    email,
    status: "pending",
    addedAt: now,
    confirmedAt: null,
  });
  batch.set(db().collection("emailLinks").doc(token), {
    kind: "confirm",
    ownerId: callerId,
    contactId: id,
    createdAt: now,
    expiresAt: new Date(now.getTime() + CONFIRM_LINK_TTL_MS),
  });
  await batch.commit();

  const sent = await sendSafely({
    to: email,
    ...confirmationEmail(await ownerName(callerId), `${linkBase()}/s/confirm/${token}`),
  });
  return { contactId: id, emailSent: sent };
}

async function removeContact(callerId, contactId) {
  if (!callerId) throw new HttpsError("unauthenticated", "Sign in first.");
  if (typeof contactId !== "string" || contactId === "") {
    throw new HttpsError("invalid-argument", "contactId is required.");
  }
  const ref = emailContactsOf(callerId).doc(contactId);
  const snap = await ref.get();
  if (!snap.exists) return { status: "removed" };
  // A declined row stays declined, so removing it cannot be used to re-invite.
  if (snap.get("status") !== "declined") {
    await ref.set({ status: "removed" }, { merge: true });
  }
  return { status: "removed" };
}

/** The contact's answer, from the confirmation page. */
async function answerConfirmation(token, accept, now = new Date()) {
  const link = await readLink(token, "confirm");
  if (!link) return "invalid";
  const expires = toDate(link.expiresAt);
  if (expires && now > expires) return "expired";

  const ref = emailContactsOf(link.ownerId).doc(link.contactId);
  const contact = await ref.get();
  if (!contact.exists || contact.get("status") === "removed") return "invalid";
  const status = contact.get("status");
  if (status === "confirmed") return "confirmed";
  if (status === "declined") return "declined";

  if (!accept) {
    await ref.set({ status: "declined", confirmedAt: null }, { merge: true });
    return "declined";
  }
  if ((await activeSlots(link.ownerId)) >= MAX_CONTACTS) return "full";
  await ref.set({ status: "confirmed", confirmedAt: now }, { merge: true });
  return "confirmed";
}

// --- Alerts -----------------------------------------------------------------

async function confirmedEmailContacts(uid) {
  const snap = await emailContactsOf(uid).where("status", "==", "confirmed").get();
  return snap.docs.map((d) => ({ id: d.id, name: d.get("name"), email: d.get("email") }));
}

/**
 * Emails every confirmed contact a private tracking link for [eventId].
 * The links are kept server-side under the event so reminders reuse them.
 * Returns the contacts emailed, for the event's "who was alerted" list.
 */
async function emailAlert(eventId, userId, name, now = new Date()) {
  const contacts = await confirmedEmailContacts(userId);
  const recipients = db().collection("panicEvents").doc(eventId).collection("emailRecipients");
  for (const c of contacts) {
    const token = newToken();
    const batch = db().batch();
    batch.set(db().collection("emailLinks").doc(token), {
      kind: "alert",
      ownerId: userId,
      contactId: c.id,
      contactName: c.name,
      eventId,
      createdAt: now,
    });
    batch.set(recipients.doc(c.id), { email: c.email, name: c.name, token });
    await batch.commit();
    await sendSafely({
      to: c.email,
      ...alertEmail(name, `${linkBase()}/s/track/${token}`),
    });
  }
  return contacts;
}

/** Re-emails every recipient of [eventId] with the kind of message given. */
async function emailRecipientsOf(eventId, build) {
  const snap = await db().collection("panicEvents").doc(eventId).collection("emailRecipients").get();
  let sent = 0;
  for (const d of snap.docs) {
    const link = `${linkBase()}/s/track/${d.get("token")}`;
    if (await sendSafely({ to: d.get("email"), ...build(link) })) sent += 1;
  }
  return sent;
}

const emailReminder = (eventId, name) =>
  emailRecipientsOf(eventId, (link) => alertEmail(name, link, { reminder: true }));
const emailDuress = (eventId, name) =>
  emailRecipientsOf(eventId, (link) => duressEmail(name, link));
const emailSafe = (eventId, name) => emailRecipientsOf(eventId, () => safeEmail(name));

// --- Web --------------------------------------------------------------------

function toDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  return new Date(value);
}

async function readLink(token, kind) {
  if (!TOKEN_PATTERN.test(String(token ?? ""))) return null;
  const snap = await db().collection("emailLinks").doc(token).get();
  if (!snap.exists || snap.get("kind") !== kind) return null;
  return snap.data();
}

/**
 * What the tracking page shows. Position only while the event is open; after
 * that the page says how it ended and nothing more.
 */
async function trackingState(token) {
  const link = await readLink(token, "alert");
  if (!link) return null;
  const event = await db().collection("panicEvents").doc(link.eventId).get();
  if (!event.exists) return null;
  const e = event.data();
  const acks = await db().collection("panicEvents").doc(link.eventId).collection("acknowledgements").get();
  const responders = acks.docs.map((d) => d.get("displayName")).filter(Boolean);
  const base = {
    status: e.status,
    userName: e.userName ?? "Your contact",
    raisedAt: toDate(e.raisedAt)?.toISOString() ?? null,
    responders,
    youResponded: acks.docs.some((d) => d.id === `email_${link.contactId}`),
  };
  if (e.status === "resolved") return base;

  const live = e.current;
  const start = e.location;
  const position = live
    ? { lat: live.lat, lng: live.lng, accuracy: live.accuracy, updatedAt: toDate(live.updatedAt)?.toISOString() ?? null }
    : start
      ? { lat: start.lat, lng: start.lng, accuracy: start.accuracy, updatedAt: toDate(e.raisedAt)?.toISOString() ?? null }
      : null;
  return {
    ...base,
    position,
    batteryPercent: live?.batteryPercent ?? e.batteryPercent ?? null,
  };
}

/** "I'm on my way" from the tracking page. */
async function respondFromLink(token, now = new Date()) {
  const link = await readLink(token, "alert");
  if (!link) return false;
  const event = await db().collection("panicEvents").doc(link.eventId).get();
  if (!event.exists || event.get("status") === "resolved") return false;
  await db()
    .collection("panicEvents")
    .doc(link.eventId)
    .collection("acknowledgements")
    .doc(`email_${link.contactId}`)
    .set({ displayName: link.contactName || "A contact", acknowledgedAt: now, via: "email" });
  return true;
}

const PAGE_HEADERS = {
  "Cache-Control": "no-store",
  "X-Robots-Tag": "noindex, nofollow",
  // The token is in the URL. Without this, every map tile request would carry
  // it to the tile server in the Referer header.
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
};

function htmlPage(title, body, script = "") {
  return `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="referrer" content="no-referrer"><meta name="robots" content="noindex">
<title>${escapeHtml(title)}</title>
<style>
:root{--bg:#f6f6f4;--card:#fff;--ink:#141414;--muted:#5d5d5d;--red:#c62828;--teal:#1f6f68;--line:#e2e2de}
@media (prefers-color-scheme:dark){:root{--bg:#101010;--card:#1b1b1b;--ink:#f3f3f3;--muted:#a9a9a9;--line:#2c2c2c}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
main{max-width:560px;margin:0 auto;padding:20px 16px 40px}
h1{font-size:24px;line-height:1.25;margin:8px 0 12px}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px;margin:14px 0}
.muted{color:var(--muted)}.big{font-size:18px}
.btn{display:block;width:100%;text-align:center;border:0;border-radius:12px;padding:15px;font-size:17px;font-weight:600;text-decoration:none;cursor:pointer;margin:10px 0}
.red{background:var(--red);color:#fff}.teal{background:var(--teal);color:#fff}.plain{background:transparent;color:var(--ink);border:1px solid var(--line)}
#map{height:320px;border-radius:14px;border:1px solid var(--line)}
.row{display:flex;gap:10px}.row .btn{flex:1}
.pill{display:inline-block;padding:3px 10px;border-radius:99px;font-size:14px;font-weight:600}
.pill.red{background:var(--red)}.pill.teal{background:var(--teal)}
</style></head><body><main>${body}</main>${script}</body></html>`;
}

function confirmPage(token, ownerNameText, outcome) {
  const name = escapeHtml(ownerNameText);
  if (outcome === "confirmed") {
    return htmlPage("Confirmed", `<h1>You're ${name}'s safety contact</h1>
<div class="card"><p class="big">If ${name} raises an emergency alert, we'll email you a link to their live location.</p>
<p class="muted">So alerts don't land in spam, add <b>${escapeHtml(fromAddress().replace(/^.*<|>.*$/g, ""))}</b> to your contacts now.</p></div>`);
  }
  if (outcome === "declined") {
    return htmlPage("Declined", `<h1>You won't receive alerts</h1><div class="card"><p>We won't email you about ${name} again.</p></div>`);
  }
  if (outcome === "full") {
    return htmlPage("Not added", `<h1>${name} already has enough contacts</h1><div class="card"><p>Nothing to do. You won't receive alerts.</p></div>`);
  }
  if (outcome === "expired" || outcome === "invalid") {
    return htmlPage("Link expired", `<h1>This link has expired</h1><div class="card"><p>If you still want to be a safety contact, ask them to add you again.</p></div>`);
  }
  return htmlPage("Safety contact", `<h1>${name} added you as a safety contact</h1>
<div class="card"><p class="big">If ${name} ever raises an emergency alert in the FitSocial app, we'll email you a link showing where they are, live, until they are safe.</p>
<p class="muted">You don't need the app or an account. Nothing else is sent to you.</p></div>
<form method="POST" action="">
<button class="btn teal" name="answer" value="yes">Yes, I'll be a safety contact</button>
<button class="btn plain" name="answer" value="no">No thanks</button></form>`);
}

function trackPage(token) {
  const t = JSON.stringify(token);
  return htmlPage("Emergency alert", `
<div id="head"><h1 id="title">Loading…</h1><p id="sub" class="muted"></p></div>
<div id="mapwrap"><div id="map" role="img" aria-label="Map of their last known position"></div>
<p id="age" class="muted"></p></div>
<div class="card" id="facts"></div>
<button class="btn red" id="respond">I'm on my way</button>
<div class="row"><a class="btn plain" href="tel:10111">Call 10111</a><a class="btn plain" href="tel:112">Call 112</a></div>
<a class="btn plain" id="nav" href="#" target="_blank" rel="noopener noreferrer">Open in Google Maps</a>
<p class="muted" style="font-size:14px">Emergency numbers are free, even without airtime. This page updates by itself.</p>`,
`<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" crossorigin="" referrerpolicy="no-referrer">
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js" crossorigin="" referrerpolicy="no-referrer"></script>
<script>
const TOKEN=${t};let map,marker,circle;
function ago(iso){if(!iso)return"";const s=Math.max(0,Math.round((Date.now()-new Date(iso))/1000));
 if(s<60)return s+" seconds ago";const m=Math.round(s/60);if(m<60)return m+" minute"+(m==1?"":"s")+" ago";
 const h=Math.round(m/60);return h+" hour"+(h==1?"":"s")+" ago";}
function esc(v){return String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));}
async function load(){
 let s;try{const r=await fetch("../api/track/"+TOKEN,{cache:"no-store"});if(!r.ok)throw 0;s=await r.json();}
 catch(e){document.getElementById("sub").textContent="Can't reach the server. Retrying…";return;}
 const n=esc(s.userName);
 if(s.status==="resolved"){
  document.getElementById("title").innerHTML=n+" is safe";
  document.getElementById("sub").textContent="They ended the alert. Their location is no longer shared.";
  for(const id of["mapwrap","respond","nav","facts"])document.getElementById(id).style.display="none";return;}
 document.getElementById("title").innerHTML=n+" needs help";
 document.getElementById("sub").innerHTML=s.status==="duress"
  ?'<span class="pill red" style="color:#fff">Alarm cancelled under pressure</span> The alert is still active.'
  :"Alert raised "+ago(s.raisedAt)+".";
 const f=[];if(s.batteryPercent!=null)f.push("Battery: "+esc(s.batteryPercent)+"%");
 f.push(s.responders.length?"Responding: "+s.responders.map(esc).join(", "):"Nobody has responded yet.");
 document.getElementById("facts").innerHTML=f.map(x=>"<div>"+x+"</div>").join("");
 const b=document.getElementById("respond");if(s.youResponded){b.textContent="They know you're on your way";b.disabled=true;b.className="btn teal";}
 const p=s.position;
 if(!p){document.getElementById("age").textContent="Their phone hasn't shared a position yet.";return;}
 document.getElementById("age").textContent="Location updated "+ago(p.updatedAt)+" (accurate to about "+Math.round(p.accuracy||0)+" m).";
 document.getElementById("nav").href="https://www.google.com/maps/search/?api=1&query="+p.lat+","+p.lng;
 const ll=[p.lat,p.lng];
 if(!map&&window.L){map=L.map("map").setView(ll,16);
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png",{maxZoom:19,attribution:"&copy; OpenStreetMap contributors",referrerPolicy:"no-referrer"}).addTo(map);
  marker=L.marker(ll).addTo(map);circle=L.circle(ll,{radius:p.accuracy||0}).addTo(map);}
 else if(map){marker.setLatLng(ll);circle.setLatLng(ll).setRadius(p.accuracy||0);map.panTo(ll);}
}
document.getElementById("respond").addEventListener("click",async e=>{e.target.disabled=true;
 try{await fetch("../api/respond/"+TOKEN,{method:"POST"});}catch(_){}load();});
load();setInterval(load,15000);
</script>`);
}

async function handleWeb(req, res) {
  for (const [k, v] of Object.entries(PAGE_HEADERS)) res.set(k, v);
  const parts = String(req.path || "").split("/").filter(Boolean);
  // Hosting forwards the full path: /s/<route>/<token> or /s/api/<route>/<token>.
  if (parts[0] === "s") parts.shift();

  try {
    if (parts[0] === "confirm" && parts[1]) {
      const token = parts[1];
      const link = await readLink(token, "confirm");
      const name = link ? await ownerName(link.ownerId) : "";
      if (req.method === "POST") {
        const outcome = await answerConfirmation(token, req.body?.answer === "yes");
        return res.status(200).send(confirmPage(token, name, outcome));
      }
      if (!link) return res.status(404).send(confirmPage(token, name, "invalid"));
      return res.status(200).send(confirmPage(token, name, null));
    }
    if (parts[0] === "track" && parts[1]) {
      const state = await trackingState(parts[1]);
      if (!state) {
        return res.status(404).send(htmlPage("Link not found", `<h1>This link isn't valid</h1><div class="card"><p>Check you opened the whole link from the email.</p></div>`));
      }
      return res.status(200).send(trackPage(parts[1]));
    }
    if (parts[0] === "api" && parts[1] === "track" && parts[2]) {
      const state = await trackingState(parts[2]);
      return state ? res.status(200).json(state) : res.status(404).json({ error: "not-found" });
    }
    if (parts[0] === "api" && parts[1] === "respond" && parts[2] && req.method === "POST") {
      const ok = await respondFromLink(parts[2]);
      return res.status(ok ? 200 : 404).json({ ok });
    }
  } catch (error) {
    console.error("safetyWeb failed:", error);
    return res.status(500).send(htmlPage("Error", `<h1>Something went wrong</h1><div class="card"><p>Please reload the page.</p></div>`));
  }
  return res.status(404).send(htmlPage("Not found", `<h1>Page not found</h1>`));
}

// --- Exports ----------------------------------------------------------------

exports.addEmailSafetyContact = onCall({ secrets: [resendApiKey] }, async (request) =>
  addContact(request.auth?.uid, request.auth?.token?.email, request.data?.name, request.data?.email)
);

exports.removeEmailSafetyContact = onCall(async (request) =>
  removeContact(request.auth?.uid, request.data?.contactId)
);

// us-central1, not the africa-south1 default: Firebase Hosting can only
// rewrite to functions in a fixed list of regions, and africa-south1 is not on
// it (deploy fails with "Cloud Run region africa-south1 is not supported").
// The pages stay on the Hosting domain, which reads far more trustworthily in
// an email than a cloudfunctions.net address. Firestore is read from
// Johannesburg across the Atlantic, as the scheduled jobs already do.
exports.safetyWeb = onRequest({ region: "us-central1" }, handleWeb);

exports._internals = {
  resendApiKey,
  MAX_CONTACTS,
  EMAIL_REMINDER_EVERY,
  usedSlots,
  activeSlots,
  addContact,
  removeContact,
  answerConfirmation,
  emailAlert,
  emailReminder,
  emailDuress,
  emailSafe,
  trackingState,
  respondFromLink,
  handleWeb,
  escapeHtml,
  setMailer: (fn) => {
    mailer = fn;
  },
};
