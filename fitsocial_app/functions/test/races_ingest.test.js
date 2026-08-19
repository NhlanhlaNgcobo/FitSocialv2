// The validation that stands between a hand-transcribed fixture list and the
// calendar users trust.
//
// Worth testing carefully because the failure mode is quiet: a mistyped field
// name or a fee entered in rands does not crash anything, it just puts a wrong
// number in front of somebody deciding whether they can afford a race.
const test = require("node:test");
const assert = require("node:assert");

const {
  bucketFor,
  eventId,
  normaliseEvent,
  normaliseAll,
} = require("../races_ingest");

/** A valid row, which each test then breaks in one specific way. */
function row(overrides = {}) {
  return {
    name: "Chamberlain Country Classic",
    date: "2026-10-03",
    province: "GP",
    city: "Midrand",
    distances: [{ km: 10, priceCents: 9000 }],
    ...overrides,
  };
}

test("bucketFor matches the Dart boundaries", () => {
  assert.equal(bucketFor(3), "fun");
  assert.equal(bucketFor(5), "5k");
  assert.equal(bucketFor(9.8), "10k");
  assert.equal(bucketFor(11.5), "10k");
  assert.equal(bucketFor(15), "15k");
  assert.equal(bucketFor(21.1), "21.1k");
  assert.equal(bucketFor(21.4), "21.1k");
  assert.equal(bucketFor(30), "30k");
  assert.equal(bucketFor(42.2), "42.2k");
  assert.equal(bucketFor(56), "ultra");
  assert.equal(bucketFor(90), "ultra");
});

test("normaliseEvent fills in the defaults", () => {
  const { doc } = normaliseEvent(row(), "test row");

  assert.equal(doc.name, "Chamberlain Country Classic");
  assert.equal(doc.status, "scheduled");
  assert.equal(doc.source, "curated");
  assert.deepEqual(doc.tags, []);
  // 06:00 SAST is 04:00 UTC. SA has no daylight saving, so this is exact.
  assert.equal(doc.startAt.toISOString(), "2026-10-03T04:00:00.000Z");
  assert.equal(doc.endAt, undefined);
});

test("normaliseEvent derives the distance buckets from the distances", () => {
  const { doc } = normaliseEvent(
    row({ distances: [{ km: 5 }, { km: 10 }, { km: 21.1 }] }),
    "test row"
  );
  assert.deepEqual(doc.distanceBuckets, ["5k", "10k", "21.1k"]);
});

test("normaliseEvent collapses distances that share a bucket", () => {
  // A 28 km and a 34 km are both "30k". The array feeds an array-contains-any,
  // so a duplicate would be dead weight in the index.
  const { doc } = normaliseEvent(
    row({ distances: [{ km: 28 }, { km: 34 }] }),
    "test row"
  );
  assert.deepEqual(doc.distanceBuckets, ["30k"]);
});

test("normaliseEvent sorts distances shortest first", () => {
  const { doc } = normaliseEvent(
    row({ distances: [{ km: 21.1 }, { km: 5 }, { km: 10 }] }),
    "test row"
  );
  assert.deepEqual(
    doc.distances.map((d) => d.km),
    [5, 10, 21.1]
  );
});

test("normaliseEvent names the distances the source left unlabelled", () => {
  const { doc } = normaliseEvent(
    row({ distances: [{ km: 10 }, { km: 21.1 }, { km: 42.2 }, { km: 12.5 }] }),
    "test row"
  );
  assert.deepEqual(
    doc.distances.map((d) => d.label),
    ["10 km", "12.5 km", "Half Marathon", "Marathon"]
  );
});

test("normaliseEvent records the cheapest fee as priceFromCents", () => {
  const { doc } = normaliseEvent(
    row({
      distances: [
        { km: 21.1, priceCents: 15000 },
        { km: 5, priceCents: 5000 },
      ],
    }),
    "test row"
  );
  assert.equal(doc.priceFromCents, 5000);
});

test("normaliseEvent leaves priceFromCents off when no fee is published", () => {
  // Absent, not zero. A free fun run and an unannounced fee must not look the
  // same to the app.
  const { doc } = normaliseEvent(row({ distances: [{ km: 10 }] }), "test row");
  assert.equal("priceFromCents" in doc, false);
});

test("normaliseEvent puts a stage race's end at the end of its last day", () => {
  const { doc } = normaliseEvent(
    row({ date: "2026-11-13", endDate: "2026-11-15" }),
    "test row"
  );
  // 23:59 SAST on the 15th, so the race is still upcoming on its final morning.
  assert.equal(doc.endAt.toISOString(), "2026-11-15T21:59:00.000Z");
});

