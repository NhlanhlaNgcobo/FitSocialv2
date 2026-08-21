package com.fitsocial.fitsocial_app

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
