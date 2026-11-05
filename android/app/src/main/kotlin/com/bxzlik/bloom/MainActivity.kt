package com.bxzlik.bloom

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.Virtualizer
import android.os.Build
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * AudioServiceActivity, not FlutterActivity: otherwise audio_service can't
 * bring the activity up from the notification or the lock screen.
 */
class MainActivity : AudioServiceActivity() {

    /** System file dialogs (SAF): customization presets and own tracks. */
    private val files by lazy { FilesChannel(this) }

    private var pendingRecordPermissionResult: MethodChannel.Result? = null
    private var activeAudioRecord: AudioRecord? = null
    @Volatile
    private var isCapturingAudio = false

    private var nativeEqualizer: Equalizer? = null
    private var nativeBassBoost: BassBoost? = null
    private var nativeVirtualizer: Virtualizer? = null
    private var currentAudioSessionId: Int = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bloom/notifications",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Android 13+ hides the playback notification without this
                // permission. I show the dialog and answer at once: the user's
                // reply changes nothing in the player.
                "ensure" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                        result.success(true)
                    } else {
                        val granted = checkSelfPermission(
                            Manifest.permission.POST_NOTIFICATIONS,
                        ) == PackageManager.PERMISSION_GRANTED
                        if (!granted) {
                            requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                REQ_NOTIFICATIONS,
                            )
                        }
                        result.success(granted)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bloom/downloads",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // A downloaded track to shared storage (Music/Bloom). Dart
                // already wrote it to a file, so the path is enough: no need to
                // push megabytes through the channel.
                "save" -> saveToMusic(call, result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bloom/files",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveText" -> files.saveText(
                    filename = call.argument<String>("filename") ?: "bloom.json",
                    content = call.argument<String>("content").orEmpty(),
                    mime = call.argument<String>("mime") ?: "application/json",
                    result = result,
                )
                "openText" -> files.openText(result)
                // Own tracks: picking audio and giving back the permission on
                // an outside file.
                "pickAudio" -> files.pickAudio(
                    mode = call.argument<String>("mode") ?: "inPlace",
                    tracksDir = call.argument<String>("tracksDir").orEmpty(),
                    coversDir = call.argument<String>("coversDir").orEmpty(),
                    known = call.argument<List<String>>("known") ?: emptyList(),
                    result = result,
                )
                // A ready file to the system share sheet.
                "shareFile" -> files.shareFile(
                    path = call.argument<String>("path").orEmpty(),
                    mime = call.argument<String>("mime") ?: "image/png",
                    text = call.argument<String>("text"),
                    result = result,
                )
                "releaseAudio" -> files.releaseAudio(
                    uri = call.argument<String>("uri").orEmpty(),
                    result = result,
                )
                // The build version for the About row. Not worth a package for
                // two strings.
                "appInfo" -> appInfo(result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bloom/recognition",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> {
                    val granted = checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
                        PackageManager.PERMISSION_GRANTED
                    result.success(granted)
                }
                "requestPermission" -> {
                    val granted = checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
                        PackageManager.PERMISSION_GRANTED
                    if (granted) {
                        result.success(true)
                    } else {
                        pendingRecordPermissionResult = result
                        requestPermissions(
                            arrayOf(Manifest.permission.RECORD_AUDIO),
                            REQ_RECORD_AUDIO,
                        )
                    }
                }
                "captureAudio" -> {
                    val durationMs = call.argument<Int>("durationMs") ?: 6500
                    captureAudio(durationMs.toLong(), result)
                }
                "cancelCapture" -> {
                    cancelAudioCapture()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bloom/audio_fx",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "attach" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    attachAudioFx(sessionId)
                    result.success(true)
                }
                "apply" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val bandLevels = call.argument<List<Int>>("bandLevels") ?: emptyList()
                    val bassBoost = call.argument<Int>("bassBoost") ?: 0
                    val virtualizer = call.argument<Int>("virtualizer") ?: 0
                    applyAudioFx(enabled, bandLevels, bassBoost, virtualizer)
                    result.success(true)
                }
                "release" -> {
                    releaseAudioFx()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode == REQ_RECORD_AUDIO) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingRecordPermissionResult?.success(granted)
            pendingRecordPermissionResult = null
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    /**
     * A file dialog's answer. I take mine first and pass the rest to `super`,
     * or plugins like the image picker would lose their results.
     */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (files.onActivityResult(requestCode, resultCode, data)) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    /** Version name and build number from the manifest. */
    private fun appInfo(result: MethodChannel.Result) {
        try {
            val info = packageManager.getPackageInfo(packageName, 0)
            val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
            result.success(
                mapOf(
                    "version" to (info.versionName ?: ""),
                    "build" to code.toString(),
                    "device" to deviceName(),
                ),
            )
        } catch (e: Exception) {
            // My own package wasn't found. That never happens, and the screen
            // would just show a dash.
            result.success(null)
        }
    }

    /**
     * The phone's name in the computer's device list: the one from About phone,
     * else maker and model.
     */
    private fun deviceName(): String {
        val own = try {
            Settings.Global.getString(contentResolver, "device_name")
        } catch (e: Exception) {
            null
        }
        if (!own.isNullOrBlank()) return own
        val maker = Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
        return if (Build.MODEL.startsWith(Build.MANUFACTURER, ignoreCase = true)) Build.MODEL else "$maker ${Build.MODEL}"
    }

    /**
     * Copies a ready file to the media library. `deleteSource` is for a temp
     * download; an offline copy must stay, the player needs it.
     */
    private fun saveToMusic(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val filename = call.argument<String>("filename")
        if (sourcePath == null || filename == null) {
            result.error("args", "sourcePath and filename are required", null)
            return
        }
        val source = File(sourcePath)
        if (!source.isFile) {
            result.error("missing", "no file: $sourcePath", null)
            return
        }

        // Below Android 10 writing to a public folder needs a permission. I ask
        // and report a failure so the user retries: the answer comes later, and
        // I can't hold the result open for it.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                REQ_STORAGE,
            )
            result.error("permission", "no access to the phone's storage", null)
            return
        }

        try {
            val path = MediaStoreSaver.save(
                context = this,
                source = source,
                filename = filename,
                mime = call.argument<String>("mime") ?: "audio/mpeg",
                title = call.argument<String>("title"),
                artist = call.argument<String>("artist"),
            )
            if (call.argument<Boolean>("deleteSource") == true) source.delete()
            result.success(path)
        } catch (e: Exception) {
            result.error("save", e.message ?: "couldn't save", null)
        }
    }

    private fun captureAudio(durationMs: Long, result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            result.error("permission_denied", "RECORD_AUDIO not granted", null)
            return
        }

        Thread {
            val sampleRate = 16000
            val channelConfig = AudioFormat.CHANNEL_IN_MONO
            val audioFormat = AudioFormat.ENCODING_PCM_16BIT
            val minBufSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
            if (minBufSize <= 0) {
                runOnUiThread { result.error("init_failed", "Invalid buffer size", null) }
                return@Thread
            }

            val bufferSize = maxOf(minBufSize, 4096 * 2) * 2
            val record = try {
                AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    sampleRate,
                    channelConfig,
                    audioFormat,
                    bufferSize,
                )
            } catch (e: Exception) {
                runOnUiThread { result.error("init_failed", e.message, null) }
                return@Thread
            }

            if (record.state != AudioRecord.STATE_INITIALIZED) {
                record.release()
                runOnUiThread { result.error("init_failed", "AudioRecord not initialized", null) }
                return@Thread
            }

            activeAudioRecord = record
            isCapturingAudio = true

            val targetSampleCount = ((durationMs * sampleRate) / 1000L).toInt().coerceAtLeast(1)
            val outputBytes = ByteArray(targetSampleCount * 2)
            val chunk = ByteArray(4096)
            var bytesCaptured = 0

            try {
                record.startRecording()
                while (isCapturingAudio && bytesCaptured < outputBytes.size) {
                    val toRead = minOf(chunk.size, outputBytes.size - bytesCaptured)
                    val read = record.read(chunk, 0, toRead)
                    if (read < 0) {
                        break
                    }
                    if (read == 0) continue
                    System.arraycopy(chunk, 0, outputBytes, bytesCaptured, read)
                    bytesCaptured += read
                }
                record.stop()
            } catch (_: Exception) {
            } finally {
                record.release()
                activeAudioRecord = null
                isCapturingAudio = false
            }

            runOnUiThread {
                if (bytesCaptured > 0) {
                    val finalBytes = if (bytesCaptured == outputBytes.size) {
                        outputBytes
                    } else {
                        outputBytes.copyOf(bytesCaptured)
                    }
                    result.success(finalBytes)
                } else {
                    result.error("capture_failed", "No audio captured", null)
                }
            }
        }.start()
    }

    private fun cancelAudioCapture() {
        isCapturingAudio = false
        try {
            activeAudioRecord?.stop()
        } catch (_: Exception) {}
    }

    private fun attachAudioFx(sessionId: Int) {
        if (sessionId == 0 || sessionId == currentAudioSessionId) return
        releaseAudioFx()
        currentAudioSessionId = sessionId
        try {
            nativeEqualizer = Equalizer(0, sessionId).apply { enabled = false }
            nativeBassBoost = BassBoost(0, sessionId).apply { enabled = false }
            nativeVirtualizer = Virtualizer(0, sessionId).apply { enabled = false }
        } catch (_: Exception) {}
    }

    private fun applyAudioFx(
        enabled: Boolean,
        bandLevels: List<Int>,
        bassBoostStrength: Int,
        virtualizerStrength: Int,
    ) {
        try {
            val eq = nativeEqualizer
            if (eq != null) {
                eq.enabled = enabled
                if (enabled && bandLevels.isNotEmpty()) {
                    val numBands = eq.numberOfBands.toInt()
                    val range = eq.bandLevelRange
                    val minLevel = range[0].toInt()
                    val maxLevel = range[1].toInt()

                    val targetFreqs = intArrayOf(31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000)
                    for (band in 0 until numBands) {
                        val centerFreq = eq.getCenterFreq(band.toShort()) / 1000
                        var closestIndex = 0
                        var minDiff = Int.MAX_VALUE
                        for (i in targetFreqs.indices) {
                            val diff = kotlin.math.abs(targetFreqs[i] - centerFreq)
                            if (diff < minDiff) {
                                minDiff = diff
                                closestIndex = i
                            }
                        }
                        val level = if (closestIndex < bandLevels.size) bandLevels[closestIndex] else 0
                        val clampedLevel = level.coerceIn(minLevel, maxLevel).toShort()
                        eq.setBandLevel(band.toShort(), clampedLevel)
                    }
                }
            }

            val bb = nativeBassBoost
            if (bb != null) {
                bb.enabled = enabled && bassBoostStrength > 0
                if (bb.enabled) {
                    bb.setStrength(bassBoostStrength.coerceIn(0, 1000).toShort())
                }
            }

            val virt = nativeVirtualizer
            if (virt != null) {
                virt.enabled = enabled && virtualizerStrength > 0
                if (virt.enabled) {
                    virt.setStrength(virtualizerStrength.coerceIn(0, 1000).toShort())
                }
            }
        } catch (_: Exception) {}
    }

    private fun releaseAudioFx() {
        try {
            nativeEqualizer?.release()
            nativeEqualizer = null
            nativeBassBoost?.release()
            nativeBassBoost = null
            nativeVirtualizer?.release()
            nativeVirtualizer = null
            currentAudioSessionId = 0
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        releaseAudioFx()
        super.onDestroy()
    }

    private companion object {
        const val REQ_NOTIFICATIONS = 1001
        const val REQ_STORAGE = 1002
        const val REQ_RECORD_AUDIO = 1003
    }
}
