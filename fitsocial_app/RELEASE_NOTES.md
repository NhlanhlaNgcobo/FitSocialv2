# Release notes

Newest first. One section per tester build; the version here is the one in
`pubspec.yaml`, which is what App Distribution shows testers.

## 1.0.0 (9) — 2026-09-07

Everything below landed since 1.0.0 (8).

### Push notifications

FitSocial now reaches you when the app is closed. The phone registers with
Firebase Messaging on sign-in and drops its registration on sign-out, so a
shared phone never pushes the previous person's notifications.

- Pushes for follows, likes and reactions, comments, replies, mentions, tags,
  and the three challenge events — invited, accepted, completed.
- Tapping one opens the thing it is about — the post, the profile, the
  challenge — rather than the app's front door.
- Per-type preferences are kept on the device, so turning one kind off is not
  a round trip.
- Dead device tokens are pruned when a send is rejected, so an uninstalled
  phone stops costing a delivery attempt.

### Comment replies

Comments are threaded one level deep. A reply carries the comment it answers,
replies group under their parent instead of arriving as loose lines further
down, and the composer says who you are replying to. Reply notifications are
their own type, so the author of the post and the author of the comment both
hear about the right thing.

### Runs recorded somewhere else now show up

A run recorded on a watch, or by Samsung Health with the phone in a pocket,
used to be invisible to FitSocial — the app only knew about runs somebody
opened it to start.

- On open and on resume, the app reads running sessions out of the platform
  health store and files each new one as a draft on Create. Nothing reaches
  the feed or the database until you tap it.
- A session that overlaps a run FitSocial already logged is dropped, so using
  the app does not produce the same outing twice.
- Discarding an imported draft sticks: an import ledger remembers every
  session already dealt with, so an unwanted run is not offered back tomorrow.
- Each scan rereads a fixed 48-hour window rather than following a cursor,
  because Health Connect is filled in batches and a run that finished an hour
  ago is routinely not there yet.
- Imported runs carry distance, duration, pace and heart rate but no route —
  Health Connect keeps the route behind a separate permission — and the card
  says so rather than looking like a map that failed to load.
- They arrive private; posting one to the feed is a deliberate second choice
  in the overflow menu.
- The whole thing is off with one switch in Settings, under Health data.

### Save and share the run card

The run card can now leave the app as a picture.

- **Save to Photos / Share** buttons sit under the card preview when you
  finish a tracked run and when you log a run by hand — they act on exactly
  what is being previewed, including a photo you just picked.
- **Save image** joins the share sheet on any run post in the feed or on its
  own page, alongside sharing and copying the link.
- The file is a 1080px PNG, laid out at phone width and rasterised at 3x so
  the proportions stay the ones that were designed, and cropped to the shape
  of the card you were looking at.
- A card with no photo is drawn on the theme's own ground rather than coming
  out transparent, so it does not pick up black notches when Instagram
  flattens the alpha.
- Saving never touches the run itself: a failed export is a side errand, and
  it says what went wrong — no photo access (with a shortcut to Settings), no
  space left, or a photo that would not load.

### Fixes and plumbing

- Push delivery is now logged: one line per notification saying how many
  devices it reached, and an explicit line when a recipient has no registered
  device at all — previously the single most confusing failure, because
  everything succeeded and nothing was sent.
- Android declares `WRITE_EXTERNAL_STORAGE` capped at API 28 for the gallery
  write; from API 29 the MediaStore insert needs no permission at all.
- iOS declares `NSPhotoLibraryAddUsageDescription` — add-only, so saving does
  not trigger the full photo-library prompt.
- New dependency: `gal` ^2.3.0 for the gallery write.
- Documented that a tester added without `--group-alias` is never emailed and
  never told.

Verified: `flutter analyze` clean, 1273 Dart tests pass, 91 Cloud Functions
tests pass. Not verified on device — the APK could not be built in this
environment (see the loopback blocker), so the build itself was run by hand.
