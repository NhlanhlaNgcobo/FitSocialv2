package com.fitsocial.fitsocial_app

import io.flutter.embedding.android.FlutterFragmentActivity

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
class MainActivity : FlutterFragmentActivity()
