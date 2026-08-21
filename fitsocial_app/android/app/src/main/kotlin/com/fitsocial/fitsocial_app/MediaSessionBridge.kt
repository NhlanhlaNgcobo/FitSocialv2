package com.fitsocial.fitsocial_app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.text.TextUtils
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Reads and drives whatever music app is currently playing, through Android's
 * own media-session APIs.
 *
 * This is a *remote control*, not a player: it presses the buttons on a session
 * some other app has already started, and reads what that session broadcasts.
 * It cannot start a particular song — MediaController only ever steers a
 * session that already exists.
 *
 * Nothing here talks to Spotify, Google or Apple. That is the point: no OAuth,
 * no client ID, no quota and no per-user allowlist, so it works for every user
 * on every music app, free tiers included.
 *
 * Access is gated on notification-listener permission (see
 * [MediaSessionListener]); every session-manager call throws SecurityException
 * without it, so all of them are guarded.
 */
class MediaSessionBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "com.fitsocial.fitsocial_app/media_session"
        const val EVENT_CHANNEL = "com.fitsocial.fitsocial_app/media_session/events"

        /** Longest edge for cover art handed to Dart, in pixels. */
        private const val ART_MAX_PX = 512

        /**
         * JPEG quality for that art. Cover art is photographic; PNG roughly
         * doubles the payload for no visible gain at this size.
         */
        private const val ART_QUALITY = 85

        /**
         * VolumeProvider.VOLUME_CONTROL_FIXED — a device that reports a level
         * but will not accept a new one.
         */
        private const val VOLUME_CONTROL_FIXED = 0
    }

    private val main = Handler(Looper.getMainLooper())

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL).apply {
        setMethodCallHandler(this@MediaSessionBridge)
    }
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL).apply {
        setStreamHandler(this@MediaSessionBridge)
    }

    private val sessionManager: MediaSessionManager? =
        context.getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager

    private val listenerComponent = ComponentName(context, MediaSessionListener::class.java)

    private var sink: EventChannel.EventSink? = null

    /** The session currently being mirrored, if any. */
    private var controller: MediaController? = null

    /**
     * Identity of the last track artwork was sent for.
     *
     * Cover art is a few hundred KB and sessions fire on every seek tick;
     * sending the bitmap each time would push megabytes a second across the
     * platform channel. It goes out only when this changes.
     */
    private var lastArtKey: String? = null

    private var listeningToSessions = false

    // --- Permission ---

    private fun hasPermission(): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        if (TextUtils.isEmpty(enabled)) return false
        // The setting is a colon-separated list of flattened component names.
        // Parse and compare components rather than matching substrings: another
        // package whose name merely contains ours would otherwise read as a hit.
        return enabled.split(':').any {
            ComponentName.unflattenFromString(it) == listenerComponent
        }
    }

    // --- Session discovery ---

    private val sessionsChanged =
        MediaSessionManager.OnActiveSessionsChangedListener { controllers ->
            attachTo(pick(controllers))
        }

    /**
     * Picks the session worth mirroring.
     *
     * The list arrives in priority order — most recently active first — so the
     * head is usually right. A session that is actually playing wins over one
     * that is merely recent, which is what stops a paused podcast from
     * shadowing music started after it.
     */
    private fun pick(controllers: List<MediaController>?): MediaController? {
        val candidates = controllers.orEmpty().filter {
            // Our own sessions would be a feedback loop, and a session with no
            // metadata has nothing to show.
            it.packageName != context.packageName && it.metadata != null
        }
        return candidates.firstOrNull {
            it.playbackState?.state == PlaybackState.STATE_PLAYING
        } ?: candidates.firstOrNull()
    }

    private val controllerCallback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) = emit()

        override fun onMetadataChanged(metadata: MediaMetadata?) = emit()

        override fun onAudioInfoChanged(info: MediaController.PlaybackInfo) = emit()

        override fun onSessionDestroyed() {
            // The app that was playing went away. Re-poll rather than blanking
            // outright: another session is often already waiting behind it.
            attachTo(pick(activeSessions()))
        }
    }

    private fun activeSessions(): List<MediaController> {
        val manager = sessionManager ?: return emptyList()
        return try {
            manager.getActiveSessions(listenerComponent)
        } catch (e: SecurityException) {
            emptyList()
        }
    }

    private fun attachTo(next: MediaController?) {
        val current = controller
        if (current != null && next != null &&
            current.sessionToken == next.sessionToken
        ) {
            // Same session — its changed state is why this was called.
            emit()
            return
        }
        current?.unregisterCallback(controllerCallback)
        controller = next
        lastArtKey = null
        next?.registerCallback(controllerCallback, main)
        emit()
    }

    /** Starts mirroring, if permission allows. Safe to call repeatedly. */
    private fun start(): Boolean {
        if (!hasPermission()) return false
        val manager = sessionManager ?: return false
        if (!listeningToSessions) {
            try {
                manager.addOnActiveSessionsChangedListener(
                    sessionsChanged,
                    listenerComponent,
                    main,
                )
                listeningToSessions = true
            } catch (e: SecurityException) {
                return false
            }
        }
        attachTo(pick(activeSessions()))
        return true
    }

    private fun stop() {
        if (listeningToSessions) {
            sessionManager?.removeOnActiveSessionsChangedListener(sessionsChanged)
            listeningToSessions = false
        }
        controller?.unregisterCallback(controllerCallback)
        controller = null
        lastArtKey = null
    }

    /** Releases every listener. Called when the engine detaches. */
    fun dispose() {
        stop()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        sink = null
    }

    // --- Reading state ---

    /**
     * Live playback position.
     *
     * PlaybackState reports where the track was at its
     * `lastPositionUpdateTime`, not where it is now — so a session playing
     * untouched for a minute still reports the position it held a minute ago.
     * Extrapolating by elapsed real time, scaled by playback speed, is what
     * makes a progress bar track reality between callbacks.
     */
    private fun livePosition(state: PlaybackState?): Long {
        if (state == null) return 0L
        var position = state.position
        if (state.state == PlaybackState.STATE_PLAYING) {
            val elapsed = SystemClock.elapsedRealtime() - state.lastPositionUpdateTime
            val speed = if (state.playbackSpeed > 0f) state.playbackSpeed else 1f
            position += (elapsed * speed).toLong()
        }
        return position.coerceAtLeast(0L)
    }

    private fun appLabel(packageName: String): String {
        return try {
            val pm = context.packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString()
        } catch (e: Exception) {
            packageName
        }
    }

    /**
     * Cover art as JPEG bytes, downscaled.
     *
     * Sessions publish artwork at whatever size the source app felt like —
     * often 1024px or larger. Handing that straight to Dart puts a multi-MB
     * blob through the channel and then holds it in memory behind a 44px chip.
     */
    private fun artBytes(metadata: MediaMetadata?): ByteArray? {
        val bitmap = metadata?.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: metadata?.getBitmap(MediaMetadata.METADATA_KEY_ART)
            ?: metadata?.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
            ?: return null
        return try {
            val longest = maxOf(bitmap.width, bitmap.height)
            val scaled = if (longest > ART_MAX_PX && longest > 0) {
                val ratio = ART_MAX_PX.toFloat() / longest
                Bitmap.createScaledBitmap(
                    bitmap,
                    (bitmap.width * ratio).toInt().coerceAtLeast(1),
                    (bitmap.height * ratio).toInt().coerceAtLeast(1),
                    true,
                )
            } else {
                bitmap
            }
            val out = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, ART_QUALITY, out)
            // Only the copy is ours to release; the original belongs to the
            // metadata object and is still needed by whoever reads it next.
            if (scaled !== bitmap) scaled.recycle()
            out.toByteArray()
        } catch (e: Exception) {
            // Artwork is decoration. A recycled or oversized bitmap must never
            // take the whole snapshot down with it.
            null
        }
    }

    private fun volumeSettable(info: MediaController.PlaybackInfo): Boolean =
        info.volumeControl != VOLUME_CONTROL_FIXED && info.maxVolume > 0

    private fun snapshot(): Map<String, Any?> {
        val active = controller
        val granted = hasPermission()
        if (active == null) {
            return mapOf(
                "hasPermission" to granted,
                "hasTrack" to false,
            )
        }

        val metadata = active.metadata
        val state = active.playbackState
        val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE).orEmpty()
        val artist = metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
            ?: ""
        val album = metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM).orEmpty()
        val duration = metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L

        // Identity for the artwork cache. Sessions rarely publish a stable id,
        // so the fields a person would use to name the song stand in for one.
        val artKey = active.packageName + "|" + title + "|" + artist + "|" + album
        val artChanged = artKey != lastArtKey
        val art = if (artChanged) artBytes(metadata) else null
        if (artChanged) lastArtKey = artKey

        val actions = state?.actions ?: 0L
        val info = active.playbackInfo

        return mapOf(
            "hasPermission" to granted,
            "hasTrack" to (title.isNotEmpty() || artist.isNotEmpty()),
            "appPackage" to active.packageName,
            "appName" to appLabel(active.packageName),
            "title" to title,
            "artist" to artist,
            "album" to album,
            "durationMs" to duration.coerceAtLeast(0L),
            "positionMs" to livePosition(state),
            "isPlaying" to (state?.state == PlaybackState.STATE_PLAYING),
            // No shuffle or repeat. android.media.session.MediaController
            // has no accessor for either — they exist only on androidx's
            // MediaControllerCompat, which would mean rebuilding every
            // controller through MediaSessionCompat.Token.fromToken(). The
            // flag lets the player card disable both buttons rather than show
            // controls that silently do nothing.
            "canSetShuffleRepeat" to false,
            "canSkipNext" to (actions and PlaybackState.ACTION_SKIP_TO_NEXT != 0L),
            "canSkipPrevious" to (actions and PlaybackState.ACTION_SKIP_TO_PREVIOUS != 0L),
            "canSeek" to (actions and PlaybackState.ACTION_SEEK_TO != 0L),
            "volumePercent" to info?.let {
                if (it.maxVolume > 0) it.currentVolume * 100 / it.maxVolume else null
            },
            "supportsVolume" to (info != null && volumeSettable(info)),
            // A null `albumArt` means "unchanged, keep what you have"; this
            // flag is what separates that from "this track has no cover".
            "albumArtChanged" to artChanged,
            "albumArt" to art,
        )
    }

    private fun emit() {
        val payload = snapshot()
        main.post { sink?.success(payload) }
    }

    // --- Channels ---

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        // A listener that subscribes while music is already playing must not
        // sit empty until the user next presses a button, so current state goes
        // out immediately rather than waiting for a session callback.
        if (!start()) emit()
    }

    override fun onCancel(arguments: Any?) {
        stop()
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermission" -> result.success(hasPermission())

            "openPermissionSettings" -> {
                val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    context.startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    // Some OEM builds hide the screen entirely.
                    result.success(false)
                }
            }

            // Called when the app returns to the foreground: permission may
            // have been granted while we were away, and sessions may have
            // changed with no callback delivered to a stopped listener.
            "refresh" -> {
                start()
                result.success(snapshot())
            }

            "snapshot" -> result.success(snapshot())

            "play" -> transport(result) { it.transportControls.play() }
            "pause" -> transport(result) { it.transportControls.pause() }
            "skipNext" -> transport(result) { it.transportControls.skipToNext() }
            "skipPrevious" -> transport(result) { it.transportControls.skipToPrevious() }

            "seek" -> {
                val ms = (call.argument<Number>("positionMs") ?: 0).toLong()
                transport(result) { it.transportControls.seekTo(ms) }
            }

            // No "setShuffle" or "setRepeat" case: TransportControls offers
            // neither. Dart never sends them — see the note in snapshot().

            "setVolume" -> {
                val percent = (call.argument<Number>("percent") ?: 0).toInt()
                transport(result) {
                    val info = it.playbackInfo
                    if (info != null && volumeSettable(info)) {
                        val target = (info.maxVolume * percent / 100)
                            .coerceIn(0, info.maxVolume)
                        it.setVolumeTo(target, 0)
                    }
                }
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Runs a transport command against the live session.
     *
     * Every failure here is ordinary rather than exceptional — the user closed
     * their music app, or revoked notification access while we were running —
     * so these answer with a typed error the Dart side turns into a hint,
     * rather than throwing.
     */
    private fun transport(
        result: MethodChannel.Result,
        action: (MediaController) -> Unit,
    ) {
        if (!hasPermission()) {
            result.error("no_permission", "Notification access is not granted.", null)
            return
        }
        val active = controller ?: pick(activeSessions())?.also { attachTo(it) }
        if (active == null) {
            result.error("no_session", "Nothing is playing.", null)
            return
        }
        try {
            action(active)
            result.success(null)
        } catch (e: SecurityException) {
            result.error("no_permission", e.message, null)
        } catch (e: Exception) {
            result.error("failed", e.message, null)
        }
    }
}
