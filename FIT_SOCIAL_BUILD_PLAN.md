# FitSocial Build Plan

## Source Materials

- Product document: `FitSocial_Level2_MVP_Plan.docx`
- UI reference board: `ChatGPT Image Apr 23, 2026, 11_57_53 AM.png`
- Hero/mockup reference: `ChatGPT Image Apr 23, 2026, 12_07_23 PM.png`

## Product Direction

FitSocial is a dark-mode, social-first fitness app for the South African market. The MVP should focus on one repeatable habit loop:

1. Track a workout, run, or meal.
2. Review the result.
3. Share it to the feed.
4. Receive engagement through likes, comments, streaks, badges, and progress stats.

The visual identity should stay close to the references: black background, charcoal cards, white typography, deep orange accents, rounded iPhone-style surfaces, bold fitness imagery, and a bottom navigation model with a central create action.

## MVP Scope

### Must Have

- Onboarding splash and login/signup flow
- Home feed with stories, posts, engagement actions, and bottom navigation
- Create action sheet with quick choices:
  - Log a workout
  - Log a run
  - Log a meal
  - Share a post
  - Add photo
- Meal camera/upload screen
- Meal review screen with editable nutrition values
- Workout/activity logging screen
- Profile screen with posts, followers, bio, and media grid
- Progress screen with workout, calorie, and active minute stats
- Achievements screen with level, XP, badges, and checklist-style goals

### Should Have

- Firebase Auth with email, Google, and Apple sign-in
- Firestore records for users, posts, workouts, runs, meals, comments, likes, and achievements
- Firebase Storage for uploaded meal/post/profile images
- Cloud Function endpoint for meal image analysis
- Basic privacy controls for whether a log is shared to feed
- Seed/demo data for investor demos

### Later

- Paid subscriptions and in-app purchases
- Student pricing verification
- Offline mode
- Challenges and group chats
- Wearable import
- Push notifications
- Advanced analytics dashboard

## Screen Inventory

### 1. Splash / Welcome

Purpose: First impression and brand positioning.

Key UI:

- Full-screen athlete image
- Large `FitSocial` logo
- Tagline: `Train. Fuel. Share. Grow.`
- Four small value icons: track workouts, log meals, share progress, build community
- Primary `Get Started` button
- Secondary login link

Build notes:

- This can be implemented as the first onboarding slide or a standalone `WelcomeScreen`.
- Use high-contrast orange CTA and minimal body text.

### 2. Account Creation / Login

Purpose: Fast account entry.

Key UI:

- Background fitness image with dark overlay
- Email, Google, and Apple sign-in options
- Login link for existing users

Build notes:

- Start with Firebase Auth.
- Email flow can be implemented before Google/Apple if credentials setup is pending.

### 3. Home Feed

Purpose: Main social hub.

Key UI:

- Brand header
- Notification and media/message icons
- Horizontal stories row
- Feed cards with workout/run/media summary
- Like, comment, bookmark/share controls
- Bottom nav: Home, Explore, Create, Activity, Profile

Build notes:

- The document says bottom nav should include Feed, Workouts, Runs, Meals, Profile, but the images show a stronger social app pattern. Recommend using the image pattern and exposing workout/run/meal logging through the central create button.

### 4. Create Action Sheet

Purpose: Route users into the main habit loop.

Key UI:

- Modal page titled `What are you up to?`
- Options for workout, run, meal, post, and photo
- Orange line icons and dark list rows

Build notes:

- Implement as a route or bottom sheet.
- This is the central navigation hub for creation actions.

### 5. Meal Camera

Purpose: Camera-first meal capture.

Key UI:

- Large meal preview/camera frame
- Capture button
- Gallery and flash controls
- Instruction text

Build notes:

- MVP can use `image_picker` for camera/gallery.
- Full camera preview can come after core flow is stable.

### 6. Meal Review

Purpose: Confirm AI/manual nutrition data before saving.

Key UI:

- Meal thumbnail
- Change photo action
- Meal name
- Calories
- Protein, carbs, fat fields
- Notes
- Share-to-feed toggle
- Save meal CTA

Build notes:

- Use editable fields even when AI analysis is available because image-based nutrition estimates need user correction.

### 7. Workout / Activity Log

Purpose: Save a workout and optionally share it.

Key UI:

- Workout/run segmented control
- Workout title, time, duration, calories
- Exercise list with sets/reps/weight
- Share-to-feed CTA

Build notes:

- Initial MVP can support manual entries first.
- Run tracking can use manual distance/time before maps or wearable integration.

### 8. Profile

Purpose: Identity, social proof, and personal archive.

Key UI:

- Avatar, username, handle
- Posts/followers/following counts
- Bio and location
- Edit profile button
- Media grid tabs

Build notes:

- Keep profile editing basic for MVP: avatar, display name, bio, location.

### 9. Progress

Purpose: Personal insight and retention.

Key UI:

