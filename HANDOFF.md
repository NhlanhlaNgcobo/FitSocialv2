# FitSocial — Collaborator Handoff
**Date:** 2026-07-01  
**Prepared by:** Nhlanh  
**Repo:** https://github.com/NhlanhlaNgcobo/FitSocialv2  
**Branch:** `main`

---

## What This Document Is

This document covers every change made to the codebase during the Phase 4 development sprint — new screens, shared widgets, sensor integration, Firebase tooling, and infrastructure configuration. Read this before touching any of the files listed below. A separate full architecture document lives at `CODEBASE_ANALYSIS.md`.

---

## Quick-Start for Your Machine

```sh
git clone https://github.com/NhlanhlaNgcobo/FitSocialv2.git
cd FitSocialv2/fitsocial_app
flutter pub get
```

Then do **one** of the following depending on your goal:

**A — Run against real Firebase (real device / release build)**
1. Run `flutterfire configure` — this generates `lib/firebase_options.dart` (gitignored, you need your own copy)
2. Deploy Firestore rules: `npx firebase-tools deploy --only firestore:rules --project fitsocialv2`
3. `flutter run -d <device>`

**B — Run against local emulators (no credentials needed)**
1. Install JDK 21+ (Eclipse Temurin recommended)
2. `cd fitsocial_app && firebase emulators:start --only firestore,auth` (Terminal 1)
3. `cd tool/seed && npm install && npm run seed` (Terminal 2 — seeds mock data)
4. In `lib/core/bootstrap/app_bootstrap.dart`, add emulator wiring after `Firebase.initializeApp()`:
   ```dart
   FirebaseFirestore.instance.useFirestoreEmulator('10.0.2.2', 8080);
   await FirebaseAuth.instance.useAuthEmulator('10.0.2.2', 9099);
   ```
5. `flutter run -d emulator-5554`

