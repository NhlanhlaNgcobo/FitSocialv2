package com.fitsocial.fitsocial_app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.net.Uri
import android.os.SystemClock
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

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

        /** Connect and read timeout for cover art fetched over the network. */
        private const val ART_TIMEOUT_MS = 5000

        private const val TAG = "FitSocialMedia"
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
     * Every session on the phone, not just the one being mirrored.
     *
     * A callback registered only on the chosen session cannot see a *different*
     * session wake up, and the session-list listener does not help: it fires
     * when sessions are added or removed, not when one that already exists
     * starts playing. Music apps hold a session open for as long as they are
     * running — Spotify publishes one with null metadata the moment it is
     * launched — so "user pressed play" is almost always a change to a session
     * that already existed, which is a callback on that session and nothing
     * else. Watching all of them is what makes starting a song while FitSocial
     * is already open work at all.
     */
    private var watched = emptyList<MediaController>()

    /**
     * Identity of the last track artwork was sent for.
     *
     * Cover art is a few hundred KB and sessions fire on every seek tick;
     * sending the bitmap each time would push megabytes a second across the
     * platform channel. It goes out only when this changes.
     */
    private var lastArtKey: String? = null

    private var listeningToSessions = false

    /**
     * Cover art is not always a bitmap.
     *
     * Plenty of media sessions publish artwork as a *reference* —
     * METADATA_KEY_ALBUM_ART_URI and its siblings — rather than as pixels,
     * because handing every listener a full-size bitmap costs memory the source
     * app has no reason to spend. Spotify is one of them, which is why this
     * bridge drew a placeholder note for every track it ever read.
     *
     * A URI has to be opened, and opening one is I/O: a content:// read reaches
     * into another app's provider and an https:// one reaches the network,
     * neither of which may happen on the main thread. So the fetch runs here,
     * off-thread, and its result is cached against the track it belongs to and
     * pushed on a later emission.
     */
    private val io = Executors.newSingleThreadExecutor()

    /** The track a URI fetch is currently in flight for, so it runs once. */
    private var fetchingArtKey: String? = null

    /** The track [fetchedArt] belongs to. */
    private var fetchedArtKey: String? = null

    private var fetchedArt: ByteArray? = null

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

    /**
     * Fires when a session is added or removed — never when one that already
     * exists starts or stops playing. That is why it re-watches rather than
     * simply choosing from the list it is handed.
     */
    private val sessionsChanged =
        MediaSessionManager.OnActiveSessionsChangedListener {
            refreshWatched()
            reselect()
        }

    /**
     * Picks the session worth mirroring.
     *
     * The list arrives in priority order — most recently active first — so the
     * head is usually right. A session that is actually playing wins over one
     * that is merely recent, which is what stops a paused podcast from
     * shadowing music started after it.
     *
     * Missing metadata is a preference here, not a filter. It used to be a
     * filter, and that was the bug: a session with nothing loaded yet was
     * dropped from the list entirely, so nothing was ever attached to it and
     * the moment it *gained* a track went unheard. It now sorts last instead,
     * which keeps a dormant player from shadowing a live one without making it
     * invisible.
     */
    private fun pick(controllers: List<MediaController>?): MediaController? {
        val candidates = controllers.orEmpty().filter {
            // Our own sessions would be a feedback loop.
            it.packageName != context.packageName
        }
        return candidates.firstOrNull {
            it.playbackState?.state == PlaybackState.STATE_PLAYING &&
                it.metadata != null
        }
            ?: candidates.firstOrNull { it.metadata != null }
            ?: candidates.firstOrNull()
    }

    /**
     * Registered on every session in [watched].
     *
     * Each of these re-runs the choice rather than merely re-emitting, because
     * the event may be coming from a session that is not the current one — a
     * second music app starting, or the dormant session this bridge is parked
     * on finally loading a track. Deciding again is the only way that becomes
     * the mirrored session.
     */
    private val controllerCallback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) = reselect()

        override fun onMetadataChanged(metadata: MediaMetadata?) = reselect()

        override fun onAudioInfoChanged(info: MediaController.PlaybackInfo) =
            reselect()

        override fun onSessionDestroyed() {
            // The app that was playing went away. Re-poll rather than blanking
            // outright: another session is often already waiting behind it.
            refreshWatched()
            reselect()
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

    /**
     * Re-subscribes to the full set of sessions on the phone.
     *
     * The manager hands back fresh [MediaController] instances each call, so the
     * old ones are unregistered wholesale rather than diffed — registering twice
     * on the same session would double every callback, and a controller we no
     * longer hold cannot be unregistered later.
     */
    private fun refreshWatched() {
        watched.forEach {
            try {
                it.unregisterCallback(controllerCallback)
            } catch (e: Exception) {
                // The session died between listing and unregistering. Nothing
                // to detach from, and nothing worth failing over.
            }
        }
        watched = activeSessions().filter { it.packageName != context.packageName }
        watched.forEach { it.registerCallback(controllerCallback, main) }
    }

    /** Decides which watched session to mirror, then pushes the result. */
    private fun reselect() {
        val next = pick(watched)
        if (controller?.sessionToken != next?.sessionToken) {
            controller = next
            // A different session means different artwork, whatever the cache
            // last held.
            lastArtKey = null
        }
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
        refreshWatched()
        reselect()
        return true
    }

    private fun stop() {
        if (listeningToSessions) {
            sessionManager?.removeOnActiveSessionsChangedListener(sessionsChanged)
            listeningToSessions = false
        }
        watched.forEach {
            try {
                it.unregisterCallback(controllerCallback)
            } catch (e: Exception) {
                // Already gone; nothing to detach.
            }
        }
        watched = emptyList()
        controller = null
        lastArtKey = null
    }

    /** Releases every listener. Called when the engine detaches. */
    fun dispose() {
        stop()
        io.shutdownNow()
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
        return compress(bitmap)
    }

    /**
     * Downscales and JPEG-encodes, leaving the caller's bitmap alone.
     *
     * The source may belong to a MediaMetadata that other code still reads, so
     * the only thing recycled here is a scaled copy this function made itself.
     */
    private fun compress(bitmap: Bitmap): ByteArray? {
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
            if (scaled !== bitmap) scaled.recycle()
            out.toByteArray()
        } catch (e: Exception) {
            // Artwork is decoration. A recycled or oversized bitmap must never
            // take the whole snapshot down with it.
            null
        }
    }

    /**
     * Cover art for this track: the bitmap if the session published one, the
     * cached result of a URI fetch if one has already landed, otherwise null
     * with a fetch started in the background.
     */
    private fun resolveArt(key: String, metadata: MediaMetadata?): ByteArray? {
        artBytes(metadata)?.let { return it }
        if (fetchedArtKey == key) return fetchedArt
        fetchArt(key, metadata)
        return null
    }

    /** Opens the artwork URI off the main thread, then re-emits with it. */
    private fun fetchArt(key: String, metadata: MediaMetadata?) {
        val uri = metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM_ART_URI)
            ?: metadata?.getString(MediaMetadata.METADATA_KEY_ART_URI)
            ?: metadata?.getString(MediaMetadata.METADATA_KEY_DISPLAY_ICON_URI)
        if (uri.isNullOrEmpty()) {
            // Neither a bitmap nor a reference. Naming the keys the session did
            // set is the one line that turns "the cover is missing" from a
            // guess into a fact, and it costs a log call per track change.
            Log.d(TAG, "no artwork on this session; keys=" +
                metadata?.keySet()?.joinToString(","))
            return
        }
        if (fetchingArtKey == key) return
        fetchingArtKey = key

        io.execute {
            val bytes = readArt(uri)
            main.post {
                if (fetchingArtKey == key) fetchingArtKey = null
                if (bytes == null) {
                    Log.d(TAG, "artwork uri would not open: $uri")
                    return@post
                }
                fetchedArt = bytes
                fetchedArtKey = key
                // The snapshot that asked for this already went out without it,
                // and sessions only emit on change — so unless we forget having
                // sent this track's artwork, nothing would ever send it. This
                // marks it dirty again for the emit below.
                if (lastArtKey == key) lastArtKey = null
                emit()
            }
        }
    }

    /**
     * Reads an artwork URI into JPEG bytes. Runs on [io], never on main.
     *
     * Every failure here is ordinary: a provider that will not grant us a read,
     * a scheme with no opener, a dead network, or one of the pseudo-URIs some
     * apps publish that are not addressable at all. They all mean the same
     * thing to the caller — this track has no cover to draw.
     */
    private fun readArt(raw: String): ByteArray? {
        var connection: HttpURLConnection? = null
        return try {
            val parsed = Uri.parse(raw)
            val stream = when (parsed.scheme?.lowercase()) {
                "http", "https" -> {
                    connection = (URL(raw).openConnection() as HttpURLConnection)
                        .apply {
                            connectTimeout = ART_TIMEOUT_MS
                            readTimeout = ART_TIMEOUT_MS
                        }
                    connection?.inputStream
                }
                // content://, file:// and android.resource:// all open through
                // the resolver; a scheme it cannot handle throws, which the
                // catch below turns into "no cover".
                else -> context.contentResolver.openInputStream(parsed)
            } ?: return null

            val bitmap = stream.use { BitmapFactory.decodeStream(it) }
                ?: return null
            val bytes = compress(bitmap)
            // This one we decoded ourselves, so this one is ours to release.
            bitmap.recycle()
            bytes
        } catch (e: Exception) {
            null
        } finally {
            connection?.disconnect()
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
        val art = if (artChanged) resolveArt(artKey, metadata) else null
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
        val active = controller ?: run {
            refreshWatched()
            pick(watched)?.also { controller = it }
        }
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
