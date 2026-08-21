/**
 * The Admin app is created before Firestore is asked for — in every module.
 *
 * This file exists because of a production outage. Every module here guarded
 * initialisation with `admin.apps.length === 0` (or its modular twin,
 * `getApps().length === 0`), which asks whether *any* app exists rather than
 * whether the *default* one does. Those are the same question right up until
 * firebase-functions answers a Firestore trigger: before calling the handler it
 * builds the snapshot behind `event.data`, and to do that it needs an app, and
 * when it cannot find a default one it quietly installs a named app of its own
 * called `__FIREBASE_FUNCTIONS_SDK__`.
 *
 * From that moment the count is 1 and the default app still does not exist, so
 * every guard concluded the work was done, skipped it, and the next line threw
 * "The default Firebase app does not exist". Each Firestore trigger in the
 * project died on its first invocation on every cold start, for as long as the
 * build was live. On the challenge tracker that showed up as five of the seven
 * daily tasks reading zero forever — water and reading kept moving only because
 * the client writes and overlays those two itself — and as Early Worm never
 * crediting a dawn Pulse at all.
 *
 * The test below reproduces that sequence exactly: let the SDK install its
 * named app first, the way it does in production, then call each module's
 * database accessor and require it to work. It fails against the old guard in
 * every module and passes against the current one.
 */

const { test } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const FUNCTIONS_DIR = path.join(__dirname, "..");

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "fitsocial-test";
process.env.FIREBASE_CONFIG =
  process.env.FIREBASE_CONFIG ||
  JSON.stringify({ projectId: process.env.GCLOUD_PROJECT });

/** The internal module firebase-functions uses to get itself an app. */
function functionsSdkApp() {
  return require(
    path.join(FUNCTIONS_DIR, "node_modules/firebase-functions/lib/common/app.js")
  );
}

/**
 * Loads [moduleFile] fresh, with the module registry rewound first so its
 * `require("firebase-admin")` and any memoised handle start from nothing —
 * which is what a cold Cloud Functions instance gives it.
 */
function loadCold(moduleFile) {
  for (const key of Object.keys(require.cache)) {
    if (key.includes("firebase-admin") || key.includes("firebase-functions")) {
      delete require.cache[key];
    }
  }
  const modulePath = require.resolve(path.join(FUNCTIONS_DIR, moduleFile));
  delete require.cache[modulePath];
  return require(modulePath);
}

/**
 * Every module that reaches Firestore, and how to make it do so without
 * touching the network. `db()` and friends only construct a client — no
 * request leaves the process until a read or write is issued, and none is.
 */
const ACCESSORS = [
  ["challenges.js", (m) => m._internals.db()],
  ["account_deletion.js", (m) => m._internals.db()],
  ["race_entry_taps.js", (m) => m._internals.db()],
  ["nutrition_db.js", (m) => m._internals.ensureAdmin().firestore()],
];

for (const [moduleFile, reachFirestore] of ACCESSORS) {
  test(`${moduleFile} reaches Firestore after the SDK installs its own app`, () => {
    const module = loadCold(moduleFile);

    // What firebase-functions does on a Firestore trigger before the handler
    // is called. On a cold instance with no default app, this installs
    // `__FIREBASE_FUNCTIONS_SDK__` — the exact state the old guards misread.
    const sdkApp = functionsSdkApp().getApp();
    assert.equal(
      sdkApp.name,
      "__FIREBASE_FUNCTIONS_SDK__",
      "precondition: the SDK should have installed a named app of its own. If " +
        "this fails, firebase-functions has changed how it gets an app and " +
        "the scenario below may no longer be the one that broke production."
    );

    const firestore = reachFirestore(module);
    assert.ok(firestore, "expected a Firestore instance");
  });
}
