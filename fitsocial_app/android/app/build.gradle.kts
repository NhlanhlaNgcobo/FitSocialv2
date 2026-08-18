plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("com.google.firebase.crashlytics")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

// Google Maps SDK key.
//
// Read from android/local.properties, which is gitignored — so the key is never
// committed. A gradle property (-PMAPS_API_KEY=... or ~/.gradle/gradle.properties)
// still wins, which is how CI supplies it without a local.properties file.
// Falls back to empty: the build succeeds and only the map view fails, rather
// than blocking every developer who hasn't set a key yet.
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}

val mapsApiKey: String = (project.findProperty("MAPS_API_KEY") as String?)
    ?: localProperties.getProperty("MAPS_API_KEY")
    ?: ""

// Release signing config is read from android/key.properties (gitignored).
// When absent (e.g. a fresh clone or CI without secrets), the release build
// falls back to debug signing so `flutter build` still works.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.fitsocial.fitsocial_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.fitsocial.fitsocial_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Health Connect (health package) requires Android 8.0+
        minSdk = maxOf(26, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
        // Spotify's auth library (pulled in by spotify_sdk) declares its
        // callback activity with these placeholders. They must resolve or the
        // manifest merger fails the build, and together they have to spell the
        // App Remote redirect URI registered in the Spotify dashboard — see
        // SpotifyConfig.appRemoteRedirectUri.
        //
        // Deliberately *not* the same host as the flutter_web_auth_2 callback:
        // two activities claiming one URI makes Android show a chooser dialog
        // mid-sign-in.
        manifestPlaceholders["redirectSchemeName"] = "fitsocial"
        manifestPlaceholders["redirectHostName"] = "spotify-sdk-auth"
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // No keystore present — fall back to debug signing so the
                // build still succeeds (not distributable to the Play Store).
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )

            // R8 rewrites every class and method name in this build, so a
            // crash arrives at Crashlytics as `a.b.c(Unknown Source)` unless
            // the mapping file goes up with it. Uploading it is the whole
            // difference between a report you can act on and a report you
            // cannot — and it only matters here, which is why minification and
            // this setting are configured on the same build type.
            //
            // A copy is still archived to dist/ by the release script, for
            // reading a stack trace by hand if it ever comes to that.
            configure<com.google.firebase.crashlytics.buildtools.gradle.CrashlyticsExtension> {
                mappingFileUploadEnabled = true
            }
        }

        debug {
            // Nothing from a developer's own laptop belongs in the dashboard
            // we watch during testing. Symbol upload is the slow part of the
            // plugin, and a debug build has nothing to symbolicate anyway.
            //
            // This does not by itself stop debug crashes being *sent* — that
            // is decided at runtime in crash_reporter.dart, which is where the
            // kDebugMode switch lives.
            configure<com.google.firebase.crashlytics.buildtools.gradle.CrashlyticsExtension> {
                mappingFileUploadEnabled = false
            }
        }
    }
}

flutter {
    source = "../.."
}
