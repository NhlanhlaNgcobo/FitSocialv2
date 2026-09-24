package com.fitsocial.fitsocial_app

import android.content.Context
import android.os.BatteryManager
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The battery level for a panic alert, on `fitsocial/panic`. The Dart side is
 * MethodChannelPanicDevice in lib/features/safety/data/panic_device.dart;
 * PanicBridge.swift is its iOS twin.
 *
 * A panic is silent: nothing here sounds, flashes or lights up the phone. A
 * siren can push an attacker who wants to stay unnoticed into violence, so
 * the only thing the phone contributes is the alert and its whereabouts.
 */
class PanicBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "fitsocial/panic"
        private const val TAG = "PanicBridge"
    }

    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "batteryPercent" -> result.success(batteryPercent())
            else -> result.notImplemented()
        }
    }

    private fun batteryPercent(): Int? {
        return try {
            val value = context.getSystemService(BatteryManager::class.java)
                ?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            if (value == null || value !in 0..100) null else value
        } catch (e: Exception) {
            Log.w(TAG, "batteryPercent failed", e)
            null
        }
    }
}
