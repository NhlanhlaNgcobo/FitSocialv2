# Brag Plan: FitSocial onboarding

## Angle
"Your crew is already here." The first-run flow as it really is: splash, welcome, sign up, profile, feed. The profile scene types Sipho's name and handle into the real form, so the header, progress bar ("Off the ground 2/5") and the handle check ("Available.") react live.

## Tone
- Preset: polished. Creative direction: calm first-run walkthrough.
- Format: vertical 1080x1920, 30 s. Music: happy-beats vol-12 (110 BPM) at 0.34, fade 1.5 s.

## Storyboard (scene changes on the beat grid)
1. 0-3.27 Hook: "YOUR CREW IS / ALREADY HERE." opens centred, rides up as the phone rises on the splash (clip_splash).
2. 3.27-8.74 Welcome (clip_welcome): "BUILT FOR HOW YOU TRAIN." / "Runs, lifts, meals and the people you do them with."
3. 8.74-13.11 Sign up (strong beat): "ONE TAP TO JOIN." / "Sign up with Google or with email." Tap lands on the Google button.
4. 13.11-19.66 Profile (clip_profile_typing): "MAKE IT YOURS." / "Pick a name and a handle. We check it's free." Glass chime as "Available." appears.
5. 19.66-26.0 Feed (clip_home_scroll): "LAND IN YOUR FEED." / "Your crew's runs, lifts and meals, first thing."
6. 26.0-30 Wordmark + "Train. Fuel. Share. Grow." on a bell.

## Audio
Soft drop on each screen change, click on the tap, glass on "Available.", bell on the wordmark. Bass breathes the ember glow.

## Claims checked against code
Google sign-up (login_screen.dart continueWithProvider('google')), username availability check (username_repository.dart), profile completion meter (profile_setup_screen.dart).
