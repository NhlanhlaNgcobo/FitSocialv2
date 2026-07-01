# FitSocial — Codebase Analysis
**Generated:** 2026-07-01  
**Analyzer:** Claude (claude-sonnet-4-6)  
**Project path:** `fitsocial_app/`  
**Flutter SDK:** 3.x · Dart SDK ≥ 3.3.0  

---

## 1. Project Purpose

FitSocial is a fitness social-media mobile app for Android. Users log workouts, track runs with GPS, photograph meals, and share activity posts to a community feed. The design pattern mirrors Strava + Instagram: social content is anchored to real fitness data (distance, pace, sets, reps, calories).

---

## 2. Tech Stack

| Concern | Choice | Package |
|---|---|---|
| UI Framework | Flutter (Material3 dark theme) | sdk: flutter |
| State management | Riverpod 2.x | flutter_riverpod ^2.5.1 |
| Navigation | go_router with StatefulShellRoute | go_router ^14.2.0 |
| Backend | Firebase (Auth + Firestore + Storage + Analytics) | firebase_core/auth/cloud_firestore ^3-5 |
| Maps | Google Maps Flutter | google_maps_flutter ^2.17.0 |
| GPS | Geolocator | geolocator ^14.0.2 |
| Step counter | Pedometer (hardware step sensor) | pedometer ^4.0.2 |
| Motion sensors | Sensors Plus (accel/gyro/baro) | sensors_plus ^6.1.1 |
| Social auth | Google Sign-In | google_sign_in ^6.2.1 |

---

## 3. Architecture Overview

```
lib/
├── app/
│   ├── router/          # go_router config + auth redirect logic
│   └── theme/           # AppColors, AppSpacing, AppTheme (dark Material3)
├── core/
│   ├── bootstrap/       # App startup: Firebase init, BootstrapStatus
│   └── config/          # AppConfig (BackendMode enum)
├── features/
│   ├── auth/
│   │   ├── application/ # AppSession (ChangeNotifier), Riverpod providers
│   │   ├── data/        # FirebaseAuthRepository, FirebaseUserProfileRepository
│   │   ├── domain/      # AuthModels (UserProfileDraft)
│   │   └── presentation/# WelcomeScreen, LoginScreen, ProfileSetupScreen, EditProfileScreen
│   └── main/
│       ├── application/ # CreateFlowController, ActivityActions, ContentProviders,
│       │                # MusicIntegrationController
│       ├── data/        # FirestoreContentRepository + contract, mappers, models
│       ├── domain/      # app_models.dart — all domain types
│       └── presentation/# All main app screens (see §5)
└── shared/
    ├── layout/          # AppShell (bottom nav host)
    └── widgets/         # Reusable widget library (see §6)
```

### Design pattern
Feature-based vertical slices. Each feature owns application, data, domain, and presentation sub-layers. Riverpod providers wire layers together; screens never touch repositories directly.

---

## 4. Authentication & Session Logic

### Flow
```
App start
  └─ bootstrapApp()
       └─ Firebase.initializeApp()  [FirebaseInitProvider disabled in Manifest]
       └─ BootstrapStatus(firebaseConfigured: true)
            └─ appSessionProvider → AppSession(unauthenticated)
                 └─ Router redirect:
                      unauthenticated → /welcome
                      profileSetup   → /profile-setup
                      authenticated  → /home
```

### AppSession (ChangeNotifier)
State machine with three stages: `unauthenticated → profileSetup → authenticated`.

| Method | Action |
|---|---|
| `signInWithEmail(email, password)` | FirebaseAuth sign-in → loads Firestore profile → sets stage |
| `signUpWithEmail(email, password)` | FirebaseAuth create user → loads profile → stage = profileSetup |
| `continueWithProvider('google')` | Google OAuth → FirebaseAuth credential → same as above |
| `continueWithProvider('apple')` | Apple Sign-In (web or native) |
| `completeProfile(...)` | Saves display name/handle/bio/location to Firestore users/{uid} |
| `signOut()` | Clears all state, stage → unauthenticated |

