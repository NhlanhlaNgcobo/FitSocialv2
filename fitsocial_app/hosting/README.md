# Share links

Everything a shared FitSocial link touches outside the app.

```
https://fitsocialv2.web.app/post/{postId}
https://fitsocialv2.web.app/user/{userId}
```

That URL is the only thing the share sheet ever sends. What happens when
somebody opens it depends on what they have:

| Recipient                        | What they get                                   |
| -------------------------------- | ----------------------------------------------- |
| Android, app installed, verified | The app opens on the post (Android App Link)     |
| Android, app installed, unverified | `open.html`, which hands off via `intent://`    |
| iOS, app installed               | `open.html` → `fitsocial://app/post/{id}` (Universal Links pending, see below) |
| No app                           | `open.html`, which offers the store              |

`open.html` never redirects on a timer. It makes one hand-off attempt on a
phone and then stops; a page that bounces you to a store after three seconds
fires on exactly the people who already said no.

## Deploying

```bash
firebase deploy --only hosting --project fitsocialv2
```

`firebase.json` points the hosting site at this directory and rewrites
`/post/**` and `/user/**` to `open.html`, which reads the id back out of
`location.pathname`.

Note this site is *not* the Flutter web build in `web/`. If that is ever
deployed it needs its own hosting target rather than replacing this one, or
shared links stop resolving.

## Before links open the app on Android

`.well-known/assetlinks.json` still carries placeholder fingerprints. Until
they are replaced, the https link opens this page instead of the app — which
works, but costs a tap.

1. Get the SHA-256 of the signing key. For a Play-signed app, take it from
   Play Console → Release → Setup → App signing (list **both** the app signing
   key and the upload key). Otherwise:

   ```bash
   keytool -list -v -keystore <path-to-keystore> -alias <alias>
   ```

2. Paste the fingerprints into `sha256_cert_fingerprints`, deploy, and confirm:

   ```bash
   curl https://fitsocialv2.web.app/.well-known/assetlinks.json
   ```

3. Reinstall the app — verification runs at install time. Check it took with:

   ```bash
   adb shell pm get-app-links com.fitsocial.fitsocial_app
   ```

## Before links open the app on iOS

Universal Links need three things this repo cannot supply on its own:

1. An Apple Developer team ID, to write
   `.well-known/apple-app-site-association` (served as `application/json`, no
   file extension):

   ```json
   {
     "applinks": {
       "details": [
         { "appID": "TEAMID.com.fitsocial.fitsocialApp", "paths": ["/post/*", "/user/*"] }
       ]
     }
   }
   ```

2. The Associated Domains capability in Xcode, with
   `applinks:fitsocialv2.web.app`.

3. An App Store listing, whose numeric id goes into `IOS_APP_ID` in
   `open.html` so the fallback button reaches the App Store rather than this
   site's front page.

Until then iOS falls back to the custom scheme, which is already registered in
`Info.plist` and works for anyone who has the app.

## Moving to a custom domain

Four places name the host, and all four have to change together or verified
links break:

- `lib/shared/links/share_links.dart` — `FitSocialLinks.webHost`
- `android/app/src/main/AndroidManifest.xml` — the App Link `<data>` element
- `hosting/open.html` — `SITE`
- the Associated Domains entitlement, once iOS is set up
