/**
 * Validation and normalisation for running-calendar records.
 *
 * Split from the script that writes them so the rules can be tested with
 * `node --test` and so the same checks can be reused by whatever ends up
 * promoting a user submission into a listing.
 *
 * The validation is deliberately strict and refuses the whole file rather than
 * skipping bad rows. A calendar is trusted or it is useless: somebody drives to
 * a start line on the strength of a date in here, and a silently-dropped row
 * means a race that quietly does not exist in the app with nothing to show why.
 */

const COLLECTION = "raceEvents";

/** The nine SA provinces plus the neighbours the SA calendar includes. */
const PROVINCES = new Set([
  "EC",
  "FS",
  "GP",
  "KZN",
  "LP",
  "MP",
  "NW",
  "NC",
  "WC",
  "LS",
  "NA",
  "BW",
  "MZ",
  "SZ",
  "ZW",
]);

/**
 * Must match RaceTag in lib/features/races/domain/race_models.dart.
 *
 * Duplicated because a Dart enum cannot be imported here. Change one and you
 * must change the other — an unknown tag is dropped by the app's mapper, so a
 * typo would seed a listing whose badge silently never appears.
 */
const TAGS = new Set([
  "road",
  "trail",
  "xc",
  "comrades-qualifier",
  "two-oceans-qualifier",
  "night",
  "womens",
  "charity",
  "stage",
  "virtual",
]);

/** Must match RaceStatus in race_models.dart. */
const STATUSES = new Set([
  "scheduled",
  "entries_closed",
  "sold_out",
  "postponed",
  "cancelled",
]);

/** Must match RaceSource in race_models.dart. */
const SOURCES = new Set(["curated", "submission", "partner"]);

/**
 * Must match DistanceBucket.forKilometres in race_models.dart, including the
 * generous boundaries — a 21.4 km "half" is a real race that advertises itself
 * that way, and a runner filtering for halfs should still see it.
 */
function bucketFor(km) {
  if (km < 4) return "fun";
  if (km < 7.5) return "5k";
  if (km < 12.5) return "10k";
  if (km < 18) return "15k";
  if (km < 25) return "21.1k";
  if (km < 36) return "30k";
  if (km <= 45) return "42.2k";
  return "ultra";
}

/**
 * A stable document id derived from the race and its date.
 *
 * Derived rather than random so re-running the ingest updates the same document
 * instead of creating a second copy of every race. The date is part of the key
 * because an annual event is a new listing each year — last year's entry link
 * and fees are not this year's.
 */
function eventId(event) {
  const slug = event.name
    .toLowerCase()
    .normalize("NFD")
    // Strip combining marks so "Gqeberha Twilight" and an accented variant of
    // the same name cannot produce two different ids.
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60);
  return `${event.date}-${slug}`;
}

/**
 * Checks one raw record and returns the Firestore document body.
 *
 * Throws with a message naming the field and the row so a 200-race file that
 * fails tells you which line to fix.
 */
