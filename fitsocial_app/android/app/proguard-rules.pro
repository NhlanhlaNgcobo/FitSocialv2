# Flutter wrapper — keep embedding classes referenced via reflection.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Firebase / Google Play services keep rules.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# flutter_blue_plus / geolocator / health use platform channels only —
# suppress warnings for optional desktop/reflection paths.
-dontwarn javax.annotation.**

# The Flutter engine references Play Core "deferred components" (dynamic
# feature modules) even though this app doesn't use them. Without the
# play-core dependency present, R8 fails on these missing classes —
# suppress rather than pull in an unused library.
-dontwarn com.google.android.play.core.**
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
