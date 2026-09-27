# FitSocial /brag prompts

One prompt per feature, plus one for the whole app. Paste a prompt as it is
into Claude Code from the repo root. Every prompt points at
`marketing/brag/house-rules.md`, which holds the brand, the rule that screens
must be real, the 30 s beat sheet and the carousel spec. Edit that file once
instead of changing every prompt.

Tips:
- On Opus 5.5, /brag hands off to /brag-slim. For the full pipeline, add
  "use the full brag" to the end of the prompt.
- For pixel-exact screens, first drop real phone screenshots into
  `marketing/screens/<feature>/` (for example `marketing/screens/safety/`).
  The prompts tell /brag to match them when they exist.
- Run one prompt at a time. Each run writes its own `brag-output-<timestamp>/`.

---

## 0. Whole app: launch clip

```
/brag --format vertical --duration 30 --tone app-store

Read marketing/brag/house-rules.md first and follow it strictly.

Make the FitSocial launch clip: a South African fitness social app where you train, log your food, share it and stay safe on the road.
Angle: "Your whole fitness life, one feed." Fast cuts across real screens rebuilt from the Flutter code:
- Hook (0–3s): Home feed (lib/features/main/presentation/home_screen.dart) scrolling with a run post and a meal post.
- Beat 1 Train: Live run with the map (lib/features/tracking/presentation/live_run_screen.dart, live_run_map_screen.dart).
- Beat 2 Fuel: Meal Review with foods and macros (lib/features/main/presentation/meal_review_screen.dart).
- Beat 3 Share: Pulse viewer (lib/features/pulse/presentation/pulse_viewer_screen.dart), then a Challenge board (lib/features/challenges/presentation/challenge_board_screen.dart).
- Beat 4 Safe: hold-to-alert panic button (lib/features/safety/presentation/panic_screen.dart).
- End card: F mark + "Train. Fuel. Share. Grow."

Carousel (7 slides): 01 hook "Your whole fitness life, one feed" over the Home feed · 02 Live run · 03 Meal Review · 04 Pulse · 05 Challenges · 06 Safety · 07 CTA "Join FitSocial".
```

---

## 1. Welcome and onboarding

```
/brag --format vertical --duration 30 --tone polished

Read marketing/brag/house-rules.md first and follow it strictly.

Feature: getting started on FitSocial. Screens to rebuild from code: splash_screen.dart, welcome_screen.dart, login_screen.dart, profile_setup_screen.dart in lib/features/auth/presentation/ (use the welcome hero assets in fitsocial_app/assets/images/ that the welcome screen actually loads).
Angle: "From download to first post in under a minute." Show the splash, then the welcome hero, Google sign-in, profile setup (photo, name, goals), and land on the Home feed.
Hook: the F mark forming on #050505, then the welcome screen sliding up.

Carousel (5 slides): 01 hook "Set up in under a minute" · 02 Welcome · 03 Sign in · 04 Profile setup · 05 CTA "Your feed is waiting".
```

## 2. Feed, posts, reactions and comments

```
/brag --format vertical --duration 30 --tone default

Read marketing/brag/house-rules.md first and follow it strictly.

Feature: the social feed. Rebuild from lib/features/main/presentation/: home_screen.dart, explore_screen.dart, post_compose_screen.dart, post_detail_screen.dart, plus the post card, reactions sheet and threaded comments widgets they use.
Real behaviour to show: posting a run, workout or meal; the reaction picker and reaction counts; comment replies threaded one level deep with "Replying to …"; tagging people on a run or workout.
Angle: "Progress is better together." Hook: a run card lands in the feed and reactions start stacking on it.

Carousel (6 slides): 01 hook · 02 Feed · 03 Compose with tags · 04 Reactions · 05 Threaded replies · 06 CTA.
```

## 3. Pulse (24-hour stories)

```
/brag --format vertical --duration 30 --tone chaotic

Read marketing/brag/house-rules.md first and follow it strictly.

Feature: Pulse. Rebuild from lib/features/pulse/presentation/: pulse_composer_screen.dart, pulse_viewer_screen.dart, share_post_to_pulse_screen.dart, share_music_to_pulse_screen.dart. Check the code for how long a Pulse stays up and say exactly that.
Real behaviour: composing a Pulse, the tap-through viewer with progress bars, sharing a feed post to your Pulse (the author gets told), and sharing the song you're playing to a Pulse.
Angle: "Post the moment, not the whole workout." Hook: the progress bars racing across the top of the viewer.

Carousel (5 slides): 01 hook · 02 Composer · 03 Viewer · 04 Share a post to Pulse · 05 Share your song to Pulse.
```

## 4. Run tracking

