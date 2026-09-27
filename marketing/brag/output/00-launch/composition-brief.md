# Hyperframes Composition Brief: FitSocial launch clip

## Objective
A 30 s vertical launch clip for FitSocial built from the app's real screens.

## Output
- Composition directory: `composition/`
- Rendered video: `brag.mp4`
- Format: vertical 1080x1920, 30 fps
- Duration: 30 s (house rules override brag's 15-25 s default)

## Source Material
- Project root: `fitsocial_app/`
- Screens: rendered from the Flutter widgets by `fitsocial_app/tool/marketing_shots/` (1179x2556 at 3x, 393x852 logical). Tall captures (`*_long.png`, `challenge_board.png`) are scrolled inside the phone.
- Must appear verbatim (from the screens): "Live Run", "Meal Review", "Detected foods", "Road to Comrades: 100 km", "Send silent alert", "Alerting 3 contacts".
- Tagline: "Train. Fuel. Share. Grow."

## Creative Direction
- Tone preset: app-store
- Angle, hook, outro: see `brag-plan.md`
- Avoid: generic SaaS language, AI phone renders, invented UI. Only the phone frame, status bar and headline type are drawn in HTML.

## Visual Identity
- Background #050505, ember glow #3C2113 / #703515, accent #FF6B1A, text #F7F7F7, muted #AAAAAA
- Display: Anton. Body: Roboto (the app's UI face). Wordmark: Roboto Black Italic with the F mark PNG, as `FitSocialLogo` builds it.
- Phone: flat rounded rectangle, 10 px #1A1A1A bezel, no photoreal hardware.

## Storyboard
1. Hook — 0-3 s — headline + phone rise
2. Feed — 3-8 s — scroll home_feed_long
3. Train — 8-13 s — live_run push + punch-in
4. Fuel — 13-18 s — meal_review_long scroll
5. Share — 18-23 s — pulse_viewer, then challenge_board scroll
6. Safe — 23-27 s — safety hold flipbook, panic_sent
7. End card — 27-30 s

## Audio
- Music: `assets/music/happy-beats-business-moves-vol-1-by-ende-dot-app.mp3` at 0.34, fade out 1.5 s
- Cue source: bundled preset; scene changes locked to 3.02, 8.02, 13.01, 18.02, 20.52, 23.02, 27.02
- Audio-reactive: `assets/audio-data.js` (rms, bass per frame from `marketing/brag/tools/audio_data.py`); bass drives the ember glow's opacity and scale, subtly.
- SFX: drop_001/drop_002 on screen pushes, click_002 on the SOS press, impactSoft_medium_001 on send and on the hook landing, impactBell_heavy_000 on the wordmark.

## Hyperframes Instructions
Standalone composition, one paused GSAP timeline registered as `main`. Local fonts via @font-face. Run `npx hyperframes check` before render.
