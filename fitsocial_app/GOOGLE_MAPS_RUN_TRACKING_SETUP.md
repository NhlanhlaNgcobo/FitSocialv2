# Google Maps Run Tracking Setup

The live run tracker in `lib/features/main/presentation/run_log_screen.dart` uses:

- `google_maps_flutter`
- `geolocator`

## Android setup

Once the Flutter Android host project exists, make sure:

1. `android/app/build.gradle` uses `minSdkVersion 21` or higher.
2. `android/app/src/main/AndroidManifest.xml` includes your Maps API key:

```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="${MAPS_API_KEY}" />
```

3. Android location permissions are declared:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

If you later want background tracking, also add:

```xml
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```

4. Add your API key to `local.properties`:

```properties
MAPS_API_KEY=YOUR_API_KEY
```

## Web setup

Add your Google Maps JavaScript API key to `web/index.html` once you want the live map working in web builds.

## Current project note

This workspace still needs a generated native `android/` project folder before the Android manifest and Gradle settings above can be applied.
