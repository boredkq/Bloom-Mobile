package com.bxzlik.bloom

import android.app.Activity
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * System file dialogs: the presets file (SAF) and adding own tracks.
 *
 * SAF, not MediaStore: presets aren't media, the user picks where they go, and
 * no storage permission is needed on any Android version. It suits tracks too:
 * `ACTION_OPEN_DOCUMENT` grants just the picked file, so I never ask for
 * `READ_MEDIA_AUDIO`.
 *
 * I hold the channel's answer until `onActivityResult`, the only place the
 * dialog's result arrives. A second request while one is pending gets refused,
 * or the first `MethodChannel.Result` would never be answered.
 */
class FilesChannel(private val activity: Activity) {

    private var pending: MethodChannel.Result? = null
    private var pendingContent: String? = null

    /** What to do with picked audio: `inPlace` keeps the path, `copy` makes a copy. */
    private var audioMode = MODE_IN_PLACE
    private var audioTracksDir = ""
    private var audioCoversDir = ""

    /** Keys of tracks already added: I neither copy nor parse them. */
    private var audioKnown = HashSet<String>()

    /** Offers to save text as a file. Answers true/false. */
    fun saveText(
        filename: String,
        content: String,
        mime: String,
        result: MethodChannel.Result,
    ) {
        if (!claim(result)) return
        pendingContent = content
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mime
            putExtra(Intent.EXTRA_TITLE, filename)
        }
        start(intent, REQ_SAVE)
    }

    /**
     * Hands a ready file to the system share sheet.
     *
     * I answer right away: `ACTION_SEND` returns no result, and cancelling
     * looks the same as sending. Success here means the sheet was shown.
     */
    fun shareFile(path: String, mime: String, text: String?, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.isFile) {
            result.error("missing", "no file: $path", null)
            return
        }
        try {
            val uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.share",
                file,
            )
            val send = Intent(Intent.ACTION_SEND).apply {
                type = mime
                putExtra(Intent.EXTRA_STREAM, uri)
                if (!text.isNullOrEmpty()) putExtra(Intent.EXTRA_TEXT, text)
                // Without this the receiving app can't open the uri: it reads
                // my provider's file under its own identity.
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(Intent.createChooser(send, null))
            result.success(true)
        } catch (e: Exception) {
            result.error("share", e.message ?: "couldn't share", null)
        }
    }

    /** Lets the user pick a file and returns its text. */
    fun openText(result: MethodChannel.Result) {
        if (!claim(result)) return
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // `.bloompresets` has no registered type and `application/json`
            // would hide it, so I allow any file and Dart checks the format
            // when parsing.
            type = "*/*"
        }
        start(intent, REQ_OPEN)
    }

    /**
     * Lets the user pick audio files and returns ready track entries.
     *
     * The heavy work stays here, not in Dart: copying, reading tags, extracting
     * the cover. Only strings cross the channel; file and picture bytes stay on
     * disk.
     */
    fun pickAudio(
        mode: String,
        tracksDir: String,
        coversDir: String,
        known: List<String>,
        result: MethodChannel.Result,
    ) {
        if (!claim(result)) return
        audioMode = mode
        audioTracksDir = tracksDir
        audioCoversDir = coversDir
        audioKnown = HashSet(known)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // A wide type with the real list in EXTRA_MIME_TYPES: some
            // providers report flac and opus as binary, and `audio/*` alone
            // wouldn't let them be picked.
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, AUDIO_MIME)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        start(intent, REQ_AUDIO)
    }

    /**
     * Gives back the permission on an outside file when its track leaves the
     * library.
     *
     * Persisted permissions are capped (512 on Android 11+), and adding and
     * removing tracks would eventually hit the cap.
     */
    fun releaseAudio(uri: String, result: MethodChannel.Result) {
        try {
            activity.contentResolver.releasePersistableUriPermission(
                Uri.parse(uri),
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (_: Exception) {
            // The permission is already gone, which is what I wanted.
        }
        result.success(null)
    }

    /** `false` when the previous dialog hasn't answered and this request is refused. */
    private fun claim(result: MethodChannel.Result): Boolean {
        if (pending != null) {
            result.error("busy", "a file dialog is already open", null)
            return false
        }
        pending = result
        return true
    }

    private fun start(intent: Intent, request: Int) {
        try {
            activity.startActivityForResult(intent, request)
        } catch (e: Exception) {
            finish { it.error("dialog", e.message ?: "no file manager", null) }
        }
    }

    /** Answers Dart and forgets the request. */
    private fun finish(answer: (MethodChannel.Result) -> Unit) {
        val result = pending ?: return
        pending = null
        pendingContent = null
        answer(result)
    }

    /** Handles a system dialog's answer. `true` means the code was mine and needs no passing on. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQ_AUDIO) {
            val uris = if (resultCode == Activity.RESULT_OK) pickedUris(data) else emptyList()
            // Cancelling isn't an error: Dart tells it by null.
            if (uris.isEmpty()) {
                finish { it.success(null) }
            } else {
                importAudio(uris)
            }
            return true
        }
        if (requestCode != REQ_SAVE && requestCode != REQ_OPEN) return false
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            // Cancelling isn't an error: Dart tells it by false/null.
            finish { if (requestCode == REQ_SAVE) it.success(false) else it.success(null) }
            return true
        }
        try {
            if (requestCode == REQ_SAVE) {
                val content = pendingContent.orEmpty()
                activity.contentResolver.openOutputStream(uri, "wt")?.use { out ->
                    out.write(content.toByteArray(Charsets.UTF_8))
                } ?: throw IllegalStateException("couldn't open the file for writing")
                finish { it.success(true) }
            } else {
                val text = activity.contentResolver.openInputStream(uri)?.use { input ->
                    input.readBytes().toString(Charsets.UTF_8)
                } ?: throw IllegalStateException("couldn't read the file")
                finish { it.success(text) }
            }
        } catch (e: Exception) {
            finish { it.error("io", e.message ?: "file error", null) }
        }
        return true
    }

    /** Picked files: one in `data`, several in `clipData`. */
    private fun pickedUris(data: Intent?): List<Uri> {
        if (data == null) return emptyList()
        val clip = data.clipData
        if (clip != null) {
            return (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
        }
        return listOfNotNull(data.data)
    }

    /**
     * Parses the picks and answers Dart. On its own thread: copying and reading
     * tags hit the disk, and this is the main thread the app draws on.
     */
    private fun importAudio(uris: List<Uri>) {
        val mode = audioMode
        val tracksDir = File(audioTracksDir)
        val coversDir = File(audioCoversDir)
        val known = audioKnown
        Thread {
            val out = ArrayList<HashMap<String, Any?>>()
            for (uri in uris) {
                try {
                    val entry = importOne(uri, mode, tracksDir, coversDir, known)
                    if (entry != null) out.add(entry)
                } catch (_: Exception) {
                    // I skip non-audio and unreadable files silently: one bad
                    // file shouldn't fail a whole batch.
                }
            }
            activity.runOnUiThread { finish { it.success(out) } }
        }.start()
    }

    /** `null` if the file is already in the library or isn't audio. */
    private fun importOne(
        uri: Uri,
        mode: String,
        tracksDir: File,
        coversDir: File,
        known: HashSet<String>,
    ): HashMap<String, Any?>? {
        val name = displayName(uri)
        val size = fileSize(uri)

        // "In place" relies on a persisted permission: without one a
        // `content://` uri dies with this run. If it's refused I copy instead,
        // or the track would stop playing after a restart.
        val persisted = mode == MODE_IN_PLACE && takePersistable(uri)
        val key = if (persisted) uri.toString() else "$name|$size"
        // I add the key right away: it also drops duplicates within one batch.
        if (!known.add(key)) return null

        var copy: File? = null
        if (!persisted) {
            copy = copyInto(tracksDir, uri, name) ?: run {
                known.remove(key)
                return null
            }
        }

        val retriever = MediaMetadataRetriever()
        try {
            if (copy != null) {
                retriever.setDataSource(copy.absolutePath)
            } else {
                retriever.setDataSource(activity, uri)
            }
            val entry = HashMap<String, Any?>()
            entry["key"] = key
            entry["name"] = name
            entry["size"] = size
            if (persisted) entry["uri"] = uri.toString() else entry["file"] = copy?.name
            entry["durationMs"] =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull() ?: 0L
            entry["title"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)
            // Compilations have an empty track artist and a filled album one.
            entry["artist"] =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
                    ?: retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST)
            entry["album"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)
            entry["year"] =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_YEAR)
                    ?: retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DATE)
            entry["genre"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_GENRE)
            entry["cover"] = saveCover(retriever.embeddedPicture, coversDir)
            return entry
        } catch (e: Exception) {
            // It didn't open as audio, so I remove the copy.
            copy?.delete()
            known.remove(key)
            throw e
        } finally {
            retriever.release()
        }
    }

    /** A persisted read permission on an outside file. `false` if refused. */
    private fun takePersistable(uri: Uri): Boolean = try {
        activity.contentResolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION,
        )
        true
    } catch (_: Exception) {
        false
    }

    private fun displayName(uri: Uri): String {
        activity.contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) return cursor.getString(0)
            }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "audio"
    }

    private fun fileSize(uri: Uri): Long {
        activity.contentResolver
            .query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) return cursor.getLong(0)
            }
        return 0L
    }

    /** A copy inside the app. `null` if copying failed. */
    private fun copyInto(dir: File, uri: Uri, name: String): File? = try {
        dir.mkdirs()
        val dest = uniqueFile(dir, safeName(name))
        activity.contentResolver.openInputStream(uri)?.use { input ->
            dest.outputStream().use { out -> input.copyTo(out) }
        } ?: throw IllegalStateException("couldn't read the file")
        dest
    } catch (_: Exception) {
        null
    }

    /** `Song.mp3`, `Song (2).mp3`, `Song (3).mp3`… */
    private fun uniqueFile(dir: File, name: String): File {
        var candidate = File(dir, name)
        if (!candidate.exists()) return candidate
        val stem = name.substringBeforeLast('.', name)
        val ext = name.substringAfterLast('.', "").let { if (it.isEmpty()) "" else ".$it" }
        var n = 2
        while (candidate.exists()) {
            candidate = File(dir, "$stem ($n)$ext")
            n++
        }
        return candidate
    }

    private fun safeName(name: String): String {
        val clean = name.replace(Regex("""[\\/:*?"<>|]+"""), "_").trim()
        return if (clean.isEmpty()) "audio" else clean.take(120)
    }

    /** Saves an embedded cover to the covers folder; `null` if there's none or the write failed. */
    private fun saveCover(bytes: ByteArray?, dir: File): String? {
        if (bytes == null || bytes.isEmpty()) return null
        return try {
            dir.mkdirs()
            // The extension is only nominal: Flutter recognizes the picture by
            // its bytes (tags almost always hold JPEG).
            val name = "lt_${System.currentTimeMillis()}_${coverSeq++}.jpg"
            File(dir, name).writeBytes(bytes)
            name
        } catch (_: Exception) {
            null
        }
    }

    /** Keeps apart the names of covers written in the same millisecond. */
    private var coverSeq = 0

    private companion object {
        const val REQ_SAVE = 1101
        const val REQ_OPEN = 1102
        const val REQ_AUDIO = 1103

        const val MODE_IN_PLACE = "inPlace"

        val AUDIO_MIME = arrayOf(
            "audio/*",
            // Containers that providers often don't report as audio.
            "application/ogg",
            "application/x-flac",
            "application/octet-stream",
        )
    }
}
