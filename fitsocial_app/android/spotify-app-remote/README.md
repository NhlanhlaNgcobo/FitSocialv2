# Spotify App Remote (Android)

`spotify-app-remote-release-0.8.0.aar` is Spotify's native App Remote library.
It is what actually plays audio: FitSocial sends transport commands over it to
the installed Spotify app, which owns the audio session.

It is **not** on Maven Central, so it is vendored here as a file-artifact Gradle
module. The `spotify_sdk` plugin declares `implementation project(':spotify-app-remote')`,
which resolves to this directory via `include(":spotify-app-remote")` in
`android/settings.gradle.kts`.

Source:
<https://github.com/spotify/android-sdk/releases/download/v0.8.0-appremote_v2.1.0-auth/spotify-app-remote-release-0.8.0.aar>

To upgrade, download a newer asset from
<https://github.com/spotify/android-sdk/releases>, drop it in here, and update
the filename in `build.gradle`.

> The plugin ships a `dart run spotify_sdk:android_setup` script that automates
> this, but it only understands Groovy `android/app/build.gradle`. This project
> uses the Kotlin DSL, so the script aborts in its precondition check and the
> wiring is maintained by hand instead.
