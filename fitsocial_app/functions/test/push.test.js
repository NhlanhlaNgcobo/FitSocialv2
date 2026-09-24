/**
 * Push delivery.
 *
 * The copy cases here are the same sentences
 * lib/features/notifications/domain/notification_models.dart builds on the Dart
 * side — two implementations of one wording, checked against one set of
 * examples. "every notification type says something" is the pinning test: a
 * tenth kind added to the Dart enum and forgotten in notification_copy.js fails
 * here rather than shipping as a blank push.
 *
 * The delivery cases — token pruning, empty inboxes, self-notification — are
 * this side's own. There is no Dart counterpart to them.
 */

const test = require("node:test");
const assert = require("node:assert");
const Module = require("node:module");

const { createFakeAdmin } = require("./fake_admin");

/**
 * Loads push.js against a fake firebase-admin.
 *
 * `./challenges` is stubbed rather than loaded, for the same reasons
 * running_challenges.test.js stubs it: requiring it would register the real
 * challenge triggers as a side effect, and its memoised `db()` would leak one
 * test's store into the next. Only `db` is taken from it here.
 */
function loadPush(seed = {}) {
  const fake = createFakeAdmin(seed);
  const originalLoad = Module._load;

  Module._load = function (request, parent, isMain) {
    if (request === "firebase-admin") return fake.admin;
    if (request === "firebase-functions/v2/firestore") {
      return { onDocumentCreated: (path, handler) => ({ path, handler }) };
    }
    if (request === "./challenges") {
      return { _internals: { db: () => fake.admin.firestore() } };
    }
    return originalLoad(request, parent, isMain);
  };

  try {
    delete require.cache[require.resolve("../push")];
    delete require.cache[require.resolve("../notification_copy")];
    const push = require("../push");
    return { push, ...fake };
  } finally {
    Module._load = originalLoad;
  }
}

/** One recipient with two registered devices. */
const TWO_DEVICES = {
  "users/recipient/fcmTokens/tok_phone": { platform: "android" },
  "users/recipient/fcmTokens/tok_tablet": { platform: "android" },
};

/**
 * Runs the delivery path directly, bypassing the trigger wrapper — the wrapper
 * only unpacks `event.data` and `event.params`.
 */
async function deliver(loaded, data, notificationId = "n1") {
  await loaded.push._internals.deliver(
    "recipient",
    notificationId,
    data,
    loaded.admin.messaging()
  );
  return loaded.sentMessages;
}

// --- Copy, mirrored from the Dart side --------------------------------------

/**
 * Every stored `type` key in FitNotificationType, with the fields its sentence
 * needs. If you add a kind in Dart, add it here — that is what this list is for.
 */
const EVERY_TYPE = [
  ["follow", { actorId: "actor" }],
  ["like", { postId: "p1", postType: "run", reaction: "fire" }],
  ["mention", { postId: "p1", postType: "image" }],
  ["comment", { postId: "p1", commentId: "c1", postType: "meal" }],
  ["reply", { postId: "p1", commentId: "c1" }],
  ["tag", { postId: "p1", postType: "workout" }],
  ["pulseShare", { postId: "p1", postType: "run" }],
  ["challengeInvite", { challengeId: "ch1", challengeTitle: "September 100" }],
  ["challengeAccepted", { challengeId: "ch1", challengeTitle: "September 100" }],
  [
    "challengeCompleted",
    { challengeId: "ch1", challengeTitle: "September 100" },
  ],
  ["safetyInvite", {}],
  ["safetyAccepted", {}],
  ["safetyRevoked", {}],
];

test("every notification type says something", async () => {
  for (const [type, extra] of EVERY_TYPE) {
    const loaded = loadPush({ ...TWO_DEVICES });
    const sent = await deliver(loaded, {
      type,
      actorId: "actor",
      actorName: "Bear",
      ...extra,
    });

    assert.equal(sent.length, 1, `${type} sent nothing`);
    assert.ok(sent[0].notification.title, `${type} has no title`);
    assert.ok(sent[0].notification.body, `${type} has no body`);
    assert.ok(sent[0].data.route, `${type} has no route`);
  }
});

