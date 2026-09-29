/**
 * Week and month keys, checked against the shared fixture.
 *
 * test/period_keys_test.dart runs the same file against the Dart
 * implementation. If a case here fails, the app and the server disagree about
 * which week a day is in.
 */

const test = require("node:test");
const assert = require("node:assert");
const path = require("node:path");

const periods = require("../period_keys");
const cases = require(
  path.join(__dirname, "..", "..", "test", "fixtures", "period_keys_cases.json")
);

for (const c of cases.weekOf) {
  test(`${c.day} is ${c.week} — ${c.why}`, () => {
    assert.strictEqual(periods.isoWeekIdOf(c.day), c.week);
  });
}

for (const c of cases.weekStart) {
  test(`${c.week} opens on ${c.monday}`, () => {
    assert.strictEqual(periods.weekStartDayKey(c.week), c.monday);
    const days = periods.weekDayKeys(c.week);
    assert.strictEqual(days.length, 7);
    assert.strictEqual(days[0], c.monday);
    assert.deepStrictEqual(new Set(days.map(periods.isoWeekIdOf)), new Set([c.week]));
  });
}

for (const c of cases.previousWeek) {
  test(`before ${c.week} is ${c.previous}`, () => {
    assert.strictEqual(periods.previousWeekId(c.week), c.previous);
  });
}

for (const c of cases.months) {
  test(`${c.day} is in ${c.month}`, () => {
    assert.strictEqual(periods.monthIdOf(c.day), c.month);
  });
}

for (const c of cases.monthLength) {
  test(`${c.month} has ${c.days} days`, () => {
    const days = periods.monthDayKeys(c.month);
    assert.strictEqual(days.length, c.days);
    assert.strictEqual(days[0], c.first);
    assert.strictEqual(days[days.length - 1], c.last);
  });
}

for (const c of cases.previousMonth) {
  test(`before ${c.month} is ${c.previous}`, () => {
    assert.strictEqual(periods.previousMonthId(c.month), c.previous);
  });
}

test("malformed keys throw rather than guess", () => {
  for (const day of cases.invalid.days) {
    assert.throws(() => periods.isoWeekIdOf(day), `day "${day}"`);
    assert.throws(() => periods.monthIdOf(day), `day "${day}"`);
  }
  for (const week of cases.invalid.weeks) {
    assert.throws(() => periods.weekStartDayKey(week), `week "${week}"`);
  }
  for (const month of cases.invalid.months) {
    assert.throws(() => periods.monthDayKeys(month), `month "${month}"`);
  }
});