function normaliseEvent(raw, label) {
  const fail = (message) => {
    throw new Error(`${label}: ${message}`);
  };

  if (typeof raw !== "object" || raw === null) fail("not an object");

  const known = new Set([
    "name",
    "date",
    "endDate",
    "startTime",
    "province",
    "city",
    "venueName",
    "addressLine",
    "lat",
    "lng",
    "distances",
    "tags",
    "organiser",
    "description",
    "entryUrl",
    "entryPlatform",
    "imageUrl",
    "status",
    "source",
    "verified",
  ]);
  for (const key of Object.keys(raw)) {
    // JSON has no comments, and this file is maintained by hand from PDF fixture
    // lists — so an underscore-prefixed key is treated as one and ignored. That
    // is where a "checked against the AGN list, start moved" note goes.
    if (key.startsWith("_")) continue;
    // Any other unknown key is a typo like "entryURL", and rejecting it is how
    // that gets caught. Ignoring it would seed a race with no entry link and no
    // warning that one was meant to be there.
    if (!known.has(key)) fail(`unknown field "${key}"`);
  }

  if (typeof raw.name !== "string" || raw.name.trim().length < 3) {
    fail("name must be a string of at least 3 characters");
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw.date ?? "")) {
    fail('date must be "YYYY-MM-DD"');
  }
  if (raw.endDate !== undefined) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(raw.endDate)) {
      fail('endDate must be "YYYY-MM-DD"');
    }
    if (raw.endDate < raw.date) fail("endDate is before date");
  }
  const startTime = raw.startTime ?? "06:00";
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(startTime)) {
    fail('startTime must be "HH:mm"');
  }
  if (!PROVINCES.has(raw.province)) {
    fail(`province "${raw.province}" is not one of ${[...PROVINCES].join(", ")}`);
  }
  if (typeof raw.city !== "string" || raw.city.trim().length < 2) {
    fail("city is required");
  }
  if (!Array.isArray(raw.distances) || raw.distances.length === 0) {
    fail("distances must be a non-empty array");
  }

  const distances = raw.distances.map((entry, index) => {
    const where = `${label} distance ${index + 1}`;
    if (typeof entry !== "object" || entry === null) {
      throw new Error(`${where}: not an object`);
    }
    if (typeof entry.km !== "number" || !(entry.km > 0) || entry.km > 300) {
      throw new Error(`${where}: km must be a number between 0 and 300`);
    }
    if (entry.label !== undefined && typeof entry.label !== "string") {
      throw new Error(`${where}: label must be a string`);
    }
    if (entry.priceCents !== undefined) {
      if (!Number.isInteger(entry.priceCents) || entry.priceCents < 0) {
        // Cents, not rands. A fee of 100 means R1, and the most common mistake
        // here is writing 100 for a R100 race.
        throw new Error(`${where}: priceCents must be a whole number of cents`);
      }
      if (entry.priceCents > 2000000) {
        throw new Error(
          `${where}: priceCents over R20 000 — is this rands instead of cents?`
        );
      }
    }
    if (
      entry.startTime !== undefined &&
      !/^([01]\d|2[0-3]):[0-5]\d$/.test(entry.startTime)
    ) {
      throw new Error(`${where}: startTime must be "HH:mm"`);
    }

    return {
      km: entry.km,
      label: entry.label ?? defaultDistanceLabel(entry.km),
      ...(entry.priceCents !== undefined
        ? { priceCents: entry.priceCents }
        : {}),
      ...(entry.startTime !== undefined ? { startTime: entry.startTime } : {}),
    };
  });
  distances.sort((a, b) => a.km - b.km);

  const tags = raw.tags ?? [];
  if (!Array.isArray(tags)) fail("tags must be an array");
  for (const tag of tags) {
    if (!TAGS.has(tag)) fail(`unknown tag "${tag}"`);
  }
  if (raw.status !== undefined && !STATUSES.has(raw.status)) {
    fail(`unknown status "${raw.status}"`);
  }
  if (raw.source !== undefined && !SOURCES.has(raw.source)) {
    fail(`unknown source "${raw.source}"`);
  }
  for (const field of ["lat", "lng"]) {
    if (raw[field] !== undefined && typeof raw[field] !== "number") {
      fail(`${field} must be a number`);
    }
  }
  if ((raw.lat === undefined) !== (raw.lng === undefined)) {
    // One coordinate without the other places the race in the sea off Ghana.
    fail("lat and lng must be given together");
  }
  if (raw.entryUrl !== undefined && !/^https?:\/\/.+/.test(raw.entryUrl)) {
    fail("entryUrl must start with http:// or https://");
  }

  // Times are South African. SA has no daylight saving, so a fixed +02:00
  // offset is exact rather than an approximation — this is the one place the
  // ingest can be simpler than it would be almost anywhere else.
  const startAt = new Date(`${raw.date}T${startTime}:00+02:00`);
  if (Number.isNaN(startAt.getTime())) fail(`could not read date ${raw.date}`);

  // The end of the last day rather than its start, so a stage race stays
  // "upcoming" through its final morning.
  const endAt =
    raw.endDate === undefined
      ? null
      : new Date(`${raw.endDate}T23:59:00+02:00`);

  const priceCents = distances
    .map((distance) => distance.priceCents)
    .filter((price) => price !== undefined);

  return {
    id: eventId(raw),
    doc: {
      name: raw.name.trim(),
      startAt,
      ...(endAt ? { endAt } : {}),
      province: raw.province,
      city: raw.city.trim(),
      ...(raw.venueName ? { venueName: raw.venueName.trim() } : {}),
      ...(raw.addressLine ? { addressLine: raw.addressLine.trim() } : {}),
      ...(raw.lat !== undefined ? { lat: raw.lat, lng: raw.lng } : {}),
      distances,
      // Derived, never hand-written: the app's distance filter reads this array
      // and nothing else, so it has to agree with the distances above.
      distanceBuckets: [...new Set(distances.map((d) => bucketFor(d.km)))],
      tags,
      ...(raw.organiser ? { organiser: raw.organiser.trim() } : {}),
      ...(raw.description ? { description: raw.description.trim() } : {}),
      ...(raw.entryUrl ? { entryUrl: raw.entryUrl.trim() } : {}),
      ...(raw.entryPlatform ? { entryPlatform: raw.entryPlatform } : {}),
      ...(raw.imageUrl ? { imageUrl: raw.imageUrl } : {}),
      status: raw.status ?? "scheduled",
      source: raw.source ?? "curated",
      ...(priceCents.length > 0
        ? { priceFromCents: Math.min(...priceCents) }
        : {}),
      // Only set when the file says somebody actually checked. Absent means the
      // detail screen shows no "last checked" line, which is the honest answer
      // for a row nobody has confirmed.
      ...(raw.verified ? { verifiedAt: new Date(`${raw.verified}T12:00:00+02:00`) } : {}),
    },
  };
}

function defaultDistanceLabel(km) {
  const bucket = bucketFor(km);
  if (bucket === "42.2k") return "Marathon";
  if (bucket === "21.1k") return "Half Marathon";
  return `${Number.isInteger(km) ? km : km.toFixed(1)} km`;
}

/**
 * Validates a whole file and returns `{id, doc}` pairs ready to write.
 *
 * Duplicate ids are an error rather than a last-one-wins merge: two rows with
 * the same name and date mean the file has the race twice, and picking one
 * silently would hide the mistake until somebody noticed the fees were wrong.
 */
function normaliseAll(rows) {
  if (!Array.isArray(rows)) {
    throw new Error("the seed file must contain a JSON array of races");
  }

  const seen = new Map();
  const events = [];
  rows.forEach((raw, index) => {
    const label = `race ${index + 1}${raw?.name ? ` (${raw.name})` : ""}`;
    const event = normaliseEvent(raw, label);
    if (seen.has(event.id)) {
      throw new Error(
        `${label}: duplicate of ${seen.get(event.id)} — same name and date`
      );
    }
    seen.set(event.id, label);
    events.push(event);
  });
  return events;
}

module.exports = {
  COLLECTION,
  PROVINCES,
  TAGS,
  STATUSES,
  SOURCES,
  bucketFor,
  eventId,
  normaliseEvent,
  normaliseAll,
};
