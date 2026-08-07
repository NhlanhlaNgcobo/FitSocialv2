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

# Spotify App Remote (spotify_sdk).
#
# The .aar ships consumer rules, but it is wired in as a bare file artifact
# rather than a real android-library module, so those are not guaranteed to
# reach R8. Restating them here is cheap insurance — without the Item keeps,
# release builds connect to Spotify and then silently deliver empty player
# state, because the protocol types are deserialised by name.
-keep class com.spotify.protocol.types.** { *; }
-keep class * implements com.spotify.protocol.types.Item { *; }
-keep class com.spotify.android.appremote.api.ConnectionParams$Builder { *; }
-keep class com.spotify.android.appremote.internal.DebugSpotifyLocator { *; }
-keep class com.spotify.android.appremote.internal.ReleaseSpotifyLocator { *; }
-keep class com.spotify.sdk.android.auth.** { *; }
-dontwarn com.spotify.android.appremote.api.ContentApi$ContentType
-dontwarn com.spotify.android.appremote.api.PlayerApi$StreamType
-dontwarn com.fasterxml.jackson.**
# SpotifyServiceBinder is annotated with Spotify's own @NotNull, which lives in
# a spotify-base artifact the vendored App Remote .aar references but does not
# bundle. The -keepattributes *Annotation* below makes R8 try to resolve it, and
# an unresolved annotation type is a hard error rather than a warning — R8 fails
# minifyReleaseWithR8 on it. Safe to drop: annotations are metadata, and this one
# has no runtime retention that anything reads.
-dontwarn com.spotify.base.annotations.**

# The plugin bridges player state as JSON via gson; generic type information
# has to survive for its reflective deserialisation to work.
-keepattributes Signature,InnerClasses,EnclosingMethod,*Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