test("the sentences match the ones the app's own list renders", async () => {
  const cases = [
    [{ type: "follow" }, "Bear", "started following you"],
    [
      { type: "like", postId: "p1", postType: "run", reaction: "fire" },
      "Bear",
      "reacted \u{1F525} to your run",
    ],
    // A like written before there were seven reactions keeps its own wording
    // rather than being retconned into a reaction nobody chose.
    [
      { type: "like", postId: "p1", postType: "image" },
      "Bear",
      "liked your photo",
    ],
    [
      { type: "mention", postId: "p1", postType: "meal" },
      "Bear",
      "mentioned you in a meal",
    ],
    // The comment id is what tells a caption mention from a comment one.
    [
      { type: "mention", postId: "p1", commentId: "c1", postType: "meal" },
      "Bear",
      "mentioned you in a comment",
    ],
    [
      { type: "comment", postId: "p1", commentId: "c1", postType: "workout" },
      "Bear",
      "commented on your workout",
    ],
    [
      { type: "reply", postId: "p1", commentId: "c1" },
      "Bear",
      "replied to your comment",
    ],
    // An unknown postType falls back to "post", which is true of everything.
    [
      { type: "tag", postId: "p1", postType: "sasquatch" },
      "Bear",
      "tagged you in a post",
    ],
    [
      {
        type: "challengeInvite",
        challengeId: "ch1",
        challengeTitle: "September 100",
      },
      "Bear",
      "invited you to September 100",
    ],
    // A challenge notification written before the title was carried still
    // reads as a sentence.
    [
      { type: "challengeAccepted", challengeId: "ch1" },
      "Bear",
      "joined a challenge",
    ],
    // Addressed to the recipient about their own achievement, so the actor's
    // name above it would read as though they had finished it.
    [
      {
        type: "challengeCompleted",
        challengeId: "ch1",
        challengeTitle: "September 100",
      },
      "FitSocial",
      "You finished September 100",
    ],
  ];

  for (const [data, title, body] of cases) {
    const loaded = loadPush({ ...TWO_DEVICES });
    const sent = await deliver(loaded, {
      actorId: "actor",
      actorName: "Bear",
      ...data,
    });

    assert.equal(sent[0].notification.title, title, `title for ${data.type}`);
    assert.equal(sent[0].notification.body, body, `body for ${data.type}`);
  }
});

test("the route matches where the app's own row would go", async () => {
  const cases = [
    [{ type: "follow", actorId: "actor" }, "/user/actor"],
    [{ type: "comment", postId: "p1", commentId: "c1" }, "/post/p1"],
    [{ type: "challengeInvite", challengeId: "ch1" }, "/challenge/board/ch1"],
    // A row that arrived without the id its destination needs still pushes;
    // tapping it just opens the app.
    [{ type: "comment", commentId: "c1" }, ""],
    [{ type: "challengeInvite" }, ""],
  ];

  for (const [data, route] of cases) {
    const loaded = loadPush({ ...TWO_DEVICES });
    const sent = await deliver(loaded, {
      actorId: "actor",
      actorName: "Bear",
      ...data,
    });

    assert.equal(sent[0].data.route, route, `route for ${data.type}`);
  }
});

test("a type this deployment does not know is skipped, not pushed blank", async () => {
  const loaded = loadPush({ ...TWO_DEVICES });
  const sent = await deliver(loaded, {
    type: "somethingAddedLater",
    actorId: "actor",
    actorName: "Bear",
  });

  assert.equal(sent.length, 0);
});

// --- Delivery ---------------------------------------------------------------

test("both of a recipient's devices are addressed in one send", async () => {
  const loaded = loadPush({ ...TWO_DEVICES });
  const sent = await deliver(loaded, {
    type: "follow",
    actorId: "actor",
    actorName: "Bear",
  });

  assert.equal(sent.length, 1);
  assert.deepEqual(sent[0].tokens.sort(), ["tok_phone", "tok_tablet"]);
});

test("a recipient with no registered device is a no-op", async () => {
  const loaded = loadPush({});
  const sent = await deliver(loaded, {
    type: "follow",
    actorId: "actor",
    actorName: "Bear",
  });

  assert.equal(sent.length, 0);
});

test("nobody is buzzed about themselves", async () => {
  const loaded = loadPush({ ...TWO_DEVICES });
  const sent = await deliver(loaded, {
    type: "follow",
    actorId: "recipient",
    actorName: "Bear",
  });

  assert.equal(sent.length, 0);
});

test("the tray entry is tagged, so a repeat replaces rather than stacks", async () => {
  const loaded = loadPush({ ...TWO_DEVICES });
  const sent = await deliver(
    loaded,
    { type: "follow", actorId: "actor", actorName: "Bear" },
    "follow_actor"
  );

  assert.equal(sent[0].android.notification.tag, "follow_actor");
  assert.equal(sent[0].data.notificationId, "follow_actor");
});

test("every data value is a string, which is all FCM will accept", async () => {
  const loaded = loadPush({ ...TWO_DEVICES });
  const sent = await deliver(loaded, {
    type: "comment",
    actorId: "actor",
    actorName: "Bear",
    postId: "p1",
    commentId: "c1",
  });

  for (const [key, value] of Object.entries(sent[0].data)) {
    assert.equal(typeof value, "string", `data.${key} is not a string`);
  }
});

test("a token FCM reports dead is deleted, the healthy one beside it survives", async () => {
  const loaded = loadPush({ ...TWO_DEVICES });
  loaded.tokenFailures.set(
    "tok_tablet",
    "messaging/registration-token-not-registered"
  );

  await deliver(loaded, { type: "follow", actorId: "actor", actorName: "Bear" });

  assert.equal(loaded.store.has("users/recipient/fcmTokens/tok_tablet"), false);
  assert.equal(loaded.store.has("users/recipient/fcmTokens/tok_phone"), true);
});

test("a transient failure does NOT delete the token", async () => {
  const loaded = loadPush({ ...TWO_DEVICES });
  // A quota error or an unavailable backend means this send failed, not that
  // the device is gone. Deleting here would turn an outage into every user
  // silently losing push until they next reinstall.
  loaded.tokenFailures.set("tok_tablet", "messaging/server-unavailable");

  await deliver(loaded, { type: "follow", actorId: "actor", actorName: "Bear" });

  assert.equal(loaded.store.has("users/recipient/fcmTokens/tok_tablet"), true);
});