### UserProfileRepository
`FirebaseUserProfileRepository` reads/writes `users/{uid}` in Firestore:
- `loadCurrentProfile()` — returns null if no document exists (triggers profileSetup stage)
- `saveProfile(...)` — merges `{displayName, handle, bio, location, email, updatedAt}`

### Known issues
- `lib/firebase_options.dart` is gitignored. Real credentials from `google-services.json` are used locally. Run `flutterfire configure` to regenerate properly for each developer.
- Firestore security rules (`firestore.rules`) have not been deployed to the live project. Until they are, authenticated users will see `permission-denied` when reading collections.

---

## 5. Screens & Logic

### 5.1 Auth Screens

**WelcomeScreen** (`/welcome`)  
Animated splash: revolving orange beam over a full-screen athlete photo. Two entry points — "Get Started" (→ `/login?mode=signup`) and "Already have an account? Log in" (→ `/login`).

**LoginScreen** (`/login`)  
- Single screen handles both sign-up and log-in via `isLoginMode` flag (passed as query param `?mode=signup`).
- Expandable email panel (hidden by default; shown when "Use Email" tapped). Pre-filled with `neo@fitsocial.app` / `password123` for dev convenience.
- Google Sign-In button. Error message displayed at bottom via `session.errorMessage`.
- Uses `appSessionProvider.signInWithEmail` / `signUpWithEmail`.

**ProfileSetupScreen** (`/profile-setup`)  
Triggered when `stage == AuthStage.profileSetup` (first login, no Firestore profile doc).  
Collects: Display Name, Handle, Bio, Location. Calls `session.completeProfile(...)`.

**EditProfileScreen** (`/edit-profile`)  
Same form as profile setup but pre-populated. Re-saves via `userProfileRepository.saveProfile`.

---

### 5.2 Main App Screens (Shell — bottom nav)

Shell uses `StatefulShellRoute.indexedStack` (5 branches, state preserved on tab switch).

**HomeScreen** (`/home`)  
Reads three Riverpod async providers:
- `storyItemsProvider` → horizontal scrollable story avatars
- `summaryMetricsProvider` → "This week: N workouts · N meals" stat strip
- `feedPostsProvider` → vertical list of `PostCard` widgets

Also shows a `_MusicSpotlightCard` linking to the Activity screen's music tab.  
Top-right actions: notifications (→ `/achievements`) and quick photo-meal capture.

**ExploreScreen** (`/explore`)  
Placeholder — scaffold for discovery, trending posts, and user search. Shows a single DarkCard message. Not yet connected to backend.

**CreateScreen** (`/create`)  
Action menu for all logging flows. Six tiles:
1. Log a Workout → `/log-workout`
2. Log a Run → `/log-run` (GPS tracker) with link to `/log-run-manual`
3. Log a Meal → `/meal-camera` (photo) → `/meal-review` (manual)
4. Share a Post → `/compose-post`
5. Workout Music → `/activity` (music tab)
6. Add Photo → `/meal-camera`

Shows a draft-resume card at the top when `CreateFlowController.hasDraft == true`.

**ActivityScreen** (`/activity`)  
Three tabs (Progress / Music / Podcasts) driven by `MusicIntegrationController`.  
- Progress tab: `progressMetricsProvider` → bar chart per metric, delta badges
- Music tab: connect Spotify / Apple Music, browse curated playlists by workout type (strength, cardio, HIIT, run, yoga)
- Podcasts tab: curated podcast recommendations by category (mindset, discipline, recovery, business)

**ProfileScreen** (`/profile`)  
- Avatar, follower/following/posts stats (from `profileStatsProvider`)
- Bio, handle, location pulled from `appSessionProvider.profile`
- Four content tabs (All / Workouts / Runs / Meals) — each tab renders a 3-column `GridView` of brand image tiles (placeholder until real post grid is built)
- Edit Profile and Sign Out actions

---

### 5.3 Logging Screens (pushed over shell)

**WorkoutLogScreen** (`/log-workout`)  
Dynamic form-based workout logging.
- Title, Duration (free text), Calories (free text)
- Dynamic exercise list via `AnimatedList`:
  - Each item: Exercise Name (TextField) + Sets stepper + Reps stepper
  - Add / Remove buttons with slide+fade insert/remove animations