**C — Demo mode (no Firebase at all — instant UI walkthrough)**
1. In `lib/core/config/app_config.dart`, change:
   ```dart
   const appConfig = AppConfig(backendMode: BackendMode.demo, ...);
   ```
   > Note: `BackendMode.demo` was removed before this commit. To restore it, see the [Demo Mode section](#demo-mode-toggle) below.
2. `flutter run -d <any device>`

---

## Changes Made This Sprint

### 1. Workout Log Screen — Rebuilt (`lib/features/main/presentation/workout_log_screen.dart`)

**What changed:** The old screen had a single multi-line textarea for exercises. It's been rebuilt from the ground up.

**New design:**
- Dynamic exercise list using `AnimatedList` — each item slides in/out with animation
- Each exercise row has a `StepperField` for Sets and a `StepperField` for Reps
- A separate Notes textarea for general workout notes
- `ShareToFeedToggle` replaces the plain `SwitchListTile`
- Staggered entrance animation (all sections fade + slide in sequentially on screen open)
- Draft syncs to `CreateFlowController` on every keystroke

**Data model change:** `WorkoutDraftState.exercises` changed from `String` (free-text) to `List<ExerciseDraftEntry>` (structured). `WorkoutLogDraft` gained a `notes` field and changed `exercises` from `List<String>` to `List<ExerciseEntry>`. The Firestore save now uses the `notes` field as the post caption (falling back to "Logged N exercises" if notes is empty).

---

### 2. Manual Run Entry Screen — New (`lib/features/main/presentation/manual_run_entry_screen.dart`)

The existing Run screen is GPS live-tracking only. This is a completely new screen for entering a completed run without GPS.

- Route: `/log-run-manual`
- Distance: large editable number field with quick-add chips (+0.1 / +0.5 / +1 / +5 km) that scale-bounce on tap
- Time: three `StepperField` widgets — Hours, Minutes, Seconds
- Estimated pace card (fades and resizes in via `AnimatedSize` once both distance and time are non-zero)
- Reached from: "Enter run manually" icon in the `RunLogScreen` AppBar
- Saves via the same `activityActionsProvider.saveRun()` as the GPS tracker

---

### 3. GPS Run Tracker — Sensor Integration (`lib/features/main/presentation/run_log_screen.dart`)

Major additions on top of the existing GPS tracking:

| Addition | Source |
|---|---|
| Step count (delta from run start) | `pedometer` — hardware step counter chip |
| Cadence in steps/min | Calculated from step delta ÷ elapsed time |
| Pedestrian status (walking/stopped) | `Pedometer.pedestrianStatusStream` |
| Accelerometer motion detection | `sensors_plus` — EMA-smoothed net accel magnitude |
| Activity type classification | GPS speed + accel + pedometer combined |

**New stat row** added to the bottom panel: **Steps | Cadence (spm)** — sits below the existing Live Speed / Avg Pace row. Shows `--` gracefully on devices without hardware step counter.

**Status pill** now shows activity type instead of generic "Tracking live":
- Stationary (speed < 0.5 km/h + no accel + pedometer stopped)
- Walking (< 6 km/h)
- Jogging (6–10 km/h)
- Running (10+ km/h)

---

### 4. New Shared Widgets (`lib/shared/widgets/`)

Four new reusable widgets — use these everywhere, don't reinvent them:

| File | Widget | Use case |
|---|---|---|
| `stepper_field.dart` | `StepperField` | +/− numeric stepper with animated value slide transition. Params: `label`, `value`, `onChanged`, `min`, `max`, `step`, `decimals`, `suffix` |
| `share_to_feed_toggle.dart` | `ShareToFeedToggle` | Animated card-style toggle. Params: `value`, `onChanged`, `subtitle`. Replaces plain `SwitchListTile` everywhere |
| `staggered_fade_in.dart` | `StaggeredFadeIn` | Staggers child entrance by `index` out of `itemCount`. Wrap top-level form sections with this on any new logging screen |
| `bouncy_chip.dart` | `BouncyChip` | Pill button with scale-down press animation. Used for quick-add distance chips |

---

### 5. State — CreateFlowController Updated (`lib/features/main/application/create_flow_controller.dart`)

Previously untracked; now committed with these additions:

- `ExerciseDraftEntry` class (id, name, sets, reps) — replaces the free-text exercise string
- `WorkoutDraftState` restructured: exercises now `List<ExerciseDraftEntry>`, added `notes` field
- `RunDraftState` added (distanceKm, hours, minutes, seconds, shareToFeed) — for manual run draft persistence
- `CreateFlowState` gains `runDraft` field; `hasDraft` now includes run drafts
- `updateRun()` and `completeRun()` added to `CreateFlowController`
- Resume logic in `CreateScreen` extended to handle run draft resumption (navigates to `/log-run-manual`)

---

### 6. Android Sensor Permissions (`android/app/src/main/AndroidManifest.xml`)

These permissions were missing and have been added:

```xml
ACCESS_BACKGROUND_LOCATION    — GPS stays alive when screen is off during a run
FOREGROUND_SERVICE            — required to run GPS in a foreground service
FOREGROUND_SERVICE_LOCATION   — required on Android 14+ (compileSdk = 34)
ACTIVITY_RECOGNITION          — hardware step counter access (Android 10+)
BODY_SENSORS                  — reserved for future heart rate / wearable integration
```

Also: `FirebaseInitProvider` is explicitly disabled in the manifest. This prevents the Google Services Gradle plugin from auto-initializing Firebase natively before `Firebase.initializeApp()` is called from Dart — which was causing a `[core/duplicate-app]` crash.

---

### 7. Firebase Bootstrap (`lib/core/bootstrap/app_bootstrap.dart`)

`bootstrapApp()` now calls `Firebase.initializeApp(options: resolveFirebaseOptions())` as the sole Firebase initializer. `FirebaseInitProvider` being disabled in the manifest means this is safe and won't double-initialize.

---

### 8. New Dependencies (`pubspec.yaml`)

```yaml
pedometer: ^4.0.2     # hardware step counter + pedestrian status streams
sensors_plus: ^6.1.1  # accelerometer, gyroscope, barometer access
```

---

### 9. Firebase & Local Dev Tooling

**`firebase.json`** — added emulator ports (Firestore 8080, Auth 9099, UI 4000)

**`firestore.rules`** — auth-gated rules written and ready to deploy:
- `users/{userId}` — own document only
- `posts` — authenticated read, own-post write
- `progress` — authenticated read, no write

**`firestore.indexes.json`** — currently empty; composite indexes will be needed (see Next Steps)

**`tool/seed/`** — Node.js seed script for local emulator. Seeds 8 users, 24 posts, 4 progress metrics. Idempotent (clears `mock-*` docs before re-seeding). Requires JDK 21+.

---

## What Is NOT in This Commit

| Item | Reason |
|---|---|
| `lib/firebase_options.dart` | Gitignored — contains real API key. Each developer generates their own via `flutterfire configure` |
| `tool/seed/node_modules/` | Gitignored — run `npm install` in `tool/seed/` |
| Emulator screenshot `.png` files | Dev-session artifacts, not project assets |

---

## Demo Mode Toggle

During development, a `BackendMode.demo` was built to let you walk through all screens without Firebase. It was removed before this commit to keep the codebase clean. To restore it temporarily:

1. In `app_config.dart`: add `demo` to the `BackendMode` enum, set `backendMode: BackendMode.demo`
2. In `app_bootstrap.dart`: add early return `if (appConfig.isDemo) return BootstrapStatus(backendMode: BackendMode.demo, firebaseConfigured: false)`
3. In `app_session.dart`: add `signInAsDemo()` method that hardcodes stage = authenticated + a fake profile; call it from the provider when demo
4. In `content_repository.dart`: add `DemoContentRepository` that returns hardcoded posts/metrics/stories

Or just ask — the whole pattern is documented in `CODEBASE_ANALYSIS.md §14`.

---

## File Map — What Changed and Why

```
fitsocial_app/
├── android/app/src/main/AndroidManifest.xml    ← Added 5 sensor permissions + FirebaseInitProvider disabled
├── firebase.json                               ← Added emulator ports (firestore/auth/ui)
├── firestore.rules                             ← NEW — auth-gated rules, ready to deploy
├── firestore.indexes.json                      ← NEW — empty now, needs composite indexes (see Next Steps)
├── pubspec.yaml                                ← Added: pedometer, sensors_plus
├── .gitignore                                  ← Added: node_modules/, firebase-debug.log, ui-debug.log
├── lib/
│   ├── app/router/app_router.dart              ← Added /log-run-manual route
│   ├── core/
│   │   ├── bootstrap/app_bootstrap.dart        ← Firebase init as sole initializer
│   │   └── config/app_config.dart              ← BackendMode enum (firebase only)
│   ├── features/
│   │   ├── auth/application/app_session.dart   ← Restored to clean state (no demo code)
│   │   └── main/
│   │       ├── application/
│   │       │   └── create_flow_controller.dart ← NEW (was untracked) — ExerciseDraftEntry, RunDraftState, updateRun, completeRun
│   │       ├── data/
│   │       │   └── firestore_content_repository.dart ← saveWorkout uses notes field for caption
│   │       ├── domain/
│   │       │   └── app_models.dart             ← Added ExerciseEntry; WorkoutLogDraft gains notes + structured exercises
│   │       └── presentation/
│   │           ├── create_screen.dart          ← Draft resume handles run draft → /log-run-manual
│   │           ├── manual_run_entry_screen.dart ← NEW — form-based run entry
│   │           ├── run_log_screen.dart          ← Pedometer + accelerometer + activity classification
│   │           └── workout_log_screen.dart     ← Full rebuild: AnimatedList, StepperField, notes
│   └── shared/widgets/
│       ├── bouncy_chip.dart                    ← NEW
│       ├── share_to_feed_toggle.dart           ← NEW
│       ├── staggered_fade_in.dart              ← NEW
│       └── stepper_field.dart                  ← NEW
└── tool/seed/
    ├── package.json                            ← NEW — Node seed script deps
    ├── seed.js                                 ← NEW — seeds emulator with mock data
    ├── data.js                                 ← NEW — 8 users, 24 posts, 4 progress metrics
    └── README.md                               ← NEW — how to run the seeder
```

---

## Next Steps — By Priority

### P0 — Do These First (Blocking)

- [ ] **Deploy Firestore rules** — every read/write on the live project currently returns `permission-denied`
  ```sh
  npx firebase-tools deploy --only firestore:rules --project fitsocialv2
  ```
- [ ] **Google Maps API key** — restrict it to the app's package + SHA-1 fingerprint in Google Cloud Console; add to CI as a secret

### P1 — Core Social Features

- [ ] **Post interactions** — wire like, comment, bookmark tap handlers on `PostCard`. Likes write to `likes/{postId}/users/{uid}`; comments navigate to a new `/comments/{postId}` screen
- [ ] **Comments screen** — new route `/comments/:postId`, Firestore stream on `comments/{postId}/items` ordered by `createdAt asc`
- [ ] **Camera + Firebase Storage upload** — add `image_picker` package; wire `MealCameraScreen` to capture real photos → upload to Storage → pass URL to meal AI analysis function
- [ ] **Auth cold-start persistence** — check `FirebaseAuth.instance.currentUser` in bootstrap; skip `/welcome` if already signed in
- [ ] **Password reset** — "Forgot password?" link on `LoginScreen` → `FirebaseAuth.sendPasswordResetEmail()`

### P2 — Data & Infrastructure

- [ ] **Firestore composite indexes** — add to `firestore.indexes.json` and deploy:
  - Posts by `authorId + createdAt desc` (profile grid query)
  - Posts by `authorId IN [] + createdAt desc` (following feed)
  - Comments by `postId + createdAt asc`
- [ ] **New Firestore collections** — schema for `follows`, `likes`, `comments`, `notifications`, `workouts/{uid}/sessions`, `runs/{uid}/sessions`
- [ ] **Cloud Functions scaffold** — `functions/` directory; start with `analyzeMealPhoto` (Storage trigger → Vision AI → Firestore write) and `onPostLiked` (counter increment + notification)
- [ ] **Following-based feed** — home feed currently fetches all posts globally; filter by followed user IDs once `follows` collection exists
- [ ] **FCM push notifications** — add `firebase_messaging`, register token on login, receive like/comment/follow notifications

### P3 — Screen Completion

- [ ] **Explore screen** — user search, trending posts, suggested follows (currently placeholder text)
- [ ] **Profile media grid** — query real posts by `authorId`, display thumbnails, tap to open post detail
- [ ] **Achievements backend** — wire Level/XP/badge data from Firestore instead of current hardcoded values
- [ ] **Notifications screen** — the bell icon navigates to `/achievements` (wrong). Create `/notifications` route reading `notifications/{uid}/items`
- [ ] **Background run tracking** — add notification channel for the geolocator foreground service; handle app-kill survival

### P4 — Enhancement & Expansion

- [ ] **Social graph UI** — Follow/Unfollow buttons, Followers/Following list screens, viewing other users' profiles
- [ ] **Music/Podcast SDKs** — real Spotify OAuth + Apple MusicKit integration (currently shows connect prompt only)
- [ ] **iOS target** — run `flutter create --platforms=ios .` then configure `Info.plist`, background modes, Apple Sign-In capability, `GoogleService-Info.plist`
- [ ] **Deprecation cleanup** — 22 `.withOpacity()` → `.withValues(alpha:)` across `activity_screen`, `run_log_screen`, `login_screen`, `fit_social_logo`, `post_card`, `brand_image_tile`
- [ ] **Firebase App Check** — register Android app with Play Integrity for production request validation
- [ ] **Firebase Storage rules** — write rules for `users/{uid}/avatar`, `posts/{postId}/image`, `meals/{uid}/`

---

## Conventions to Follow

- **State management:** Riverpod only. No `setState` in widgets that read from providers (use `ConsumerStatefulWidget`). `setState` is fine for purely local UI state (loading flags, animation state, form field controllers).
- **New logging screens:** Follow the `WorkoutLogScreen` pattern — `ConsumerStatefulWidget`, sync draft on every `onChanged`, wrap form sections with `StaggeredFadeIn`.
- **New toggles:** Use `ShareToFeedToggle` — not `SwitchListTile`.
- **New numeric steppers:** Use `StepperField` — not raw `TextField` for numeric inputs.
- **Theme:** All colors from `AppColors`, all spacing from `AppSpacing`. No hardcoded hex or pixel values except for one-off gradients (document the reason).
- **Firestore writes:** Always go through `ActivityActions` → `ContentRepository` → Firestore. Never write to Firestore directly from a screen widget.
- **Draft flow:** Any new logging screen must read from `createFlowControllerProvider` in `initState` and sync back on every change. The Create screen resumes drafts automatically.

---

*Full architecture documentation: `CODEBASE_ANALYSIS.md`*  
*Backend + frontend outstanding work: see the Next Steps section above*
