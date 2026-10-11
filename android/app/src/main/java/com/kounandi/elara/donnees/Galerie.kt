package com.kounandi.elara.donnees

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/** Enregistre des médias d'Elara dans la galerie du téléphone (dossiers Movies/Elara et Music/Elara). */
object Galerie {
    /** Android 9 et moins demandent l'autorisation d'écrire dans le stockage. */
    val demandeAutorisation: Boolean get() = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    /** Renvoie le nombre de médias enregistrés. */
    suspend fun enregistrer(ctx: Context, medias: List<Media>): Int = withContext(Dispatchers.IO) {
        medias.count { media -> runCatching { enregistrerUn(ctx, media) }.getOrDefault(false) }
    }

    private fun enregistrerUn(ctx: Context, media: Media): Boolean {
        val source = Bibliotheque.fichier(media)
        val extension = source.extension.lowercase()
        val nom = media.nom.replace(Regex("[\\\\/:*?\"<>|]"), "_") + "." + extension
        val video = media.type == TypeMedia.VIDEO
        val mime = android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: if (video) "video/mp4" else "audio/mpeg"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val collection = if (video) MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            else MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val valeurs = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, nom)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, (if (video) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_MUSIC) + "/Elara")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = ctx.contentResolver
            val uri = resolver.insert(collection, valeurs) ?: return false
            return try {
                resolver.openOutputStream(uri)?.use { sortie -> source.inputStream().use { it.copyTo(sortie) } } ?: return false
                valeurs.clear()
                valeurs.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, valeurs, null, null)
                true
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                false
            }
        } else {
            @Suppress("DEPRECATION")
            val dossier = File(
                Environment.getExternalStoragePublicDirectory(if (video) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_MUSIC),
                "Elara",
            ).apply { mkdirs() }
            var cible = File(dossier, nom)
            var n = 2
            while (cible.exists()) cible = File(dossier, media.nom + " ($n)." + extension).also { n++ }
            source.copyTo(cible)
            MediaScannerConnection.scanFile(ctx, arrayOf(cible.absolutePath), arrayOf(mime), null)
            return true
        }
    }

    /** Télécharge une image (avec la connexion Facebook) et l'enregistre dans Pictures/Elara. */
    suspend fun enregistrerImage(ctx: Context, lien: String): Boolean = withContext(Dispatchers.IO) {
        runCatching {
            val c = java.net.URL(lien).openConnection() as java.net.HttpURLConnection
            c.connectTimeout = 20_000
            c.readTimeout = 30_000
            c.setRequestProperty("User-Agent", Telechargeur.AGENT_MOBILE)
            android.webkit.CookieManager.getInstance().getCookie(lien)?.let { c.setRequestProperty("Cookie", it) }
            val type = c.contentType?.substringBefore(';')?.trim() ?: "image/jpeg"
            val donnees = c.inputStream.use { it.readBytes() }
            c.disconnect()
            if (!type.startsWith("image/") && android.graphics.BitmapFactory.decodeByteArray(donnees, 0, donnees.size) == null) {
                return@runCatching false
            }
            val ext = when (type) { "image/png" -> "png"; "image/webp" -> "webp"; "image/gif" -> "gif"; else -> "jpg" }
            val nom = "Elara " + java.text.SimpleDateFormat("yyyy-MM-dd HH'h'mm'm'ss", java.util.Locale.ROOT).format(java.util.Date()) + "." + ext
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val valeurs = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, nom)
                    put(MediaStore.MediaColumns.MIME_TYPE, if (type.startsWith("image/")) type else "image/jpeg")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Elara")
                }
                val uri = ctx.contentResolver.insert(MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY), valeurs)
                    ?: return@runCatching false
                ctx.contentResolver.openOutputStream(uri)?.use { it.write(donnees) } ?: return@runCatching false
                true
            } else {
                @Suppress("DEPRECATION")
                val dossier = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "Elara").apply { mkdirs() }
                val f = File(dossier, nom)
                f.writeBytes(donnees)
                MediaScannerConnection.scanFile(ctx, arrayOf(f.absolutePath), null, null)
                true
            }
        }.getOrDefault(false)
    }
}