- Notes textarea
- `ShareToFeedToggle` animated card
- Draft synced on every keystroke via `createFlowControllerProvider.updateWorkout()`
- On save: builds `WorkoutLogDraft` → `activityActionsProvider.saveWorkout()` → Firestore write → `context.go('/home')`

Saves post with caption from Notes field (or "Logged N exercises" fallback) and metricLabels `[duration, calories, "N moves"]`.

**ManualRunEntryScreen** (`/log-run-manual`)  
Form for manually entering a completed run (no GPS required).
- Distance: large editable number field + quick-add chips (+0.1 / +0.5 / +1 / +5 km, each with bounce-scale animation)
- Time: three `StepperField` widgets for Hours / Minutes / Seconds
- Live estimated pace card (AnimatedSize fade-in once distance + time are non-zero)
- `ShareToFeedToggle`
- Builds `RunLogDraft(distanceKm, elapsed, averagePace, shareToFeed)` → `activityActionsProvider.saveRun()`

**RunLogScreen** (`/log-run`) — GPS Live Tracker  
Full GPS run-tracking screen with Google Maps.
- Map occupies upper portion (polyline drawn as route builds, start/current markers)
- Status pills over map: activity type badge + live speed
- Bottom panel stat cards: Elapsed · Distance · Live Speed · Avg Pace · **Steps · Cadence**
- Geolocator foreground service for continuous GPS even when screen is off
- Pedometer integration: step count delta from hardware step counter, cadence (steps/min) computed over elapsed time
- Accelerometer integration: smoothed net acceleration magnitude (EMA 0.8 weight) for stationary detection when GPS is slow to update
- Activity classification (`_ActivityType`): Stationary / Walking (<6 km/h) / Jogging (6–10) / Running (10+) — combines GPS speed + accelerometer + PedestrianStatus
- Pause/Resume/Finish flow; Finish builds draft → saveRun → Firestore

**MealCameraScreen** (`/meal-camera`)  
Camera viewfinder mockup (photo analysis backend not yet connected). Shows queue state from `createFlowControllerProvider.mealPhotoAnalysisPending`. "Enter Meal Manually" button → `/meal-review`.

**MealReviewScreen** (`/meal-review`)  
Meal form: Name, Calories, Protein/Carbs/Fat (3-column row), Notes, ShareToggle. Saves `MealLogDraft` → `activityActionsProvider.saveMeal()`.

**PostComposeScreen** (`/compose-post`)  
Photo placeholder + caption textarea. Saves `PostDraft` → `activityActionsProvider.sharePost()`.

---

## 6. Shared Widget Library

| Widget | Purpose |
|---|---|
| `PrimaryButton` | 56px orange filled button, optional leading icon |
| `DarkCard` | Themed card wrapper (`surface` bg, `stroke` border, 24px radius) |
| `Avatar` | User initials circle, optional visual tile |
| `StoryAvatar` | Story ring with orange border, "+own story" badge |
| `PostCard` | Full feed card: avatar, activity label, gradient image panel, metrics row (3 Expanded), likes/comments/bookmark row, caption |
| `StatTile` | Label + value tile for stat displays |
| `BrandImageTile` | Asset image tile with overlay gradient |
| `FitSocialLogo` | Animated brand wordmark with optional beam sweep |
| `BottomNav` | Custom bottom navigation bar |
| `StaggeredFadeIn` | Entrance animation wrapper — staggers child fade+slide by index out of N siblings using a single AnimationController + Interval |
| `StepperField` | +/− numeric stepper; animated value transition via AnimatedSwitcher + SlideTransition |
| `ShareToFeedToggle` | Animated card toggle: AnimatedContainer border/bg + AnimatedSwitcher icon (lock↔globe) + Switch |
| `BouncyChip` | Pill button with GestureDetector scale-down on press (AnimatedScale) |

---

## 7. State Management

### Riverpod provider graph

