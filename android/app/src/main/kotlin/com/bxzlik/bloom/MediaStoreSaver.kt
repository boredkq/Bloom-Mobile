package com.bxzlik.bloom

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/**
 * Saves a downloaded track to the phone's shared storage, Music/Bloom.
 *
 * Unlike the offline copy inside the app, this file sits in the media library:
 * other players see it and it outlives the app.
 *
 * Two paths, because Android 10 changed storage. From 10 on it's MediaStore: my
 * own folder inside Music, no permissions. Below that it's a plain File in the
 * public folder with WRITE_EXTERNAL_STORAGE, and the scanner has to be told or
 * players won't see it.
 */
object MediaStoreSaver {

    /** The subfolder inside Music, so my files don't get lost among others. */
    private const val FOLDER = "Bloom"

    /**
     * Puts [source] in the media library as [filename].
     *
     * [title]/[artist] go to media library fields: a CDN file may have no tags,
     * and players would show "Unknown". Returns the path to show the user.
     */
    fun save(
        context: Context,
        source: File,
        filename: String,
        mime: String,
        title: String?,
        artist: String?,
    ): String {
        // A cover takes the same route into Pictures: the gallery wouldn't show
        // it from Music.
        if (mime.startsWith("image/")) {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saveImageViaMediaStore(context, source, filename, mime)
            } else {
                saveViaPublicDir(context, source, filename, Environment.DIRECTORY_PICTURES)
            }
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(context, source, filename, mime, title, artist)
        } else {
            saveViaPublicDir(context, source, filename, Environment.DIRECTORY_MUSIC)
        }
    }

    private fun saveImageViaMediaStore(
        context: Context,
        source: File,
        filename: String,
        mime: String,
    ): String {
        val resolver = context.contentResolver
        val relative = Environment.DIRECTORY_PICTURES + File.separator + FOLDER
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, filename)
            put(MediaStore.Images.Media.MIME_TYPE, mime)
            put(MediaStore.Images.Media.RELATIVE_PATH, relative)
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val collection = MediaStore.Images.Media.getContentUri(
            MediaStore.VOLUME_EXTERNAL_PRIMARY,
        )
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("the media library refused the write")
        try {
            resolver.openOutputStream(uri).use { out ->
                out ?: throw IllegalStateException("couldn't open the write stream")
                source.inputStream().use { it.copyTo(out) }
            }
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        values.clear()
        values.put(MediaStore.Images.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return relative + File.separator + filename
    }

    private fun saveViaMediaStore(
        context: Context,
        source: File,
        filename: String,
        mime: String,
        title: String?,
        artist: String?,
    ): String {
        val resolver = context.contentResolver
        val relative = Environment.DIRECTORY_MUSIC + File.separator + FOLDER
        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, filename)
            put(MediaStore.Audio.Media.MIME_TYPE, mime)
            put(MediaStore.Audio.Media.RELATIVE_PATH, relative)
            if (!title.isNullOrEmpty()) put(MediaStore.Audio.Media.TITLE, title)
            if (!artist.isNullOrEmpty()) put(MediaStore.Audio.Media.ARTIST, artist)
            // The file stays hidden from other apps while being written, or a
            // player could index half a track.
            put(MediaStore.Audio.Media.IS_PENDING, 1)
        }

        val collection = MediaStore.Audio.Media.getContentUri(
            MediaStore.VOLUME_EXTERNAL_PRIMARY,
        )
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("the media library refused the write")

        try {
            resolver.openOutputStream(uri).use { out ->
                out ?: throw IllegalStateException("couldn't open the write stream")
                source.inputStream().use { it.copyTo(out) }
            }
        } catch (e: Exception) {
            // A half-written file mustn't stay in the media library.
            resolver.delete(uri, null, null)
            throw e
        }

        values.clear()
        values.put(MediaStore.Audio.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return relative + File.separator + filename
    }

    private fun saveViaPublicDir(
        context: Context,
        source: File,
        filename: String,
        publicDir: String,
    ): String {
        val dir = File(
            Environment.getExternalStoragePublicDirectory(publicDir),
            FOLDER,
        )
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("couldn't create folder ${dir.path}")
        }
        val target = uniqueFile(dir, filename)
        source.inputStream().use { input ->
            target.outputStream().use { input.copyTo(it) }
        }
        // Without the scanner the file is on disk but never shows up in
        // players.
        MediaScannerConnection.scanFile(context, arrayOf(target.path), null, null)
        return target.path
    }

    /** `Name.mp3`, `Name (2).mp3`, …: two tracks can share a name. */
    private fun uniqueFile(dir: File, filename: String): File {
        val dot = filename.lastIndexOf('.')
        val base = if (dot > 0) filename.substring(0, dot) else filename
        val ext = if (dot > 0) filename.substring(dot) else ""
        var candidate = File(dir, filename)
        var i = 2
        while (candidate.exists()) {
            candidate = File(dir, "$base ($i)$ext")
            i++
        }
        return candidate
    }
}
