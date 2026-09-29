/**
 * The server's read of Remote Config: safe defaults, and parsing that no
 * console typo can turn into a ceiling of zero.
 */

const test = require("node:test");
const assert = require("node:assert");

const { _internals } = require("../remote_config");
const { DEFAULTS, valuesFrom } = _internals;

const param = (value) => ({ defaultValue: { value } });

test("an empty template is every default: features off", () => {
  const values = valuesFrom({ parameters: {} });
  assert.deepStrictEqual(values, { ...DEFAULTS });
  for (const [key, value] of Object.entries(values)) {
    if (key.startsWith("f")) assert.strictEqual(value, false, key);
  }
});

test("a missing template is every default", () => {
  assert.deepStrictEqual(valuesFrom(undefined), { ...DEFAULTS });
});

test("flags read only the exact string true", () => {
  const values = valuesFrom({
    parameters: {
      f1_goals_challenges: param("true"),
      f2_weekly_insights: param("TRUE"),
      f6_leaderboards: param("1"),
    },
  });
  assert.strictEqual(values.f1_goals_challenges, true);
  assert.strictEqual(values.f2_weekly_insights, false);
  assert.strictEqual(values.f6_leaderboards, false);
});

test("ceilings take positive numbers and ignore anything else", () => {
  const read = (value) =>
    valuesFrom({
      parameters: { integrity_max_daily_steps: param(value) },
    }).integrity_max_daily_steps;

  assert.strictEqual(read("80000"), 80000);
  assert.strictEqual(read("0"), DEFAULTS.integrity_max_daily_steps);
  assert.strictEqual(read("-5"), DEFAULTS.integrity_max_daily_steps);
  assert.strictEqual(read("lots"), DEFAULTS.integrity_max_daily_steps);
});

test("unknown parameters in the template are not passed through", () => {
  const values = valuesFrom({ parameters: { something_else: param("x") } });
  assert.strictEqual("something_else" in values, false);
});