```
bootstrapStatusProvider (Provider<BootstrapStatus>)
  └─ contentRepositoryProvider (Provider<ContentRepository>)
       ├─ feedPostsProvider (FutureProvider<List<FeedPost>>)
       ├─ storyItemsProvider (FutureProvider<List<StoryItem>>)
       ├─ summaryMetricsProvider (FutureProvider<List<SummaryMetric>>)
       ├─ progressMetricsProvider (FutureProvider<List<ProgressMetric>>)
       └─ profileStatsProvider (FutureProvider<List<ProfileStat>>)

appSessionProvider (ChangeNotifierProvider<AppSession>)
  ├─ authRepositoryProvider (Provider<AuthRepository>)
  └─ userProfileRepositoryProvider (Provider<UserProfileRepository>)

createFlowControllerProvider (StateNotifierProvider<CreateFlowController, CreateFlowState>)
  contains:
  ├─ WorkoutDraftState (title, duration, calories, exercises: List<ExerciseDraftEntry>, notes, shareToFeed)
  ├─ RunDraftState (distanceKm, hours, minutes, seconds, shareToFeed)
  ├─ MealDraftState (name, calories, protein, carbs, fat, notes, shareToFeed)
  └─ PostComposerDraftState (caption)

musicIntegrationControllerProvider (StateNotifierProvider)
  └─ tracks selected Activity tab section + music service connections

activityActionsProvider (Provider<ActivityActions>)
  └─ thin service: calls repository.save*(), then invalidates all content providers
```

### Draft persistence
`CreateFlowController` keeps in-memory drafts for all logging flows. Screens sync to it on every `onChanged`. If user navigates away mid-entry, the draft survives in provider state and can be resumed from the Create screen's draft-resume card.

---

## 8. Navigation

Router is defined in `app_router.dart` using `go_router`.

### Redirect logic
```
unauthenticated + not on /welcome or /login → /welcome
profileSetup + not on /profile-setup → /profile-setup
authenticated + on auth route → /home
```

### Route table

| Path | Screen | Shell |
|---|---|---|
| `/welcome` | WelcomeScreen | No |
| `/login` | LoginScreen (?mode=signup) | No |
| `/profile-setup` | ProfileSetupScreen | No |
| `/edit-profile` | EditProfileScreen | No |
| `/log-workout` | WorkoutLogScreen | No |
| `/log-run` | RunLogScreen | No |
| `/log-run-manual` | ManualRunEntryScreen | No |
| `/compose-post` | PostComposeScreen | No |
| `/meal-camera` | MealCameraScreen | No |
| `/meal-review` | MealReviewScreen | No |
| `/achievements` | AchievementsScreen | No |
| `/home` | HomeScreen | Yes |
| `/explore` | ExploreScreen | Yes |
| `/create` | CreateScreen | Yes |
| `/activity` | ActivityScreen | Yes |
| `/profile` | ProfileScreen | Yes |

---

## 9. Data Layer

### Firestore collections

| Collection | Document key | Fields written by app |
|---|---|---|
| `users` | Firebase Auth UID | displayName, handle, bio, location, email, postsCount, followersCount, followingCount, workoutsCount, mealsCount, updatedAt |
| `posts` | auto-ID | authorId, authorName, activity, caption, metricLabels[], likesCount, commentsCount, timestampLabel, themeKey, createdAt |
| `progress` | auto-ID | label, value, delta, chartBars[] |

### Post themes
`themeKey` maps to a gradient in `FirestoreMapper._themeColors`:
- `'burn'` — amber/black (used for workouts, HIIT)
- `'graphite'` — dark grey (used for meals)
- `'sunset'` — brown/black (default — used for runs, posts)

### Repository contract
`ContentRepository` defines 11 methods. Two implementations exist:
- `FirestoreContentRepository` — live Firebase, used when `canUseFirebase == true`
- `UnconfiguredContentRepository` — throws `StateError` with setup instructions

### Activity save pipeline
```
UI screen → WorkoutLogDraft / RunLogDraft / MealLogDraft / PostDraft
  → ActivityActions.save*()
  → FirestoreContentRepository.save*()
       → _incrementUser(workoutsDelta / mealsDelta / postsDelta)
       → _createPost(activity, caption, metricLabels, themeKey)
  → activityActionsProvider.invalidate(feed/metrics/stats providers)
  → UI refreshes
```