test("normaliseEvent only sets verifiedAt when the file claims a check", () => {
  assert.equal("verifiedAt" in normaliseEvent(row(), "r").doc, false);
  assert.equal(
    "verifiedAt" in normaliseEvent(row({ verified: "2026-08-19" }), "r").doc,
    true
  );
});

test("normaliseEvent ignores underscore-prefixed comment keys", () => {
  const { doc } = normaliseEvent(
    row({ _comment: "checked against the AGN list", _source: "AGN p.4" }),
    "test row"
  );
  assert.equal(doc.name, "Chamberlain Country Classic");
});

test("normaliseEvent rejects a misspelled field instead of dropping it", () => {
  // The whole reason unknown keys are fatal: "entryURL" would otherwise seed a
  // race whose Enter button is permanently disabled, with nothing to explain it.
  assert.throws(
    () => normaliseEvent(row({ entryURL: "https://example.test" }), "test row"),
    /unknown field "entryURL"/
  );
});

test("normaliseEvent rejects a fee that looks like rands", () => {
  assert.throws(
    () =>
      normaliseEvent(row({ distances: [{ km: 10, priceCents: 5000000 }] }), "r"),
    /rands instead of cents/
  );
});

test("normaliseEvent rejects a fractional fee", () => {
  assert.throws(
    () =>
      normaliseEvent(row({ distances: [{ km: 10, priceCents: 90.5 }] }), "r"),
    /whole number of cents/
  );
});

test("normaliseEvent rejects half a coordinate pair", () => {
  assert.throws(
    () => normaliseEvent(row({ lat: -25.98 }), "r"),
    /lat and lng must be given together/
  );
});

test("normaliseEvent rejects the things a transcription typo produces", () => {
  assert.throws(
    () => normaliseEvent(row({ date: "3 Oct 2026" }), "r"),
    /YYYY-MM-DD/
  );
  assert.throws(() => normaliseEvent(row({ province: "GAU" }), "r"), /province/);
  assert.throws(() => normaliseEvent(row({ startTime: "6:30" }), "r"), /HH:mm/);
  assert.throws(() => normaliseEvent(row({ startTime: "26:30" }), "r"), /HH:mm/);
  assert.throws(() => normaliseEvent(row({ distances: [] }), "r"), /non-empty/);
  assert.throws(
    () => normaliseEvent(row({ tags: ["ultra"] }), "r"),
    /unknown tag/
  );
  assert.throws(
    () => normaliseEvent(row({ entryUrl: "www.example.test" }), "r"),
    /must start with http/
  );
  assert.throws(
    () =>
      normaliseEvent(row({ date: "2026-11-15", endDate: "2026-11-13" }), "r"),
    /endDate is before date/
  );
});

test("normaliseEvent names the row it could not read", () => {
  assert.throws(
    () => normaliseEvent(row({ province: "XX" }), "race 7 (Some Race)"),
    /^Error: race 7 \(Some Race\): province/
  );
});

test("eventId is stable, and separates one year's running from the next", () => {
  const a = eventId({
    name: "Chamberlain Country Classic",
    date: "2026-10-03",
  });
  const b = eventId({
    name: "Chamberlain Country Classic",
    date: "2026-10-03",
  });
  const nextYear = eventId({
    name: "Chamberlain Country Classic",
    date: "2027-10-02",
  });

  assert.equal(a, b, "re-running the ingest must update, not duplicate");
  assert.notEqual(a, nextYear, "next year's running is a new listing");
  assert.equal(a, "2026-10-03-chamberlain-country-classic");
});

test("eventId folds punctuation and spacing so one race cannot become two", () => {
  assert.equal(
    eventId({ name: "Gqeberha Twilight Run", date: "2026-10-03" }),
    eventId({ name: "Gqeberha  Twilight—Run", date: "2026-10-03" })
  );
});

test("normaliseAll refuses a file that lists the same race twice", () => {
  assert.throws(() => normaliseAll([row(), row()]), /duplicate of race 1/);
});

test("normaliseAll refuses anything that is not an array", () => {
  assert.throws(() => normaliseAll({ races: [] }), /JSON array/);
});

test("normaliseAll returns every row when the file is clean", () => {
  const events = normaliseAll([
    row(),
    row({ name: "Another Race", date: "2026-10-10" }),
  ]);
  assert.equal(events.length, 2);
});
