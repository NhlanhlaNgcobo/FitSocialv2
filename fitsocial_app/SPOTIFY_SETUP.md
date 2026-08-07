# Spotify setup

FitSocial talks to Spotify over two separate channels, and they are configured
independently. Getting one working tells you nothing about the other.

| | What it does | Needs |
|---|---|---|
| **Web API** (PKCE OAuth) | Reads the profile and playlists; controls a Spotify Connect device elsewhere | A registered redirect URI |
| **App Remote** (native SDK) | **Plays music on this phone** through the installed Spotify app | A redirect URI *and* the package name + SHA-1 fingerprint |

Audio always comes out of the Spotify app's process. No third-party app is
allowed to decode Spotify's catalogue itself, so "playing music through
FitSocial" means FitSocial drives Spotify while Spotify owns the audio session.

## Dashboard configuration

At <https://developer.spotify.com/dashboard> → the FitSocial app → **Settings**.

**Redirect URIs** — add both, exactly:

```
fitsocial://spotify-callback
fitsocial://spotify-sdk-auth
```

The first is the OAuth sign-in callback (`SpotifyConfig.redirectUri`, matched by
the `flutter_web_auth_2` intent-filter). The second is the App Remote handshake
(`SpotifyConfig.appRemoteRedirectUri`, matched by the `redirectSchemeName` /
`redirectHostName` manifest placeholders in `android/app/build.gradle.kts`).
They are deliberately different hosts — pointing both at one URI leaves two
activities claiming it, and Android answers that with an app-chooser dialog in
the middle of sign-in.

**Android package name:**

```
com.fitsocial.fitsocial_app
```

**SHA-1 fingerprint** — the debug key currently in use on this machine:

```
90:45:A1:5E:01:92:28:11:77:46:C3:60:BE:33:37:1E:43:50:A9:E6
```

> There is no `android/key.properties` in this checkout, so release builds fall
> back to debug signing (see `build.gradle.kts`) and this one fingerprint covers
> both. **The moment a real release keystore is added, its SHA-1 has to be
> registered too** — App Remote checks the signature of the calling app, and a
> release build signed with an unregistered key is rejected at connect time with
> an authorisation error, not a build failure.

Read a fingerprint back with:

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android
```

**Users** — while the app is in development mode, every tester's Spotify account
must be added under **User Management**. Accounts that are not listed can sign
in and then get 403s on API calls.

## What each failure looks like

| Symptom | Cause |
|---|---|
| "Install the Spotify app to play music here" | Spotify not installed — App Remote has nothing to bridge to |
| "Spotify would not authorise playback" | Free account (App Remote is Premium-only), unregistered SHA-1, or account not on the User Management list |
| Player works but "Pick a playlist" fails with "No Spotify device is available" | App Remote is down and the Web API fallback has no live Connect device |
| App-chooser dialog appears mid-sign-in | The two redirect URIs collide — check the manifest placeholders |

## Native wiring

`spotify_sdk` needs Spotify's App Remote `.aar`, which is not published to
Maven. It is vendored at `android/spotify-app-remote/` — see the README there.
The plugin's own `dart run spotify_sdk:android_setup` script cannot be used
because it only understands Groovy `android/app/build.gradle`, and this project
uses the Kotlin DSL.