- Date range tabs: 7D, 30D, 3M, 1Y
- Workouts card with bar chart
- Calories burned card with line chart
- Active minutes card with area chart

Build notes:

- Use local aggregate queries from Firestore records.
- `fl_chart` is a practical Flutter choice for charts.

### 10. Achievements

Purpose: Gamification.

Key UI:

- Level card with XP progress
- Recent badges
- Checklist goals with completion states

Build notes:

- Start with deterministic badges:
  - First workout
  - First meal logged
  - 7 day streak
  - 10 workouts
  - 10K steps placeholder

## Recommended App Architecture

### Frontend

- Flutter
- Riverpod for state management
- go_router for navigation
- Firebase packages:
  - `firebase_core`
  - `firebase_auth`
  - `cloud_firestore`
  - `firebase_storage`
  - `firebase_analytics`
- Image/media:
  - `image_picker`
  - `cached_network_image`
- UI:
  - `lucide_icons` or `flutter_tabler_icons`
  - `fl_chart`

### Backend

- Firebase Auth
- Cloud Firestore
- Firebase Storage
- Cloud Functions
- OpenAI vision endpoint for meal analysis

## Suggested Firestore Model

```text
users/{userId}
  displayName
  handle
  avatarUrl
  bio
  location
  followersCount
  followingCount
  postsCount
  createdAt

posts/{postId}
  authorId
  type: post | workout | run | meal | photo
  caption
  mediaUrl
  workoutId
  runId
  mealId
  likesCount
  commentsCount
  visibility
  createdAt

workouts/{workoutId}
  userId
  title
  durationMinutes
  calories
  exercises[]
  notes
  sharedPostId
  createdAt

runs/{runId}
  userId
  distanceKm
  durationSeconds
  paceSecondsPerKm
  routePreviewUrl
  calories
  notes
  sharedPostId
  createdAt

meals/{mealId}
  userId
  name
  imageUrl
  calories
  proteinGrams
  carbsGrams
  fatGrams
  notes
  aiAnalysis
  sharedPostId
  createdAt

comments/{commentId}
  postId
  authorId
  text
  createdAt

likes/{postId_userId}
  postId
  userId
  createdAt

achievements/{achievementId}
  userId
  type
  title
  progress
  target
  completedAt
```

## Route Map

```text
/
/welcome
/login
/signup
/home
/explore
/create
/activity
/profile/:userId
/profile/:userId/edit
/progress
/achievements
/log/workout
/log/run
/log/meal/camera
/log/meal/review
/post/new
/post/:postId
```

## Build Phases

### Phase 1: Project Foundation

- Create Flutter project structure.
- Add theme tokens for black, charcoal, orange, white, muted gray, success green.
- Configure go_router shell navigation.
- Create reusable components:
  - `AppScaffold`
  - `FitSocialLogo`
  - `PrimaryButton`
  - `DarkCard`
  - `Avatar`
  - `BottomNav`
  - `StatTile`
  - `PostCard`

### Phase 2: Static UI Prototype

- Build all reference screens with mock data.
- Match the screenshot hierarchy closely.
- Validate mobile spacing, text fit, and bottom navigation behavior.

### Phase 3: Authentication And User Profiles

- Configure Firebase.
- Add email authentication first.
- Add profile creation after signup.
- Add profile edit.

### Phase 4: Social Feed

- Implement Firestore post list.
- Add post creation.
- Add likes and comments.
- Add seeded demo content.

### Phase 5: Logging Flows

- Add workout logging.
- Add run logging.
- Add meal upload and review.
- Add share-to-feed behavior for each log type.

### Phase 6: AI Meal Analysis

- Upload meal image to Firebase Storage.
- Call Cloud Function.
- Cloud Function sends image to OpenAI vision model.
- Return structured JSON for meal review.
- Let users edit the results before saving.

### Phase 7: Progress And Achievements

- Aggregate workouts, runs, and meals.
- Build progress charts.
- Add XP and badge calculation.
- Show achievements checklist.

### Phase 8: Investor Demo Polish

- Add loading, empty, and error states.
- Improve transitions and interaction feedback.
- Add demo account and seeded content.
- Prepare screenshots and a short walkthrough script.

## Immediate Next Steps

1. Decide whether the app will be built as a Flutter mobile app now, or if a clickable web/mobile prototype should come first.
2. Create the Flutter project if one does not already exist.
3. Implement theme tokens and core navigation.
4. Build the static UI screens from the screenshots before connecting Firebase.
5. Connect Firebase after the UI shell feels right.

## Open Decisions

- Should the MVP prioritize investor demo polish or production readiness first?
- Should the first version support only email login until Google/Apple credentials are ready?
- Should meal AI be included in the first demo, or mocked behind the same interface until the Firebase Cloud Function is ready?
- Should subscriptions be implemented before beta, or represented as locked premium UI for the investor demo?
- Should the app use the document's five-tab fitness navigation, or the screenshots' social navigation? Recommendation: use the screenshots' social navigation.
