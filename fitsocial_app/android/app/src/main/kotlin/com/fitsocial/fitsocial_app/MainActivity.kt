package com.fitsocial.fitsocial_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
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
    private var panic: PanicBridge? = null
    private var videoLoop: VideoLoopBridge? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        forgetReplayedLaunch()
        super.onCreate(savedInstanceState)
        createSocialNotificationChannel()
        createPanicNotificationChannel()
    }

    /**
     * A launch from Recents is not a fresh tap.
     *
     * Android restarts a task from Recents with the intent it was first
     * opened by, flagged LAUNCHED_FROM_HISTORY. If that was a notification or
     * a shared link, its extras and data come back too — and both the FCM
     * plugin's getInitialMessage and Flutter's deep-link route read them as if
     * the user had just tapped. A tester opened the app from a meal-reaction
     * push one morning and every later launch dropped her on that meal post.
     *
     * Cleared before super.onCreate, which is when Flutter and its plugins
     * first read the intent. The Dart side also refuses a repeated push id
     * (LaunchTapLedger), for any path this does not cover.
     */
    private fun forgetReplayedLaunch() {
        val launch = intent ?: return
        if (launch.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0) return
        launch.data = null
        launch.replaceExtras(Bundle())
    }

    /**
     * The channel panic alerts land on — separate from Social, so that muting
     * likes can never mute an emergency. The id must match PANIC_CHANNEL_ID in
     * functions/safety.js, which names it on every panic push.
     *
     * High importance, alarm-style sound and a strong vibration. Bypassing Do
     * Not Disturb is not set: Android only honours it once the user has granted
     * notification-policy access, and asking for that is a separate, explicit
     * step in the safety setup rather than something done silently here.
     */
    private fun createPanicNotificationChannel() {
        val channel = NotificationChannel(
            getString(R.string.fcm_channel_panic_id),
            getString(R.string.fcm_channel_panic_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = getString(R.string.fcm_channel_panic_description)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 800, 300, 800, 300, 800)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }

        getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(channel)
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
        // The battery level for panic alerts. Application context: it reads
        // a system service and nothing tied to this activity.
        panic = PanicBridge(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        // Card video loops. Application context: it writes to the cache dir
        // and runs an encoder, neither of which belongs to this activity.
        videoLoop = VideoLoopBridge(
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
        panic?.dispose()
        panic = null
        videoLoop?.dispose()
        videoLoop = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
