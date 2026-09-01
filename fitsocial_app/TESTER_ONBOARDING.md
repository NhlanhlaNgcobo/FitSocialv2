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

## The release signing certificate

Debug builds are signed with your machine's Android debug key. Everything that
goes to a tester is signed with the keystore named in `android/key.properties`,
which is a different certificate — so anything that authorises by signing
fingerprint has to know about both, or it works when you run from Android
Studio and fails for every tester.

The release fingerprint:

```
A9:FD:B1:A3:95:DE:68:C1:B8:14:0C:EF:AE:0A:6C:68:5E:50:2E:C2
```

Re-derive it from a build you have already made:

```
apksigner verify --print-certs dist/FitSocial-<version>.apk
```

or straight from the keystore, at the path `android/key.properties` points to:

```
keytool -list -v -keystore <storeFile> -alias fitsocial
```

**There are two separate allowlists, and they drift.** Registering a
fingerprint with Firebase does not register it with the Maps API key, and
nothing warns you.

- **Firebase** — `firebase apps:android:sha:list <appId> --project fitsocialv2`.
  This is what Google Sign-In authorises against.
- **The Maps API key** — Google Cloud console, Credentials > Maps Key >
  Android restrictions. This is what the map authorises against.

On 2026-09-01 the tester build showed an empty map: a cream rectangle with the
Google watermark and nothing else, on every device. The key was in the APK and
the package name matched. Firebase had all six fingerprints, the Maps key had
five — the release one was missing, because that list had been seeded from
Firebase before the release keystore existed and never re-synced.

Worth knowing for next time: a Maps *authorisation* failure does not look like
an error. There is no dialog and nothing on screen. The map simply renders its
unstyled base colour, which reads as "tiles are still loading" or "no signal"
and sends you looking in the wrong place. `adb logcat` is where it actually
says so — the SDK logs an authorisation failure with the key it tried.

Two things that make this cheap to fix once diagnosed: it is a console change,
so no rebuild and no redistribution — the build already on testers' phones
starts working on its own. But allow about five minutes for the change to
propagate, and force-stop the app rather than backgrounding it, because the
Maps SDK caches the failure for the life of the process.

**If you ever replace the keystore**, the new fingerprint has to be added to
both lists before the next build goes out.

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
