/**
 * The server's read of Remote Config.
 *
 * The app and the server must agree on two kinds of value: whether a Build 11
 * feature is on, and the integrity ceilings a day's numbers are judged by.
 * The app reads them through lib/core/config/feature_flags.dart; this is the
 * same parameters, read from the same (client) template through the Admin SDK,
 * so a ceiling changed in the console moves the ranking and the app's
 * "excluded from ranking" note together.
 *
 * Only a parameter's default value is read. Conditions are evaluated on the
 * device and have no meaning here, and nothing on the server needs them: a
 * kill switch is for everybody or it is not a kill switch.
 *
 * Every default below is the safe one — features off, ceilings at their
 * documented values — and is what the server acts on whenever the template
 * cannot be read. The keys and fallbacks must match FeatureFlag and Tunable
 * in the Dart file.
 */

const admin = require("firebase-admin");

const DEFAULTS = Object.freeze({
  f1_goals_challenges: false,
  f2_weekly_insights: false,
  f3_up_next: false,
  f4_compare: false,
  f5_recap_cards: false,
  f6_leaderboards: false,
  integrity_max_daily_steps: 100000,
  integrity_max_daily_active_minutes: 1440,
});

/**
 * How long a read template is trusted. Five minutes is how long a kill switch
 * takes to reach a warm instance at worst — short enough to be a kill switch,
 * long enough that a burst of triggers reads the template once, not once each.
 */
const CACHE_MS = 5 * 60 * 1000;

let cached = null;
let cachedAt = 0;
let inflight = null;

/** Parses one parameter's default value against the type of its fallback. */
function parse(raw, fallback) {
  if (raw == null) return fallback;
  if (typeof fallback === "boolean") return raw === "true";
  if (typeof fallback === "number") {
    const n = Number(raw);
    // Zero or negative is treated as unset, as in the app: a ceiling of zero
    // would exclude every step anybody has taken.
    return Number.isFinite(n) && n > 0 ? n : fallback;
  }
  return raw;
}

/** Reads the template's defaults into a plain `{ key: value }` of known keys. */
function valuesFrom(template) {
  const out = { ...DEFAULTS };
  const params = template?.parameters || {};
  for (const key of Object.keys(DEFAULTS)) {
    out[key] = parse(params[key]?.defaultValue?.value, DEFAULTS[key]);
  }
  return out;
}

async function load(now) {
  try {
    const template = await admin.remoteConfig().getTemplate();
    cached = valuesFrom(template);
  } catch (error) {
    // Keep whatever was last read; fall back to defaults if nothing ever was.
    // Logged without the template — it holds nothing about users, but there is
    // no reason to print it either.
    console.warn("remote config unavailable, using last known values", {
      message: error?.message,
    });
    cached = cached || { ...DEFAULTS };
  }
  cachedAt = now;
  return cached;
}

/** Every known value, from cache when fresh. Never rejects. */
async function values(now = Date.now()) {
  if (cached && now - cachedAt < CACHE_MS) return cached;
  if (!inflight) {
    inflight = load(now).finally(() => {
      inflight = null;
    });
  }
  return inflight;
}

async function isOn(flagKey) {
  return (await values())[flagKey] === true;
}

async function tunable(key) {
  return (await values())[key];
}

module.exports = {
  isOn,
  tunable,
  values,
  _internals: {
    DEFAULTS,
    valuesFrom,
    reset() {
      cached = null;
      cachedAt = 0;
      inflight = null;
    },
  },
};
