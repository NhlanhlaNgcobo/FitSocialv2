# Rules tests

The Flutter suite cannot see `firestore.rules` — it stubs the repository out —
so a rule that refuses a write the app makes every day looks exactly like a
passing test run. That is not hypothetical: the Pulse 75 water and reading
counters shipped with a rule that rejected the first tap of every day, and it
took a tester to find it.

These tests close that gap by sending the same writes the app sends, through
the real rules file, at the emulator.

```
cd fitsocial_app/test_rules
npm install
npm test          # starts the emulator, runs everything, shuts it down
```

Java is required — the Firestore emulator runs on it.
