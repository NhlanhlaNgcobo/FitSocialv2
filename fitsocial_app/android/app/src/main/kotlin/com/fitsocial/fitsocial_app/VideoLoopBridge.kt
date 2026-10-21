package com.fitsocial.fitsocial_app

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Turns a picked video into the short loop behind a run or workout card, on
 * `fitsocial/video_loop`. The Dart side is VideoLoopMaker in
 * lib/shared/services/video_loop_maker.dart.
 *
 * One pass through Media3's Transformer: cut to the chosen few seconds, drop
 * the sound (a card plays muted, so audio is only weight), and bring the short
 * side down to 720px at a bitrate that keeps five seconds near a megabyte.
 * The first frame is saved beside it as a JPEG — the card's still, which is
 * what older builds, the share export and the moment before playback show.
 *
 * Media3 rather than a bundled ffmpeg: video_player already ships Media3's
 * player, so this adds the transformer and nothing like a second media stack.
 */
class VideoLoopBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "fitsocial/video_loop"
        private const val TAG = "VideoLoopBridge"
        private const val SHORT_SIDE = 720
        private const val BITRATE = 2_000_000
    }

    private val channel = MethodChannel(messenger, CHANNEL)

    /** The export in flight. One at a time: there is one picker on screen. */
    private var running: Transformer? = null

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        running?.cancel()
        running = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "makeLoop" -> makeLoop(call, result)
            else -> result.notImplemented()
        }
    }

    private fun makeLoop(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val startMs = call.argument<Number>("startMs")?.toLong() ?: 0L
        val durationMs = call.argument<Number>("durationMs")?.toLong()
        if (path == null || durationMs == null || durationMs <= 0) {
            result.error("bad_args", "path and durationMs are required", null)
            return
        }

        running?.cancel()

        val dir = File(context.cacheDir, "video_loops").apply { mkdirs() }
        val stamp = System.currentTimeMillis()
        val video = File(dir, "loop_$stamp.mp4")
        val poster = File(dir, "loop_$stamp.jpg")

        val clipping = MediaItem.ClippingConfiguration.Builder()
            .setStartPositionMs(startMs)
            .setEndPositionMs(startMs + durationMs)
            .build()
        val item = MediaItem.Builder()
            .setUri(Uri.fromFile(File(path)))
            .setClippingConfiguration(clipping)
            .build()

        val videoEffects = scaleEffect(path)?.let { listOf(it) } ?: emptyList()
        val edited = EditedMediaItem.Builder(item)
            .setRemoveAudio(true)
            .setEffects(Effects(emptyList(), videoEffects))
            .build()

        val encoders = DefaultEncoderFactory.Builder(context)
            .setRequestedVideoEncoderSettings(
                VideoEncoderSettings.Builder().setBitrate(BITRATE).build()
            )
            .build()

        val transformer = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setEncoderFactory(encoders)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    running = null
                    if (!writePoster(video, poster)) {
                        video.delete()
                        result.error("poster_failed", "Couldn't read the first frame", null)
                        return
                    }
                    result.success(
                        mapOf("video" to video.absolutePath, "poster" to poster.absolutePath)
                    )
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    running = null
                    Log.w(TAG, "makeLoop failed", exportException)
                    video.delete()
                    result.error("export_failed", exportException.message, null)
                }
            })
            .build()

        running = transformer
        // Must start on a thread with a Looper; the method channel calls in on
        // the main one, which is where the listener then answers too.
        transformer.start(edited, video.absolutePath)
    }

    /**
     * Scales so the short side is [SHORT_SIDE], or null when the clip is
     * already that small. Worked out from the shown (rotated) size, because a
     * phone's portrait video is stored landscape with a rotation flag.
     */
    private fun scaleEffect(path: String): Presentation? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val w = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: return null
            val h = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: return null
            val rotation = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            val (shownW, shownH) = if (rotation % 180 == 0) w to h else h to w
            val shortSide = minOf(shownW, shownH)
            if (shortSide <= SHORT_SIDE) return null
            // Presentation sizes by output height; pick the height that lands
            // the short side on SHORT_SIDE. Even, as encoders require.
            val height = (shownH.toLong() * SHORT_SIDE / shortSide).toInt() and 1.inv()
            Presentation.createForHeight(height)
        } catch (e: Exception) {
            Log.w(TAG, "Couldn't read the clip's size; leaving it unscaled", e)
            null
        } finally {
            retriever.release()
        }
    }

    private fun writePoster(video: File, poster: File): Boolean {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(video.absolutePath)
            val frame = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: return false
            FileOutputStream(poster).use { frame.compress(Bitmap.CompressFormat.JPEG, 85, it) }
            frame.recycle()
            true
        } catch (e: Exception) {
            Log.w(TAG, "writePoster failed", e)
            false
        } finally {
            retriever.release()
        }
    }
}
