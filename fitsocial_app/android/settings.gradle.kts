pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.3.15") apply false
    // END: FlutterFire Configuration
    // Crashlytics. Not part of the FlutterFire block above because
    // `flutterfire configure` does not add it — it is applied in
    // app/build.gradle.kts, where the mapping upload is also configured.
    id("com.google.firebase.crashlytics") version("3.0.2") apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
// Spotify's App Remote library, vendored as a file artifact — see
// spotify-app-remote/README.md. The spotify_sdk plugin depends on this
// project path by name, so it must be included even though it has no sources.
include(":spotify-app-remote")
