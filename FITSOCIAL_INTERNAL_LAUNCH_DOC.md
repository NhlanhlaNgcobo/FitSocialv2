# ▸ FitSocial — Internal Launch Document
### Train. Fuel. Share. Grow.
**Classification:** Internal — Team Only  
**Version:** 1.0  
**Date:** July 2026  
**Status:** Pre-Launch

---

> This document is the single source of truth for how FitSocial works — technically, commercially, and from the user's perspective. Every team member across engineering, design, marketing, and business should read this before launch.

---

## Table of Contents

1. [What FitSocial Is](#1-what-fitsocial-is)
2. [How the App Works — The Big Picture](#2-how-the-app-works--the-big-picture)
3. [Frontend — Every Screen Explained](#3-frontend--every-screen-explained)
4. [Backend — How Everything Connects](#4-backend--how-everything-connects)
5. [The User Journey](#5-the-user-journey)
6. [Onboarding Flow](#6-onboarding-flow)
7. [Data, Privacy & Security](#7-data-privacy--security)
8. [Revenue Model](#8-revenue-model)
9. [100-User Revenue Projections](#9-100-user-revenue-projections)
10. [Path to Scale — 1K, 10K, 100K Users](#10-path-to-scale)
11. [Pre-Launch Checklist](#11-pre-launch-checklist)

---

## 1. What FitSocial Is

FitSocial is a **fitness social media platform** built for people who want to hold themselves accountable in public. It combines the activity tracking depth of Strava with the social engagement of Instagram — but specifically designed for the African and emerging-market fitness community where existing apps either don't exist, don't feel local, or are too expensive.

### Core value proposition

| Competitor gap | FitSocial solution |
|---|---|
| Strava is runners-only | We cover workouts, runs, meals, and lifestyle |
| MyFitnessPal has no social layer | Community feed is central to the experience |
| Instagram is passive — no fitness data | Every post carries real metrics (pace, reps, calories) |
| Most apps aren't built for African cities | South African-first, built for global scale |

### Tagline
> **Train. Fuel. Share. Grow.**

### Platforms
Android (primary). iOS expansion post-launch.

---

## 2. How the App Works — The Big Picture

FitSocial is a **Flutter mobile application** backed by **Google Firebase**. Here is how all the systems connect:

```
┌──────────────────────────────────────────────────────────────────┐
│                        USER'S PHONE                               │
│                                                                    │
│  ┌──────────────┐   ┌──────────────┐   ┌────────────────────┐   │
│  │  Flutter UI   │   │  Riverpod    │   │  Device Sensors    │   │
│  │  (Dart/Material│  │  State Mgmt  │   │  GPS · Pedometer   │   │
│  │   Dark Theme)  │◄─┤  Providers   │   │  Accelerometer     │   │
│  └──────┬────────┘   └──────┬───────┘   └────────┬───────────┘   │
│         │                   │                     │               │
└─────────┼───────────────────┼─────────────────────┼───────────────┘
          │                   │                     │
          ▼                   ▼                     │
┌─────────────────────────────────────────────────┐ │
│              FIREBASE (Google Cloud)             │ │
│                                                  │ │
│  ┌──────────────┐  ┌──────────────┐             │ │
│  │ Firebase Auth│  │  Firestore   │◄────────────┘ │
│  │              │  │  (database)  │  Real GPS      │
│  │ Email/Pass   │  │              │  data written  │
│  │ Google OAuth │  │  posts/      │  to cloud      │
│  │ Apple Sign-In│  │  users/      │               │
│  └──────────────┘  │  progress/   │               │
│                    │  comments/   │               │
│  ┌──────────────┐  │  follows/    │               │
│  │ Cloud Storage│  │  likes/      │               │
│  │              │  │  workouts/   │               │
│  │ Profile pics │  │  runs/       │               │
│  │ Meal photos  │  └──────────────┘               │
│  │ Post images  │                                  │
│  └──────────────┘  ┌──────────────┐               │
│                    │   Cloud      │               │
│  ┌──────────────┐  │  Functions   │               │
│  │    FCM       │  │              │               │
│  │ Push Notifs  │  │ Meal AI      │               │
│  │              │  │ Like counter │               │
│  └──────────────┘  │ Notif sender │               │
│                    │ Feed fanout  │               │
│                    └──────────────┘               │
└──────────────────────────────────────────────────┘
```

### Technology choices and why

| Technology | Role | Why we chose it |
|---|---|---|
| **Flutter** | Mobile UI | Single codebase for Android + iOS; fast rendering; rich animation support |
| **Firebase Auth** | User accounts | Handles email, Google, Apple sign-in with zero custom auth server |
| **Firestore** | Database | Real-time sync, offline-capable, scales to millions of documents automatically |
| **Firebase Storage** | File hosting | Profile photos, meal images, post media stored and CDN-delivered |
| **Cloud Functions** | Server-side logic | AI meal analysis, notification triggers, counter updates — no server to manage |
| **Firebase Analytics** | Usage tracking | Free, built-in, works offline |
| **Riverpod** | App state management | Reactive, testable, handles async data (feed loading, auth state) cleanly |
| **Google Maps** | Run route display | Reliable, familiar, works across Africa with good map data |
| **Geolocator** | GPS tracking | Hardware GPS with background tracking; respects OS battery management |
| **Pedometer** | Step counting | Uses the phone's dedicated low-power step sensor chip — not battery-intensive |
| **Sensors Plus** | Motion data | Accelerometer + gyroscope for activity type detection (walking vs jogging vs running) |
| **Image Picker** | Camera/gallery | Take meal photos or pick from library for AI analysis |
| **Cloud Functions (callable)** | AI meal analysis | Sends photo to Vision AI, returns nutritional data |

---

## 3. Frontend — Every Screen Explained

### Navigation Structure

The app uses a **5-tab bottom navigation shell** once authenticated. All logging flows push on top of this shell.

```
SHELL (authenticated):
 ├── 🏠 Home          — social feed, stories, weekly stats
 ├── 🔍 Explore       — search, trending, discovery
 ├── ➕ Create        — log a workout / run / meal / post
 ├── 📈 Activity+     — your progress charts, music, podcasts
 └── 👤 Profile       — your stats, posts, achievements
```

---

### Screen-by-screen breakdown

#### Auth Screens (before login)

**Welcome Screen**  
Full-screen athlete photo with animated orange light sweep. First thing every new user sees. Two paths: "Get Started" (sign up) or "Already have an account? Log in."

**Login / Sign Up Screen**  
Same screen, two modes. Toggle via the URL parameter `?mode=signup`. Shows:
- "Use Email" button → reveals email + password fields (pre-filled in dev with `neo@fitsocial.app` / `password123`)
- "Continue with Google" button → native Google OAuth sheet
- Error messages appear at the bottom when login fails (permission-denied, wrong password etc.)

**Profile Setup Screen**  
First screen after a brand-new account is created. Collects Display Name, Handle (e.g. `@neo.fits`), Bio, and Location. Required before accessing the main app. Saved to Firestore under `users/{uid}`.

**Edit Profile Screen**  
Same form as Profile Setup, accessible from the Profile tab at any time.

---

#### Home Screen

What the user sees every time they open the app:

1. **Stories row** — horizontal scroll of avatar rings showing who has posted recently. Your own story is always first with a + icon.
2. **Weekly summary strip** — "4 workouts · 11 meals" pulled from the user's Firestore stats.
3. **Music spotlight card** — links to Activity tab's music section. Changes to "Open your playlists" once connected.
4. **Feed posts** — scrollable vertical list of `PostCard` widgets. Each card shows:
   - User avatar (initials) + name + activity type + timestamp
   - Gradient image panel (burn/sunset/graphite theme based on activity)
   - 3 metric labels displayed large (e.g. "10.04 km · 52:18 · 5:12 /km")
   - Like count, comment count, bookmark icon
   - Caption text
   - "View all comments" link

---

#### Create Screen

Acts as the **command centre** for all logging. Six actions:

| Action | Route | What it does |
|---|---|---|
| Log a Workout | `/log-workout` | Form-based session with dynamic exercise list |
| Log a Run | `/log-run` | Live GPS tracker with map, or tap → `/log-run-manual` for manual entry |
| Log a Meal | `/meal-camera` | Camera viewfinder (AI backend pending) or "Enter Manually" |
| Share a Post | `/compose-post` | Caption + photo compose screen |
| Workout Music | `/activity` | Opens music tab directly |
| Add Photo | `/meal-camera` | Same as Log a Meal |

If a draft was started and not finished, a **draft resume card** appears at the top — user can continue from where they left off or clear it.

---

#### Workout Log Screen

A full-featured structured workout logger:

- **Title** — free text ("Leg Day", "Pull Day", etc.)
- **Duration + Calories** — free text, shown side-by-side
- **Exercise list** — dynamic, animated. Tap "+ Add Exercise" to add a row. Each row has:
  - Exercise name text field
  - Sets stepper (tap +/− to increment; number animates in/out)
  - Reps stepper (same pattern)
  - × remove button
- **Notes** — "How did the session feel?"
- **Share to Feed toggle** — animated card (globe icon when on, lock when off, border pulses orange)
- **Save button** — text changes to "Save & Share" when toggle is on

On save: posts are written to Firestore. Feed refreshes automatically.

---

#### Run Log Screen (GPS Live Tracker)

The most technically complex screen:

**Map view (top 60% of screen)**
- Google Maps rendering a polyline in real-time as the user runs
- Orange route line drawn as GPS positions arrive
- Green start marker, current position marker
- Status pills floating over the map:
  - Activity type badge: Stationary / Walking / Jogging / Running (live, updated every second from GPS speed + accelerometer + pedometer)
  - Live speed pill: "8.4 km/h"

**Stats panel (bottom 40%)**
- Row 1: Elapsed time · Distance (km)
- Row 2: Live Speed · Average Pace (min/km)
- Row 3: Steps (from hardware pedometer) · Cadence (steps/min)

**Controls**
- Start / Pause / Resume run
- Finish run → saves to Firestore, creates a post if "Share to Feed" is on
- Enter Manually icon in AppBar → navigates to Manual Run Entry

**Sensor pipeline during a run:**
```
GPS position stream (every 5m of movement)
  → distance accumulation
  → speed calculation (position.speed × 3.6 = km/h)
  → pace calculation (elapsed ÷ distance)
  → route polyline update
  → activity type classification

Pedometer step count stream (hardware sensor)
  → delta from run start = steps this run
  → cadence = steps ÷ elapsed minutes

Accelerometer stream (50Hz, EMA smoothed)
  → net motion magnitude
  → helps classify "Stationary" when GPS is still acquiring
```

---

#### Manual Run Entry Screen

For logging a run you already did:

- Distance input field (big, centred number) with quick-add chip buttons: +0.1 / +0.5 / +1 / +5 km (each bounces on tap)
- Time entry: three steppers — Hours / Minutes / Seconds
- Estimated pace card (fades in once both distance and time are non-zero)
- Share to Feed toggle
- Save button

---

#### Meal Log (Camera → Review)

**Camera Screen** — viewfinder with camera corners overlay. Capture button sends photo to Firebase Storage → triggers AI Cloud Function → returns nutritional data (protein, carbs, fat, calories, name). AI backend placeholder currently showing "Photo analysis not connected." Manual entry button always available.

**Review Screen** — pre-populated from either AI analysis or manual entry:
- Meal Name
- Calories (kcal)
- Protein (g) / Carbs (g) / Fat (g) — three-column row
- Notes
- Share to Feed toggle

---

#### Activity Screen

Three sections navigated by tabs:

**Progress tab**
- Progress metric cards (Weekly Volume, Average Pace, Calories Burned, Active Minutes)
- Each card shows: label, current value, delta (e.g. "+8.2%"), 7-bar sparkline chart
- Data pulled from `progress` Firestore collection

**Music tab**
- Connect Spotify or Apple Music
- Browse curated workout playlists by type (Strength, Cardio, HIIT, Run, Yoga)
- Podcast recommendations by category (Mindset, Discipline, Recovery, Business)

**Podcasts tab**
- Same podcast recommendations with more detail

---

#### Profile Screen

- Your avatar (initials or photo) + follower/following/posts counts
- Bio, handle, location
- Edit Profile button + Sign Out button
- Four content tabs: All posts / Workouts / Runs / Meals — each renders a 3-column photo grid

#### Achievements Screen

- Level card with XP progress bar (e.g. "Level 10 — 720/1000 XP")
- Recent badges (7 Day Streak, First 5K, Meal Logger)
- Goal progress rows with completion status

---

## 4. Backend — How Everything Connects

### Firestore Database Structure

All app data lives in Firestore. Here is the full schema:

```
firestore (fitsocialv2)
│
├── users/
│   └── {uid}/
│       ├── displayName: "Naledi Khumalo"
│       ├── handle: "@naledi.trains"
│       ├── bio: "Marathon in training"
│       ├── location: "Cape Town, ZA"
│       ├── email: "naledi@example.com"
│       ├── postsCount: 14
│       ├── followersCount: 1842
│       ├── followingCount: 312
│       ├── workoutsCount: 41
│       ├── mealsCount: 58
│       ├── fcmTokens: ["device-token-abc"]
│       └── updatedAt: Timestamp
│
├── posts/
│   └── {postId}/
│       ├── authorId: "uid-xyz"
│       ├── authorName: "Naledi Khumalo"
│       ├── activity: "Run"
│       ├── caption: "Easy 10K this morning"
│       ├── metricLabels: ["10.04 km", "52:18", "5:12 /km"]
│       ├── imageUrl: "https://storage.../posts/postId/image.jpg"
│       ├── likesCount: 134
│       ├── commentsCount: 12
│       ├── themeKey: "sunset"    ← drives gradient colour
│       ├── likedBy: ["uid-abc", "uid-def"]
│       └── createdAt: Timestamp
│
├── comments/
│   └── {postId}/
│       └── items/
│           └── {commentId}/
│               ├── authorId: "uid-abc"
│               ├── authorName: "Sipho Dlamini"
│               ├── text: "Incredible pace 🔥"
│               └── createdAt: Timestamp
│
├── likes/
│   └── {postId}/
│       └── users/
│           └── {uid}/
│               └── createdAt: Timestamp
│
├── follows/
│   └── {uid}/
│       └── following/
│           └── {targetUid}/
│               └── createdAt: Timestamp
│
├── notifications/
│   └── {uid}/
│       └── items/
│           └── {notifId}/
│               ├── type: "like" | "comment" | "follow"
│               ├── fromUid: "uid-abc"
│               ├── fromName: "Sipho Dlamini"
│               ├── postId: "post-xyz"   ← only for like/comment
│               ├── read: false
│               └── createdAt: Timestamp
│
├── workouts/
│   └── {uid}/
│       └── sessions/
│           └── {sessionId}/
│               ├── title: "Leg Day"
│               ├── duration: "62 min"
│               ├── calories: "540 kcal"
│               ├── exercises: [{name, sets, reps}]
│               ├── notes: "Knees felt good"
│               └── createdAt: Timestamp
│
├── runs/
│   └── {uid}/
│       └── sessions/
│           └── {sessionId}/
│               ├── distanceKm: 10.04
│               ├── elapsed: "52:18"
│               ├── paceLabel: "5:12 /km"
│               ├── steps: 9842
│               ├── cadence: 162
│               └── createdAt: Timestamp
│
└── progress/
    └── {metricId}/
        ├── label: "Weekly Volume"
        ├── value: "18,420 kg"
        ├── delta: "+8.2%"
        └── chartBars: [4200, 4600, 3900, 5100, 4800, 5300, 5600]
```

---

### Firebase Security Rules

Who can read and write what:

| Collection | Read | Write |
|---|---|---|
| `users/{uid}` | Own doc only | Own doc only |
| `posts` | Any signed-in user | Only own posts (authorId == uid) |
| `comments/{postId}/items` | Any signed-in user | Any signed-in user |
| `likes/{postId}/users/{uid}` | Any signed-in user | Own like only |
| `follows/{uid}/following` | Any signed-in user | Own follow only |
| `notifications/{uid}` | Own notifications only | Cloud Functions only |
| `workouts/{uid}`, `runs/{uid}` | Own data only | Own data only |
| `progress` | Any signed-in user | Cloud Functions only |

---

### Cloud Functions Pipeline

These are the server-side operations that run in Google Cloud when triggered by user actions:

```
User taps LIKE on a post
  → writes like document to likes/{postId}/users/{uid}
  → Cloud Function: onPostLiked
      → increments posts/{postId}.likesCount by 1
      → writes notification to notifications/{authorId}/items/
      → sends FCM push to post author's device

User posts a COMMENT
  → writes to comments/{postId}/items/
  → Cloud Function: onCommentCreated
      → increments posts/{postId}.commentsCount by 1
      → notifies post author

User FOLLOWS another user
  → writes to follows/{uid}/following/{targetUid}
  → Cloud Function: onFollow
      → increments target user's followersCount
      → increments current user's followingCount
      → notifies the followed user

User photographs a MEAL
  → image uploaded to Firebase Storage: meals/{uid}/{timestamp}.jpg
  → Cloud Function: analyzeMealPhoto (HTTP callable)
      → receives Storage path
      → sends image to Google Vision AI / OpenAI Vision API
      → returns {name, calories, protein, carbs, fat}
      → pre-populates MealReviewScreen
      → optionally writes to meals/{uid}/sessions/

User logs a WORKOUT
  → app writes WorkoutLogDraft to Firestore
  → Cloud Function: onWorkoutLogged
      → increments users/{uid}.workoutsCount
      → calculates XP gain
      → checks badge thresholds (10 workouts = "Consistent" badge)
      → updates users/{uid}/achievements
```

---

### Authentication Flow

```
App cold-start
  ↓
bootstrapApp() — Firebase.initializeApp()
  ↓
Check FirebaseAuth.currentUser
  ↓
  ├── Not null (returning user) → skip Welcome → go to Home
  └── Null (new session) → show Welcome screen
         ↓
         User taps "Get Started" or "Log In"
         ↓
         LoginScreen opens
         ↓
         User enters email + password (or taps Google)
         ↓
         FirebaseAuth.signInWithEmailAndPassword() / signInWithCredential()
         ↓
         AppSession.signInWithEmail() is called
         ↓
         AuthStage transitions: unauthenticated → profileSetup
         ↓
         Firestore: read users/{uid} — does profile exist?
           ├── Yes → AuthStage → authenticated → go to Home
           └── No  → AuthStage stays profileSetup → go to /profile-setup
                     User fills Name, Handle, Bio, Location
                     → saved to Firestore users/{uid}
                     → AuthStage → authenticated → go to Home
```

---

## 5. The User Journey

### A day in the life of a FitSocial user

**7:00 AM — Morning workout**
Neo opens FitSocial. The home feed shows Naledi's 21K run from last night (356 likes). He scrolls past Sipho's deadlift PR and Priya's meal prep photo.

He taps ➕ Create → "Log a Workout." Types "Push Day" as the title. Adds exercises one by one — Bench Press (4 sets × 8 reps), Overhead Press (3 × 10), Tricep Pushdown (3 × 12). Writes "Shoulders felt tight, took it easy" in Notes. Toggles "Share to Feed" on. Taps "Save Workout & Share." His post appears in the feed with an orange burn-theme gradient and metrics "62 min · 380 kcal · 3 moves."

**12:30 PM — Lunch**
Neo photographs his chicken wrap on the Meal Log screen. The AI analyses it and returns: Chicken Wrap · 540 kcal · 38g protein · 42g carbs · 14g fat. He reviews, edits the carbs to 45g, and shares. 

**6:00 PM — Evening run**
He opens the Run Tracker. GPS locks in 8 seconds. He taps Start Run. The map shows his route building in real-time (orange polyline). His status pill reads "Jogging." After 35 minutes his pace drops and it reads "Running." He finishes — 5.2 km, 4:58/min pace, 4,820 steps, 168 spm cadence. Taps Finish → "Run saved and shared."

**9:00 PM — Browsing**
He checks notifications — Naledi and Sipho liked his push day post. He goes to the Explore tab, discovers a new user (@amara.runs), follows her. Browses her profile — all 5Ks and track sessions.

---

### Key user motivations

| Motivation | How FitSocial addresses it |
|---|---|
| Accountability | Every workout/run/meal is a public post with real metrics — not just a selfie |
| Validation | Likes, comments, follower counts reward consistency |
| Progress | Activity screen shows weekly volume, pace trends, XP gains |
| Community | Stories, feed, following — fitness friends in one place |
| Gamification | Achievements, badges, streaks, leaderboard |
| Music | Workout playlists and podcast recommendations without leaving the app |

---

## 6. Onboarding Flow

Onboarding is the first impression. Every screen here matters for retention.

### Step-by-step

```
Step 1 — WELCOME (Welcome Screen)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Full-screen athlete photo with animated beam
• Tagline: "Train. Fuel. Share. Grow."
• Call-to-action: "Get Started" (primary, orange button)
• Secondary: "Already have an account? Log in"
• No friction — nothing to fill in yet

Step 2 — ACCOUNT CREATION (Login Screen)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Two paths: email/password or Google
• Email form slides in smoothly (no page change)
• Validation is inline
• Error states shown bottom of screen (not modals)

Step 3 — PROFILE SETUP (Profile Setup Screen)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Display Name (required)
• Handle — @username (required)
• Bio (optional) — "What drives you?"
• Location (optional)
• No skip option — this ensures every account has at least a name

Step 4 — HOME FEED (first time)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• User lands on Home with a populated feed (real posts from the community)
• No empty state on first launch — feed shows global posts not just following
• Stories show suggested users to follow

Step 5 — FIRST LOG (encouraged via Create tab)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Create tab (➕) is visually prominent in the nav bar
• First visit shows a tooltip/prompt: "Log your first activity"
• Goal: user logs within first 24 hours
```

### Onboarding KPIs to track

| Metric | Target |
|---|---|
| Account creation → Profile setup completion | > 85% |
| Profile setup → First session in feed | > 90% |
| Day 1 activity log rate | > 40% |
| Day 7 return rate | > 35% |
| Day 30 retention | > 20% |

---

## 7. Data, Privacy & Security

### What data we collect

| Data type | Where stored | Who can see it |
|---|---|---|
| Name, handle, bio, location | Firestore `users/{uid}` | Public (other users) |
| Email address | Firebase Auth + Firestore | Only the user + admin |
| GPS route data | Firestore `runs/{uid}/sessions` | Only the user |
| Meal photos | Firebase Storage | Only the user (pre-share) |
| Posts | Firestore `posts/` | All authenticated users |
| Step count, cadence | Firestore `runs/{uid}/sessions` | Only the user |
| Device FCM token | Firestore `users/{uid}.fcmTokens` | Only Cloud Functions |

### What we do NOT collect
- Payment card details (handled by payment processor, never touches our servers)
- Exact home/work address (we collect city-level location for profile display only)
- Contacts or phone book
- Biometric data (fingerprint, face — only used for device unlock, never sent to us)

### Security measures
- All data in transit encrypted via TLS
- Firestore rules enforce per-user data isolation (no user can read another's private data)
- Firebase Auth handles credential storage — we never store passwords
- Firebase App Check prevents non-app clients from hitting our API
- Cloud Functions run in a sandboxed Google Cloud environment

### POPIA / GDPR compliance considerations
- User can delete their account and all associated data
- Data export on request
- Consent is collected at sign-up for analytics tracking
- Location data is only used in-session for GPS tracking — not stored continuously

---

## 8. Revenue Model

FitSocial will monetise through a **freemium subscription model** with a free core and a premium tier that unlocks high-value features.

### Tier Structure

#### Free — FitSocial Core
**Price:** R0 / $0 forever

Everything a casual user needs:
- Community feed and social engagement (likes, comments, follows)
- Manual workout logging (sets, reps, notes)
- GPS run tracking with route map
- Manual run entry
- Meal logging (manual nutrients entry)
- 3 AI meal photo analyses per month
- Basic progress charts (7-day view)
- Stories and community events
- 1 active workout plan

---

#### Pro — FitSocial Pro
**Price:** R99/month or R799/year (~$5/month or $40/year)

For the dedicated athlete who wants more:
- **Unlimited AI meal photo analysis** — scan every meal, not just 3/month
- **Advanced analytics** — monthly and yearly trend views, training load score, fitness score
- **GPS route export** — share or download GPX files for Garmin/Strava import
- **Full run history** — step cadence trends, elevation charts
- **Custom workout templates** — save and reuse training splits
- **Priority in Explore feed** — higher visibility for their posts
- **Exclusive Pro badge** on profile
- **Leaderboards** — weekly/monthly rankings by distance, volume, streak

---

#### Coach — FitSocial Coach
**Price:** R249/month or R1,999/year (~$13/month or $104/year)

For personal trainers, coaches, and gym owners:
- Everything in Pro
- **Client dashboard** — monitor up to 20 clients' activity, compliance, and progress
- **Workout plan assignment** — push workout plans directly to clients' apps
- **Client messaging** — in-app chat with each client
- **Coach badge** on profile
- **Analytics per client** — weekly volume, rest days, missed sessions

---

### Additional revenue streams (post-launch)

| Stream | Mechanism | Timeline |
|---|---|---|
| **Brand partnerships** | Sponsored workout playlists, meal plans from nutrition brands, branded fitness challenges | Month 6+ |
| **Marketplace** | Sell custom workout plans, nutrition guides between coaches and users | Month 9+ |
| **Corporate wellness** | Bulk team licenses for companies running employee fitness programmes | Month 12+ |
| **In-app challenges** | Paid entry challenges with prizes sponsored by brands (e.g. "Run 100km in November") | Month 6+ |
| **Premium content** | Expert-led masterclasses on nutrition, recovery, training methodology | Month 12+ |

---

## 9. 100-User Revenue Projections

The following projections are based on industry benchmarks for fitness apps with strong social components. Assumptions are conservative and based on the South African market.

### Assumptions

| Variable | Value | Source / Rationale |
|---|---|---|
| Total registered users | 100 | Target cohort |
| Monthly Active Users (MAU) | 65 (65%) | Industry avg for fitness apps: 60–70% MAU rate |
| Free tier users | 84 | 84% of registrations remain free (industry standard) |
| Pro tier conversion | 12% | 12 users — conservative; fitness apps average 8–15% |
| Coach tier conversion | 4% | 4 users — personal trainers early adopters |

### Monthly Revenue Breakdown

| Tier | Users | Price (ZAR/month) | Monthly Revenue |
|---|---|---|---|
| Free | 84 | R0 | R0 |
| Pro (monthly billing) | 8 | R99 | R792 |
| Pro (annual, amortised) | 4 | R66.58 (R799 ÷ 12) | R266 |
| Coach (monthly billing) | 2 | R249 | R498 |
| Coach (annual, amortised) | 2 | R166.58 (R1,999 ÷ 12) | R333 |
| **TOTAL** | | | **R1,889/month** |

**→ Monthly recurring revenue (MRR): ~R1,889**  
**→ Annual recurring revenue (ARR): ~R22,668**

---

### Annual Revenue Scenarios

| Scenario | Assumption | ARR |
|---|---|---|
| 🔴 Conservative | 8% Pro conversion, 2% Coach | R14,400 |
| 🟡 Base case | 12% Pro, 4% Coach (above) | R22,668 |
| 🟢 Optimistic | 20% Pro, 8% Coach | R42,000 |

---

### Revenue per user benchmarks

| Metric | Value |
|---|---|
| Average Revenue Per User (ARPU) | R18.89/month |
| Average Revenue Per Paying User (ARPPU) | R117.43/month |
| Lifetime Value (LTV, 18-month avg retention) | R340 per user |
| Customer Acquisition Cost target (CAC) | < R80 per user |
| LTV:CAC ratio | 4.25:1 (healthy — target > 3:1) |

---

### What R1,889/month means

At 100 users, FitSocial is pre-revenue-positive — this is **product-market-fit validation money**, not a salary. Here is what the early revenue funds:

| Expense | Monthly Cost |
|---|---|
| Firebase (Firestore + Auth + Storage + Functions) | ~R200 |
| Google Maps API (per-request billing) | ~R100 |
| AI meal analysis (Vision API per-call) | ~R150 |
| Domain, SSL, misc infrastructure | ~R100 |
| **Total infrastructure** | **~R550/month** |

**Net from 100 users: ~R1,339/month toward development costs.**

At this stage, the primary goal is proving the model — not profitability. With 1,000 users, the unit economics become substantially more favourable (infrastructure costs grow slowly, revenue scales linearly).

---

### Path to 1,000 users revenue

Extrapolating the same conversion rates to 1,000 users:

| Tier | Users | Monthly Revenue |
|---|---|---|
| Pro (monthly + annual blend) | 120 | R11,800 |
| Coach | 40 | R10,200 |
| **Total MRR** | | **R22,000/month (~$1,200/month)** |

At 1,000 MAU, FitSocial becomes **cash-flow positive** and can sustain development costs without external funding.

---

## 10. Path to Scale

### 1,000 Users — Infrastructure priorities
- Deploy Firestore composite indexes for filtered feed queries
- Enable personalized (following-based) feed
- Launch AI meal analysis (connect Cloud Function to Vision API)
- Ship comments and likes (P1 features)
- Run first paid social campaign targeting South African fitness community

### 10,000 Users — Platform maturity
- Full social graph (follows, followers, explore page)
- Coach tier fully live with client dashboard
- First brand partnership (supplement brand, gym chain)
- iOS target launched
- Referral programme ("Invite a friend, get 1 month Pro free")

### 100,000 Users — Scale
- Regional expansion (Nigeria, Kenya, UK diaspora)
- Series A funding conversation possible
- Explore marketplace for workout plans
- Corporate wellness pilot with 2–3 SA companies
- Full native push notification campaigns (re-engagement, streak maintenance)

---

## 11. Pre-Launch Checklist

### P0 — Must complete before any user can use the app

- [ ] **Deploy Firestore security rules** — currently all reads/writes fail with permission-denied on the live project
  ```sh
  npx firebase-tools deploy --only firestore:rules --project fitsocialv2
  ```
- [ ] **Enable Email/Password auth** in Firebase Console → Authentication → Sign-in methods
- [ ] **Enable Google Sign-In** in Firebase Console — add SHA-1 fingerprint of release keystore
- [ ] **Set Google Maps API key** — restrict to app package + cert fingerprint; add to CI secret
- [ ] **`flutterfire configure`** — every developer must run this to generate local `firebase_options.dart`
- [ ] **Release build signing** — add release keystore to `android/app/build.gradle.kts`; do not share keystore password in source control

### P1 — Before soft launch (first 100 users)

- [ ] Post interactions: wire like, comment, bookmark tap handlers
- [ ] Comments screen built and routed (`/comments/:postId`)
- [ ] Auth cold-start: skip Welcome if `currentUser` exists (users get logged out on restart currently)
- [ ] Password reset flow on Login screen
- [ ] Camera + Storage upload wired (`image_picker` package already added)
- [ ] Firebase Cloud Functions scaffold (`functions/` directory) — start with like counter + AI meal

### P2 — Before public launch

- [ ] Following-based feed (personal, not global)
- [ ] Firestore composite indexes deployed
- [ ] Push notifications (FCM) — like, comment, follow triggers
- [ ] Profile media grid with real posts (not placeholder images)
- [ ] Explore screen with user search
- [ ] Achievements backend (real XP from Firestore, not hardcoded)
- [ ] Notification screen (bell icon currently routes to wrong screen)
- [ ] Background run tracking foreground service notification
- [ ] Full App Store listing prepared (screenshots, description, privacy policy URL)
- [ ] Privacy policy + Terms of Service pages linked from app

### P3 — Growth features (Month 2–3)

- [ ] Social graph (Follow / Unfollow / Followers/Following lists)
- [ ] Pro tier payment integration (App Store In-App Purchase / PayFast/Stripe)
- [ ] Coach tier beta with 3–5 real coaches
- [ ] iOS target created and submitted
- [ ] Email verification post-sign-up
- [ ] Account deletion flow (POPIA compliance)

---

## Document Version History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-07-01 | Initial internal document — covers current build state through Phase 4 |

---

*For technical architecture detail, see `CODEBASE_ANALYSIS.md`*  
*For co-editor onboarding and file changes, see `HANDOFF.md`*

---

**FitSocial — Built in South Africa. Built for the world.**  
*Train. Fuel. Share. Grow.*