---

## 10. Sensor & Movement Tracking

### Android permissions declared

```xml
ACCESS_FINE_LOCATION          — precise GPS
ACCESS_COARSE_LOCATION        — network location fallback
ACCESS_BACKGROUND_LOCATION    — GPS when screen is off during active run
FOREGROUND_SERVICE            — run GPS tracking in a foreground service
FOREGROUND_SERVICE_LOCATION   — Android 14+ foreground service type
ACTIVITY_RECOGNITION          — hardware step counter access (Android 10+)
BODY_SENSORS                  — reserved for heart rate / wearable integration
```

### GPS run tracker (RunLogScreen)
- `Geolocator.getPositionStream(distanceFilter: 5m)` — position updates every 5 m of movement
- Distance accumulation: `Geolocator.distanceBetween` per segment, ignoring micro-jumps < 0.5 m
- Speed: `position.speed * 3.6` (m/s → km/h)
- Pace: elapsed seconds / distance km, formatted as mm:ss/km
- Route polyline: deduplicated LatLng list (jumps < 1 m update last point rather than appending)

### Step counting (Pedometer)
- `Pedometer.stepCountStream` — cumulative steps since device reboot (hardware sensor, very battery efficient)
- Baseline captured at run start; `stepsThisRun = currentCount − baseline`
- `Pedometer.pedestrianStatusStream` — 'walking' | 'stopped', used as signal in activity classification

### Motion intensity (sensors_plus Accelerometer)
- `accelerometerEventStream(samplingPeriod: normalInterval)` — raw XYZ at ~50 Hz
- Net acceleration = `|√(x²+y²+z²) − 9.81|` (strips gravity)
- Smoothed via EMA: `magnitude = magnitude × 0.8 + net × 0.2`
- Threshold 0.15 m/s² → isMoving; prevents GPS-stall false-stationary at run start

### Activity classification
| Condition | Label |
|---|---|
| speed < 0.5 km/h AND accel < 0.15 AND pedometer = 'stopped' | Stationary |
| speed < 6 km/h | Walking |
| 6 ≤ speed < 10 km/h | Jogging |
| speed ≥ 10 km/h | Running |

### Cadence
`stepsThisRun / elapsed.inSeconds × 60`, shown in spm. Requires ≥5 s elapsed and ≥1 step.

---

## 11. Theme & Design System

All tokens are in `lib/app/theme/`:

**Colors (`AppColors`)**
```
black        #050505   scaffold background
surface      #111111   card backgrounds
surfaceHigh  #1A1A1A   elevated surfaces / icon containers
stroke       #2B2B2B   borders / dividers
orange       #D35400   primary (unfocused accents)
orangeBright #FF6B1A   active state / CTA / highlights
white        #F7F7F7   primary text
muted        #AAAAAA   secondary text
success      #31C46C   success states
danger       #E85D5D   error states
```

**Spacing (`AppSpacing`):** xs=4, sm=8, md=16, lg=24, xl=32

**Theme (`AppTheme.darkTheme`):**
- Material 3 dark, `useMaterial3: true`
- Input fields: 18px radius, stroke border, orange focused border
- Cards: 24px radius, stroke border
- AppBar: transparent, 20/700 weight title
- Bottom nav: selected = orangeBright, unselected = muted

---

## 12. Local Development Tooling

### Firebase Emulator Suite (`tool/seed/`)
Node.js seed script targeting local Firestore + Auth emulators.

**Emulator config (`firebase.json`):**
- Firestore: port 8080
- Auth: port 9099
- Emulator UI: port 4000

**Seeded data:**
- 8 mock users (diverse names, real cities, realistic follower counts)
- 24 posts (mixed activity types: runs, strength, HIIT, yoga, meals, status updates) spread over 4 days for scroll testing
- 4 progress metrics (Weekly Volume, Avg Pace, Calories Burned, Active Minutes) with 7-bar chart data

**Running:**
```sh
# Terminal 1 — from fitsocial_app/
firebase emulators:start --only firestore,auth

# Terminal 2
cd tool/seed && npm install && npm run seed
```

