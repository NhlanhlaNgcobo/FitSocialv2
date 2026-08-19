// The counting rule behind raceEntryStats.
//
// Worth testing on its own because the whole point of the aggregate is that the
// number is credible enough to put in front of an entry platform. A cooldown
// that silently stopped working would inflate it, and nothing else in the system
// would notice.
const test = require("node:test");
const assert = require("node:assert");

const { plan, monthKey, COOLDOWN_MS } = require("../race_entry_taps")._internals;

/** A Firestore-style timestamp. */
const ts = (iso) => ({ toDate: () => new Date(iso) });

test("a first tap counts as both a tap and a tapper", () => {
  const change = plan({
    before: null,
    after: { lastTapAt: ts("2026-09-05T04:00:00Z") },
  });
  assert.equal(change.taps, 1);
  assert.equal(change.tappers, 1);
  assert.equal(change.month, "2026-09");
});

test("a second tap inside the cooldown does not count", () => {
  // One undecided runner tapping twice while making up their mind. Counting that
  // twice is exactly the overstatement a partner would be right to challenge.
  assert.equal(
    plan({
      before: { lastTapAt: ts("2026-09-05T04:00:00Z") },
      after: { lastTapAt: ts("2026-09-05T04:30:00Z") },
    }),
    null
  );
});

test("a tap just inside the cooldown boundary does not count", () => {
  const start = new Date("2026-09-05T04:00:00Z");
  const justInside = new Date(start.getTime() + COOLDOWN_MS - 1000);
  assert.equal(
    plan({
      before: { lastTapAt: ts(start.toISOString()) },
      after: { lastTapAt: ts(justInside.toISOString()) },
    }),
    null
  );
});

test("a tap past the cooldown counts as a tap but not a new tapper", () => {
  const change = plan({
    before: { lastTapAt: ts("2026-09-05T04:00:00Z") },
    after: { lastTapAt: ts("2026-09-05T06:00:00Z") },
  });
  assert.equal(change.taps, 1);
  assert.equal(change.tappers, 0, "the same person is not a second tapper");
});

test("the function's own firstTapAt write does not count as a tap", () => {
  // onRaceEntryTap writes firstTapAt back onto the document, which re-triggers
  // it. Without this the very first tap would count twice.
  const same = ts("2026-09-05T04:00:00Z");
  assert.equal(
    plan({
      before: { lastTapAt: same },
      after: { lastTapAt: same, firstTapAt: same },
    }),
    null
  );
});

test("a deletion moves nothing", () => {
  // The tap happened. Removing the user's record is not grounds for revising a
  // total we have already reported.
  assert.equal(
    plan({ before: { lastTapAt: ts("2026-09-05T04:00:00Z") }, after: null }),
    null
  );
});

test("a document with no timestamp is ignored rather than counted", () => {
  assert.equal(plan({ before: null, after: {} }), null);
  assert.equal(plan({ before: null, after: { lastTapAt: null } }), null);
});

test("months are bucketed in South African local time", () => {
  // 23:00 UTC on 31 August is 01:00 on 1 September in Johannesburg. Filing that
  // tap under August would misreport the month to every reader of the figure.
  assert.equal(monthKey(new Date("2026-08-31T23:00:00Z")), "2026-09");
  assert.equal(monthKey(new Date("2026-08-31T21:00:00Z")), "2026-08");
  assert.equal(monthKey(new Date("2026-09-05T04:00:00Z")), "2026-09");
});

test("the cooldown is an hour", () => {
  assert.equal(COOLDOWN_MS, 3600000);
});