```
/brag --format vertical --duration 30 --tone cinematic

Read marketing/brag/house-rules.md first and follow it strictly.

Feature: tracking a run. Rebuild from lib/features/tracking/presentation/: live_run_screen.dart, live_run_map_screen.dart, treadmill_run_screen.dart, health_dashboard_screen.dart, and lib/features/main/presentation/manual_run_entry_screen.dart, run_log_screen.dart.
Real behaviour (see fitsocial_app/RELEASE_NOTES.md 1.0.0 (9)): GPS route on the map with live distance, time and pace; treadmill mode; logging a run by hand; runs from a watch or Samsung Health coming in as drafts on Create; the finished run card saved to Photos or shared as a 1080px image.
Angle: "Every kilometre counts, wherever you ran it." Hook: a route drawing itself along the Durban beachfront with pace ticking.

Carousel (6 slides): 01 hook · 02 Live run and map · 03 Treadmill · 04 Watch and Samsung Health imports · 05 Run card saved to Photos · 06 CTA.
```

## 5. Live activity sharing

```
/brag --format vertical --duration 30 --tone polished

Read marketing/brag/house-rules.md first and follow it strictly.

Feature: letting people follow your run live. Rebuild from lib/features/tracking/presentation/live_activity_viewer_screen.dart and the part of live_run_screen.dart that starts sharing. Read the code for who can watch and how the link or invite works; describe only that.
Angle: "They can see you're on your way." Two phones side by side: the runner's live run, and a friend's viewer with the moving dot and live stats.
Hook: the dot moving on the viewer map while the runner's pace updates.

Carousel (4 slides): 01 hook · 02 Runner starts sharing · 03 Friend's live view · 04 CTA.
```

## 6. Workouts

```
/brag --format vertical --duration 30 --tone default

Read marketing/brag/house-rules.md first and follow it strictly.

Feature: logging a gym workout. Rebuild from lib/features/main/presentation/workout_log_screen.dart and create_screen.dart ("What are you up to?"), plus the workout card as it shows in the feed (with full exercise names, never cut off with "…").
Real behaviour: pick exercises, sets, reps and weight, save, post to the feed with tagged gym partners.
Angle: "Leg day, logged and posted." Hook: sets filling in fast, then the workout card dropping into the feed.

Carousel (5 slides): 01 hook · 02 Create "What are you up to?" · 03 Log Workout · 04 Workout card in the feed · 05 CTA.
```

## 7. Meals and nutrition

```
/brag --format vertical --duration 30 --tone app-store

Read marketing/brag/house-rules.md first and follow it strictly.

Feature: food tracking. Rebuild from lib/features/main/presentation/: meal_upload_screen.dart ("Upload Meal"), meal_review_screen.dart ("Meal Review", "Add a food"), meal_tracking_screen.dart ("Meal Summary"). Read the code for how a photo becomes a food list and describe exactly that.
Real behaviour: snap or upload a meal, review and edit the detected foods, see calories and macros (protein, carbs, fat), see the day's summary.
Angle: "Snap it. Check it. Fuel right." Use real South African meals (pap and chakalaka, a braai plate, bunny chow, oats with banana).
Hook: a plate photo turning into a list of foods and a macro ring.

Carousel (5 slides): 01 hook · 02 Upload Meal · 03 Meal Review · 04 Meal Summary with macros · 05 CTA.
```

## 8. Challenges

```
/brag --format vertical --duration 30 --tone chaotic

Read marketing/brag/house-rules.md first and follow it strictly.

Feature: challenges. Rebuild from lib/features/challenges/presentation/: challenge_hub_screen.dart ("CHALLENGES"), live_challenges_screen.dart ("LIVE CHALLENGES"), create_challenge_screen.dart ("NEW CHALLENGE", Public/Private), challenge_board_screen.dart (Accept/Decline, "Invite someone"), challenge_tracker_screen.dart, challenge_outcome_screen.dart.
Real behaviour: create a public or private challenge, invite a friend, the push they get (invited, accepted, completed), the live board, and the outcome screen.
Angle: "Call out your friends." Hook: an invite push lands on screen, then "Accept" is tapped.

Carousel (6 slides): 01 hook "Call out your friends" · 02 New challenge · 03 Invite and accept · 04 Live board · 05 Outcome · 06 CTA.
```

## 9. Races

```
/brag --format vertical --duration 30 --tone cinematic

Read marketing/brag/house-rules.md first and follow it strictly.

Feature: the race calendar. Rebuild from lib/features/races/presentation/: races_screen.dart ("RACES", filters), race_detail_screen.dart, saved_races_screen.dart ("MY RACES", "TO GO" countdown), submit_race_screen.dart ("SUBMIT A RACE"). Use the real race data in the code (Comrades and Two Oceans are in there).
Real behaviour: browse and filter races, open one, save it to My Races with the days-to-go count, submit a race that's missing.
Angle: "Your next start line." Hook: the "TO GO" countdown ticking down to Comrades.

Carousel (5 slides): 01 hook · 02 Race calendar · 03 Race detail · 04 My Races countdown · 05 Submit a race.
```

