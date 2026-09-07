package com.fitsocial.fitsocial_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * FlutterFragmentActivity, not FlutterActivity.
 *
 * The `health` plugin casts the host activity to androidx ComponentActivity so
 * it can launch the Health Connect permission contract. FlutterActivity is not
 * one, so registration threw ClassCastException at startup and every Health
 * Connect read — steps, heart rate, sleep — silently returned nothing:
 *
 *     Error registering plugin health, cachet.plugins.health.HealthPlugin
 *     java.lang.ClassCastException: MainActivity cannot be cast to
 *     androidx.activity.ComponentActivity
 *
 * It failed quietly because the registrant catches the throw and carries on, so
 * the app still launched and only the health data was missing.
 */
class MainActivity : FlutterFragmentActivity() {

    private var mediaSession: MediaSessionBridge? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createSocialNotificationChannel()
    }

    /**
     * The channel push notifications land on.
     *
     * Declared in AndroidManifest.xml as
     * com.google.firebase.messaging.default_notification_channel_id, but naming
     * a channel there does not create it. If it does not exist by the time a
     * message arrives, FCM quietly makes one of its own called "Miscellaneous"
     * and the notification lands there instead -- which is also the name the
     * user then finds in Android's notification settings when they go looking
     * for a way to quieten the app.
     *
     * Creating it here means it exists from the first launch, before anyone has
     * signed in or granted the notification permission, so there is no window
     * in which the fallback can be created and stick. Creating a channel that
     * already exists is a no-op apart from the name and description, which the
     * system updates -- so running this on every launch is how a reworded
     * channel reaches devices that already have it.
     *
     * IMPORTANCE_HIGH is the point of the whole exercise: it is what makes the
     * phone make a sound and vibrate rather than adding a silent line to the
     * shade. The user can still turn that down per channel, which is the right
     * place for them to make that choice.
     *
     * No Build.VERSION guard: minSdk is 26 in app/build.gradle.kts, which is
     * exactly the release NotificationChannel arrived in.
     */
    private fun createSocialNotificationChannel() {
        val channel = NotificationChannel(
            getString(R.string.fcm_channel_social_id),
            getString(R.string.fcm_channel_social_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = getString(R.string.fcm_channel_social_description)
        }

        getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(channel)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Built against the application context, not this activity: the bridge
        // holds a MediaController subscription that has to survive the activity
        // being recreated on rotation, and leaking an Activity into a long-lived
        // system listener is how that turns into a memory leak.
        mediaSession = MediaSessionBridge(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // The session-manager listener is registered with the *system*, which
        // will happily keep calling into a dead engine. Unregistering here is
        // what stops that.
        mediaSession?.dispose()
        mediaSession = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
