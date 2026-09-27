# FitSocial brag videos

Fifteen 30-second vertical videos (1080x1920) and matching Instagram carousels
(1080x1350), one per feature, built from the app's real screens.

| # | Folder | Feature |
|---|--------|---------|
| 00 | `output/00-launch` | Whole app |
| 01 | `output/01-onboarding` | Welcome, sign up, profile setup |
| 02 | `output/02-feed` | Feed, reactions, threaded comments, tags |
| 03 | `output/03-pulse` | Pulse (24-hour posts) |
| 04 | `output/04-running` | Run tracking, treadmill, watch imports, run card |
| 05 | `output/05-live-sharing` | Live activity sharing |
| 06 | `output/06-workouts` | Workout log |
| 07 | `output/07-meals` | Meal upload, review, summary |
| 08 | `output/08-challenges` | Running challenges |
| 09 | `output/09-races` | Race calendar |
| 10 | `output/10-safety` | Silent alert, contacts, PINs |
| 11 | `output/11-music` | Music controls and sharing |
| 12 | `output/12-profile` | Profile, badges, your circle |
| 13 | `output/13-notifications` | Notifications |
| 14 | `output/14-tools` | Weather, health, BMI, settings |

Each folder holds:

- `brag.mp4`: the video, with its poster baked in as frame 0
- `brag.jpg`: the poster, for platforms that take a custom thumbnail
- `share-copy.txt`: the caption
- `carousel/carousel_NN.png` and `carousel/carousel-copy.txt`
- `brag-plan.md`: the storyboard; `composition/` and `carousel-src/`: the sources

## How the screens are made

The screens are not mockups. `fitsocial_app/tool/marketing_shots/` pumps the
app's own widgets in Flutter's test engine with fake South African data
(fictional people, real places) and captures them:

- `run.sh <file> [lines] [test name]` runs one shot file.
- Stills land in `tool/marketing_shots/out/<name>.png` (1179x2556, 3x).
- `shootFrames` records frame sequences of real scrolling, typing and gestures;
  `frames_to_mp4.py <name>` encodes them.
- Google Maps cannot render in tests, so `mapcomp.py <name>` draws the map from
  OpenStreetMap streets (`osm/`) in the app's own dark map style and lays it in
  under the app's overlays. Routes in `routes/` follow real Durban and Sea
  Point paths (`osm_route.py`).

## How a video is built

1. `tools/scaffold.py <slug>` sets up `output/<slug>/` from its `spec.json`.
2. Write `output/<slug>/composition/index.html` with the kit (`kit/kit.js`).
3. `tools/static_videos.py <slug>` writes the clip `<video>` tags into the page.
   Hyperframes only extracts frames for videos in the static HTML.
4. `tools/brag.ps1 -Slug <slug> -PosterAt <s> -Slides <n> -SlideLast <s>` checks,
   renders, bakes the poster and snapshots the carousel.

Renders need Hyperframes (installed in the session scratchpad) and ffmpeg
(winget `Gyan.FFmpeg`).
