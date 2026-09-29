/**
 * Which week, and which month, a day belongs to.
 *
 * The Node twin of lib/shared/time/period_keys.dart. Goals, the weekly and
 * monthly stats and the friends leaderboard all bucket days into periods, and
 * the app and the server must agree to the day on where a week starts. Both
 * implementations are held to the same cases in
 * test/fixtures/period_keys_cases.json — change one, change both, run both.
 *
 * Everything works on day keys (`YYYY-MM-DD`). Which day an instant falls on is
 * `dayKeyOf` in challenges.js, in the user's wall clock; by the time a day key
 * arrives here the timezone has been dealt with.
 *
 * Weeks are ISO 8601: Monday start, and week 1 holds the year's first
 * Thursday, so 2027-01-01 is in 2026-W53 and 2025-12-29 in 2026-W01.
 */

const DAY_MS = 86400000;

function parseDay(dayKey) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dayKey || "");
  if (!match) throw new Error(`Not a day key: ${dayKey}`);
  return new Date(Date.UTC(+match[1], +match[2] - 1, +match[3]));
}

function formatDay(date) {
  return date.toISOString().slice(0, 10);
}

/** Monday = 1 … Sunday = 7, as ISO and Dart count them. */
function isoWeekday(date) {
  return date.getUTCDay() || 7;
}

function parseWeekId(weekId) {
  const match = /^(\d{4})-W(\d{2})$/.exec(weekId || "");
  const week = match ? +match[2] : 0;
  if (!match || week < 1 || week > 53) {
    throw new Error(`Not a week id: ${weekId}`);
  }
  return { year: +match[1], week };
}

function parseMonthId(monthId) {
  const match = /^(\d{4})-(\d{2})$/.exec(monthId || "");
  const month = match ? +match[2] : 0;
  if (!match || month < 1 || month > 12) {
    throw new Error(`Not a month id: ${monthId}`);
  }
  return { year: +match[1], month };
}

/** The ISO week a day falls in, as `YYYY-Www`. */
function isoWeekIdOf(dayKey) {
  const day = parseDay(dayKey);
  // The Thursday of this day's week decides both the ISO year and the number.
  const thursday = new Date(day.getTime() + (4 - isoWeekday(day)) * DAY_MS);
  const year = thursday.getUTCFullYear();
  const dayOfYear =
    Math.round((thursday.getTime() - Date.UTC(year, 0, 1)) / DAY_MS) + 1;
  const week = Math.floor((dayOfYear - 1) / 7) + 1;
  return `${String(year).padStart(4, "0")}-W${String(week).padStart(2, "0")}`;
}

/** The Monday that opens a week. */
function weekStartDayKey(weekId) {
  const { year, week } = parseWeekId(weekId);
  // 4 January is in week 1 by definition, whichever weekday it falls on.
  const jan4 = new Date(Date.UTC(year, 0, 4));
  const weekOneMonday = jan4.getTime() - (isoWeekday(jan4) - 1) * DAY_MS;
  return formatDay(new Date(weekOneMonday + (week - 1) * 7 * DAY_MS));
}

/** The seven day keys of a week, Monday first. */
function weekDayKeys(weekId) {
  const monday = parseDay(weekStartDayKey(weekId)).getTime();
  return Array.from({ length: 7 }, (_, i) =>
    formatDay(new Date(monday + i * DAY_MS))
  );
}

function previousWeekId(weekId) {
  const monday = parseDay(weekStartDayKey(weekId)).getTime();
  return isoWeekIdOf(formatDay(new Date(monday - 7 * DAY_MS)));
}

/** The calendar month a day falls in, as `YYYY-MM`. */
function monthIdOf(dayKey) {
  parseDay(dayKey);
  return dayKey.slice(0, 7);
}

function monthDayKeys(monthId) {
  const { year, month } = parseMonthId(monthId);
  // Day 0 of the next month is the last day of this one.
  const length = new Date(Date.UTC(year, month, 0)).getUTCDate();
  return Array.from({ length }, (_, i) =>
    formatDay(new Date(Date.UTC(year, month - 1, i + 1)))
  );
}

function previousMonthId(monthId) {
  const { year, month } = parseMonthId(monthId);
  return formatDay(new Date(Date.UTC(year, month - 2, 1))).slice(0, 7);
}

module.exports = {
  isoWeekIdOf,
  weekStartDayKey,
  weekDayKeys,
  previousWeekId,
  monthIdOf,
  monthDayKeys,
  previousMonthId,
};
