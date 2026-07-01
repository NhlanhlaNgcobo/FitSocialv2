# Mock data seeding (local Firestore emulator)

Populates the local Firestore emulator with mock users, feed posts, and
progress metrics so the app's feed/profile/progress screens have enough
content to test scrolling, rendering, and layout — without touching the
real `fitsocialv2` project or needing any Firebase credentials.

## Run it

From `fitsocial_app/`:

```sh
firebase emulators:start --only firestore
```

In a second terminal:

```sh
cd tool/seed
npm install
npm run seed
```

Browse the seeded data at http://127.0.0.1:4000/firestore while the
emulator is running.

## Pointing the app at the emulator

This script only seeds the emulator — it doesn't change the app. To see
the mock data rendered in the running app, the Flutter app itself also
needs to connect to the same emulator (e.g. by calling
`FirebaseFirestore.instance.useFirestoreEmulator(...)` during bootstrap)
and it still needs `lib/firebase_options.dart` to exist (run
`flutterfire configure` once) before Firebase can initialize at all.

## Notes

- All seeded documents use `mock-` prefixed IDs, so re-running `npm run
  seed` clears and replaces only the mock data — it won't touch anything
  else in the database.
- Edit `data.js` to add/change mock users, posts, or progress metrics.
