package com.bxzlik.bloom

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
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

    private companion object {
        const val REQ_NOTIFICATIONS = 1001
        const val REQ_STORAGE = 1002
    }
}
