# Getting a build to a tester

Two halves: what you do when their email arrives, and what you send them.

Testers install through Firebase App Distribution rather than a raw APK.
That is not a preference — a sideloaded APK is blocked on install by Play
Protect, because FitSocial asks for background location, body sensors and
Health Connect records, which is the permission shape its scanner flags for
an app signed by a certificate it has never seen. App Distribution installs
through a trusted channel and is not blocked.

Requirements: Android 8.0 or newer (minSdk 26). No iOS build yet.

---

## Your side

**Add them to the group, then push a build — in that order.**

```
firebase appdistribution:testers:add THEIR@EMAIL.COM --group-alias testers --project fitsocialv2
```

```
powershell -ExecutionPolicy Bypass -File tool/distribute.ps1 -Groups testers
```

Order matters. The invitation email is sent when a release is distributed to
someone who can see it. Adding a tester *after* a build has gone out does not
notify them, and re-uploading an unchanged release does not either — that
combination silently sends nothing, which is exactly what happened on the
first run of this setup.

If you have already shipped the build and only want to add one person, you do
not have to rebuild. Send them the release link directly from the Firebase
console (Release & Monitor > App Distribution > the release > Share). It works
for anyone already in the group.

For a group of testers joining at once, the console also has an invite link
(Testers & Groups > your group) that lets people enrol themselves, so you are
not pasting addresses one at a time.

---

## Send them this

> **Installing the FitSocial test build**
>
> You will get an email from **Firebase App Distribution** inviting you to test
> FitSocial. Check spam if it has not arrived — it often lands there.
>
> Do all of this **on the Android phone you will test on**, signed into the
> same Google account the invite was sent to. Accepting on a laptop does not
> register your device.
>
> 1. Open the invitation email on the phone and tap **Get started**.
> 2. It will send you to install **Firebase App Tester** from the Play Store.
>    Install it. This is Google's own app and is how you will get every future
>    update.
> 3. Open App Tester and sign in with the same Google account.
> 4. **If you already have a copy of FitSocial on the phone, uninstall it
>    first.** Test builds are signed differently to whatever you have, and
>    Android refuses to install one over the other. Skipping this gives you a
>    confusing "app not installed" error.
> 5. Tap **FitSocial** in App Tester, then **Download**, then **Install**.
>    Android will ask permission for App Tester to install apps — allow it.
>    You only do this once.
> 6. Open FitSocial and sign in.
>
> **If Android warns about an unrecognised developer**, that is expected. The
> app is signed with a new certificate that has no history yet. Tap through
> and it will install. If you get a hard block with no way to continue, stop
> and tell me rather than changing any security settings.
>
> **What the app will ask for, and why**
>
> - Location, including in the background — GPS run tracking that keeps
>   working with the screen off
> - Physical activity — step counting
> - Health Connect (steps, heart rate, sleep, distance, calories, workouts) —
>   pulls in what your watch or phone already records
> - Notifications, photos and media, Bluetooth
>
> Decline anything you are not comfortable with; the rest of the app still
> works. Health data stays in your account.
>
> **Reporting problems**: note what screen you were on and what you did just
> before. A screenshot or screen recording is worth far more than a
> description. Crashes are reported automatically, but a message from you is
> what tells me it mattered.

---

## Updates

Push a new build with the same command. Anyone in the group is notified
automatically and updates from inside App Tester — they do not repeat any of
the setup above.

Bump the build number in `pubspec.yaml` (the `+N`) before each build you send
out, or releases are hard to tell apart.