Seeding is idempotent — clears `mock-` prefixed docs before re-seeding.

**Note:** Requires JDK 21+ (Eclipse Temurin 21 installed on this machine via winget).

### Firebase rules (`firestore.rules`)
Auth-gated rules for the live project (not yet deployed):
- `users/{userId}` — read/write: `request.auth.uid == userId`
- `posts/{postId}` — read: any authenticated user; create/write: own posts only (`authorId == uid`)
- `progress/{metricId}` — read: any authenticated user; write: false (server-only)

Deploy when ready: `npx firebase-tools deploy --only firestore:rules --project fitsocialv2`

---

## 13. Static Analysis Results

**Command:** `flutter analyze`  
**Errors:** 0  
**Warnings:** 0  
**Info items:** 27 (all pre-existing, none in new code)

| Category | Count | Files |
|---|---|---|
| `withOpacity` deprecated (→ use `.withValues()`) | 22 | activity_screen, run_log_screen, login_screen, fit_social_logo, post_card, brand_image_tile |
| `sort_constructors_first` | 3 | firestore_models.dart |
| `prefer_const_declarations` | 1 | profile_screen.dart |
| `prefer_const_constructors` | 1 | fit_social_logo.dart |

None of these affect runtime behaviour. All are stylistic/deprecation notices inherited from the original codebase; no new issues were introduced.

---

## 14. What's Complete vs. Pending

### Complete (production-ready logic)
- Full Firebase Auth flow (email/password + Google Sign-In)
- Profile create / edit with Firestore persistence
- Home feed (stories + summary stats + posts) with error/loading states
- All logging forms: Workout (structured sets/reps), Manual Run, Meal, Post
- GPS live run tracker (map, route, speed, pace, distance, step count, cadence, activity type)
- Firestore post creation for all activity types
- Provider invalidation after save (feed + stats refresh automatically)
- Draft persistence across navigation (CreateFlowController)
- Animated shared widgets: StepperField, ShareToFeedToggle, StaggeredFadeIn, BouncyChip
- Sensor permissions: location (incl. background), step counter, accelerometer, foreground service
- Demo mode toggle (BackendMode.demo → skips Firebase, returns hardcoded data — currently set to `firebase`)

### In Progress / Stubbed
- **Explore screen** — scaffold only, no backend search query
- **Profile media grid** — placeholder brand images, no real post grid query
- **Achievements screen** — referenced in nav but content not seen in this audit
- **Meal photo analysis** — camera UI complete, AI backend not wired (shows "not connected" state)
- **Music/Podcast streaming** — connect-service prompt only, no actual Spotify/Apple Music SDK integration
- **Like / comment actions** — counts display on PostCard but tap handlers not wired
- **Bookmark action** — icon present, no persistence

### Pending (infrastructure)
- `firestore.rules` deployment to live `fitsocialv2` project
- `flutterfire configure` run by each developer (generates local `lib/firebase_options.dart`)
- iOS target not created (Android-only project currently)
- Google Maps API key (`MAPS_API_KEY`) not committed — injected via `local.properties` or CI secret
- Firebase Storage not yet used (imported but no upload logic implemented)
- Background run tracking across app lifecycle (requires notification channel + service restart on kill)

---

## 15. Dependency Summary

```
firebase_analytics     ^11.3.3   — event tracking
firebase_auth          ^5.3.1    — email/password + OAuth
firebase_core          ^3.6.0    — Firebase initialization
firebase_storage       ^12.3.3   — declared, not yet used
cloud_firestore        ^5.4.4    — primary data store
flutter_riverpod       ^2.5.1    — state management
geolocator             ^14.0.2   — GPS positioning + foreground service
go_router              ^14.2.0   — declarative navigation
google_maps_flutter    ^2.17.0   — route map display
google_sign_in         ^6.2.1    — Google OAuth
pedometer              ^4.0.2    — hardware step counter
sensors_plus           ^6.1.1    — accelerometer, gyroscope, barometer
cupertino_icons        ^1.0.8    — iOS-style icon set
```
