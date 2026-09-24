package com.fitsocial.fitsocial_app

import android.app.Activity
import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.BatteryManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * The panic deterrent: siren, torch, screen and battery, on `fitsocial/panic`.
 * The Dart side is MethodChannelPanicDevice in
 * lib/features/safety/data/panic_device.dart; PanicBridge.swift is its iOS twin
 * and the two must behave the same.
 *
 * A channel of our own rather than plugins, because this is the one path where
 * a package breaking after an OS update is a safety failure rather than a bug.
 *
 * Every method is best-effort. A phone without a torch, an OEM that refuses a
 * brightness change, a camera held by another app — each is logged and
 * swallowed, and the call still succeeds. Nothing here may throw into the
 * panic flow.
 */
class PanicBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "fitsocial/panic"
        private const val TAG = "PanicBridge"

        /**
         * One strobe cycle may not be shorter than this: 3 Hz, the WCAG 2.3.1
         * ceiling. Dart already sends 334; this is the second lock, so a bad
         * caller can never make the torch flash faster.
         */
        private const val MIN_PERIOD_MS = 334L
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())
    private var activity = WeakReference<Activity>(null)

    private var player: MediaPlayer? = null
    private var previousAlarmVolume: Int? = null

    private var torchCameraId: String? = null
    private var torchOn = false
    private var torchRunnable: Runnable? = null

    private var previousBrightness: Float? = null

    init {
        channel.setMethodCallHandler(this)
    }

    fun attach(activity: Activity?) {
        this.activity = WeakReference(activity)
    }

    fun dispose() {
        safely("dispose") {
            stopSiren()
            stopTorch()
            releaseScreen()
        }
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startSiren" -> safely("startSiren") { startSiren() }
            "stopSiren" -> safely("stopSiren") { stopSiren() }
            "startTorch" -> safely("startTorch") {
                val period = (call.argument<Int>("periodMs") ?: MIN_PERIOD_MS.toInt()).toLong()
                startTorch(maxOf(period, MIN_PERIOD_MS), call.argument<Boolean>("steady") == true)
            }
            "stopTorch" -> safely("stopTorch") { stopTorch() }
            "acquireScreen" -> safely("acquireScreen") { acquireScreen() }
            "releaseScreen" -> safely("releaseScreen") { releaseScreen() }
            "batteryPercent" -> {
                result.success(batteryPercent())
                return
            }
            else -> {
                result.notImplemented()
                return
            }
        }
        result.success(null)
    }

    // --- Siren --------------------------------------------------------------

    /**
     * Loops the siren on the ALARM stream at its maximum volume.
     *
     * USAGE_ALARM is what carries it through silent and vibrate profiles — the
     * ringer mode governs ring and notification streams, not alarms. The alarm
     * stream's own volume is raised to its maximum and put back on stop.
     */
    private fun startSiren() {
        if (player != null) return
        val audio = context.getSystemService(AudioManager::class.java)
        if (audio != null) {
            previousAlarmVolume = audio.getStreamVolume(AudioManager.STREAM_ALARM)
            safely("alarm volume") {
                audio.setStreamVolume(
                    AudioManager.STREAM_ALARM,
                    audio.getStreamMaxVolume(AudioManager.STREAM_ALARM),
                    0,
                )
            }
        }

        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val p = MediaPlayer()
        try {
            context.resources.openRawResourceFd(R.raw.panic_siren).use { afd ->
                p.setAudioAttributes(attributes)
                p.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            }
            p.isLooping = true
            p.setVolume(1f, 1f)
            p.prepare()
            p.start()
            player = p
        } catch (e: Exception) {
            p.release()
            throw e
        }
    }

    private fun stopSiren() {
        player?.let { p ->
            safely("stop player") { if (p.isPlaying) p.stop() }
            p.release()
        }
        player = null
        val previous = previousAlarmVolume ?: return
        previousAlarmVolume = null
        safely("restore alarm volume") {
            context.getSystemService(AudioManager::class.java)
                ?.setStreamVolume(AudioManager.STREAM_ALARM, previous, 0)
        }
    }

    // --- Torch --------------------------------------------------------------

    /**
     * setTorchMode needs no CAMERA permission, so there is no prompt. Strobes
     * at a 50% duty cycle — half the period on, half off — which also halves
     * the LED's heat.
     */
    private fun startTorch(periodMs: Long, steady: Boolean) {
        stopTorch()
        val camera = context.getSystemService(CameraManager::class.java) ?: return
        val id = torchCameraId ?: camera.cameraIdList.firstOrNull { cid ->
            camera.getCameraCharacteristics(cid)
                .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        } ?: return
        torchCameraId = id

        if (steady) {
            setTorch(camera, id, true)
            return
        }
        val half = periodMs / 2
        val tick = object : Runnable {
            override fun run() {
                setTorch(camera, id, !torchOn)
                main.postDelayed(this, half)
            }
        }
        torchRunnable = tick
        main.post(tick)
    }

    private fun stopTorch() {
        torchRunnable?.let { main.removeCallbacks(it) }
        torchRunnable = null
        val id = torchCameraId ?: return
        val camera = context.getSystemService(CameraManager::class.java) ?: return
        setTorch(camera, id, false)
    }

    private fun setTorch(camera: CameraManager, id: String, on: Boolean) {
        safely("setTorchMode") {
            camera.setTorchMode(id, on)
            torchOn = on
        }
    }

    // --- Screen -------------------------------------------------------------

    private fun acquireScreen() {
        val a = activity.get() ?: return
        a.runOnUiThread {
            safely("acquireScreen") {
                val params = a.window.attributes
                if (previousBrightness == null) previousBrightness = params.screenBrightness
                params.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL
                a.window.attributes = params
                a.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    private fun releaseScreen() {
        val a = activity.get() ?: return
        val previous = previousBrightness
        previousBrightness = null
        a.runOnUiThread {
            safely("releaseScreen") {
                val params = a.window.attributes
                params.screenBrightness =
                    previous ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                a.window.attributes = params
                a.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    // --- Battery ------------------------------------------------------------

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

    private inline fun safely(what: String, block: () -> Unit) {
        try {
            block()
        } catch (e: Exception) {
            Log.w(TAG, "$what failed; carrying on", e)
        }
    }
}