## 10. Safety

```
/brag --format vertical --duration 30 --tone polished

Read marketing/brag/house-rules.md first and follow it strictly. The tone is serious: no jokes, no chaotic cuts, calm pacing. Use the danger red only where the app does.

Feature: runner safety. Rebuild from lib/features/safety/presentation/: safety_screen.dart, safety_contacts_screen.dart, pin_setup_screen.dart ("Panic PINs"), panic_screen.dart, panic_alert_screen.dart (Police · 10111, Ambulance · 10177, Emergency from a cellphone · 112, "Directions in Google Maps").
Real behaviour (commit 9b0de42): hold the button to send a silent alert, or trigger it from the app icon or with the volume buttons; your safety contacts get your live location; the contact's alert screen with emergency numbers and directions; Panic PINs. Read the code for exactly what each PIN does before describing it.
Angle: "Run free. Someone's got you." Hook: a thumb holding the alert button while the ring fills.

Carousel (6 slides): 01 hook "Run free. Someone's got you." · 02 Safety contacts · 03 Hold to alert · 04 From the app icon or volume buttons · 05 What your contact sees · 06 CTA.
```

## 11. Music

```
/brag --format vertical --duration 30 --tone default

Read marketing/brag/house-rules.md first and follow it strictly.

Feature: music while you train. Rebuild from lib/features/music/: the connect sheet, music_library_sheet, music_mini_player, music_player_card and the music island, plus the album-art glass look. Brand logos are in music_brand_logos.dart. Check music_feature_flags.dart and only show the services that are switched on (Spotify, Apple Music, YouTube Music).
Real behaviour: connect your service, control playback without leaving your run, show what you're playing on your profile, share the song to a Pulse.
Angle: "Your soundtrack, in the app." Hook: the music island expanding over the live run screen.

Carousel (5 slides): 01 hook · 02 Connect your music · 03 Mini player on a run · 04 Now playing on your profile · 05 Share to Pulse.
```

## 12. Profile, achievements and your circle

```
/brag --format vertical --duration 30 --tone app-store

Read marketing/brag/house-rules.md first and follow it strictly.

Feature: your profile. Rebuild from lib/features/main/presentation/: profile_screen.dart, user_profile_screen.dart, achievements_screen.dart ("Achievements"), connections_screen.dart ("Your circle"), and lib/features/auth/presentation/edit_profile_screen.dart. Use the real badge and streak definitions in the code; don't invent badge names.
Real behaviour: your stats and posts, streaks, unlocked badges, your circle of connections, following someone.
Angle: "Proof you showed up." Hook: a streak counter rolling up and a badge unlocking.

Carousel (5 slides): 01 hook · 02 Profile · 03 Streak · 04 Achievements · 05 Your circle.
```

## 13. Notifications

```
/brag --format vertical --duration 30 --tone deadpan

Read marketing/brag/house-rules.md first and follow it strictly.

Feature: notifications. Rebuild from lib/features/notifications/presentation/notifications_screen.dart and the notification settings in lib/features/settings/presentation/settings_screen.dart.
Real behaviour (RELEASE_NOTES.md 1.0.0 (9)): pushes for follows, likes and reactions, comments, replies, mentions, tags and challenge invites, accepts and completions; tapping one opens the post, profile or challenge; each type can be switched off.
Angle: "Only the pings that matter." Hook: a stack of lock-screen pushes with real FitSocial wording, then one tap opening the post.

Carousel (4 slides): 01 hook · 02 Notifications screen · 03 Tap to open · 04 Choose what you hear about.
```

## 14. Everyday tools: weather, BMI, health

```
/brag --format vertical --duration 30 --tone app-store

Read marketing/brag/house-rules.md first and follow it strictly.

Feature: the small tools. Rebuild from lib/features/weather/presentation/weather_forecast_screen.dart ("Weather Forecast"), lib/features/main/presentation/bmi_screen.dart, lib/features/tracking/presentation/health_dashboard_screen.dart ("Health & Devices", "Where this number comes from"), and lib/features/settings/presentation/settings_screen.dart.
Angle: "Check the weather, then go." Hook: the forecast for Durban at 05:30 showing good running weather.

Carousel (5 slides): 01 hook · 02 Weather forecast · 03 Health & Devices · 04 BMI · 05 CTA.
```
