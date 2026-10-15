package com.kounandi.elara.donnees

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** Tous les médias d'Elara, rangés dans le stockage privé de l'app. */
object Bibliotheque {
    private lateinit var contexte: Context
    private lateinit var racine: File

    private val _medias = MutableStateFlow<List<Media>>(emptyList())
    val medias: StateFlow<List<Media>> = _medias
    private val _dossiers = MutableStateFlow<List<Dossier>>(emptyList())
    val dossiers: StateFlow<List<Dossier>> = _dossiers

    /** Dernier fichier refusé car déjà présent (affiché quelques secondes : « Déjà dans Elara »). */
    private val _doublon = MutableStateFlow<Media?>(null)
    val doublon: StateFlow<Media?> = _doublon

    private val extensionsVideo = setOf("mp4", "mov", "m4v", "3gp", "mkv", "webm", "avi", "ts")
    private val extensionsAudio = setOf("mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "amr")

    fun init(ctx: Context) {
        contexte = ctx.applicationContext
        racine = contexte.filesDir
        File(racine, "medias").mkdirs()
        File(racine, "prive").mkdirs()
        charger()
    }

    private val index get() = File(racine, "bibliotheque.json")

    private fun charger() {
        if (!index.exists()) return
        runCatching {
            val o = JSONObject(index.readText())
            val m = o.optJSONArray("medias") ?: JSONArray()
            val d = o.optJSONArray("dossiers") ?: JSONArray()
            _medias.value = (0 until m.length()).map { Media.depuis(m.getJSONObject(it)) }
                .filter { fichier(it).exists() }
            _dossiers.value = (0 until d.length()).map { Dossier.depuis(d.getJSONObject(it)) }
        }
    }

    @Synchronized
    private fun sauver() {
        val o = JSONObject()
            .put("medias", JSONArray(_medias.value.map { it.json() }))
            .put("dossiers", JSONArray(_dossiers.value.map { it.json() }))
        val tmp = File(racine, "bibliotheque.json.tmp")
        tmp.writeText(o.toString())
        tmp.renameTo(index)
    }

    fun fichier(media: Media): File = File(File(racine, if (media.prive) "prive" else "medias"), media.fichier)

    fun media(id: String): Media? = _medias.value.firstOrNull { it.id == id }

    fun type(extension: String): TypeMedia? = when (extension.lowercase()) {
        in extensionsVideo -> TypeMedia.VIDEO
        in extensionsAudio -> TypeMedia.AUDIO
        else -> null
    }

    // MARK: Import

    /** Copie un fichier choisi (Photos, Fichiers, partage) dans Elara. */
    suspend fun importer(uri: Uri, prive: Boolean = false, dossier: String? = null): Media? = withContext(Dispatchers.IO) {
        val resolver = contexte.contentResolver
        var nom = "Média"
        runCatching {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0)?.let { nom = it }
            }
        }
        var extension = nom.substringAfterLast('.', "").lowercase()
        val mime = resolver.getType(uri)
        if (type(extension) == null && mime != null) {
            MimeTypeMap.getSingleton().getExtensionFromMimeType(mime)?.let { extension = it }
            if (extension.isEmpty()) extension = if (mime.startsWith("audio")) "m4a" else "mp4"
        }
        val sorte = type(extension) ?: when {
            mime?.startsWith("audio") == true -> TypeMedia.AUDIO
            mime?.startsWith("video") == true -> TypeMedia.VIDEO
            else -> return@withContext null
        }
        val id = UUID.randomUUID().toString()
        val dest = File(File(racine, if (prive) "prive" else "medias"), "$id.$extension")
        val ok = runCatching {
            resolver.openInputStream(uri)?.use { entree -> dest.outputStream().use { entree.copyTo(it) } } != null
        }.getOrDefault(false)
        if (!ok) { dest.delete(); return@withContext null }
        doublonDe(dest)?.let { existant ->
            dest.delete()
            signalerDoublon(existant)
            return@withContext existant
        }
        ajouter(dest, nom.substringBeforeLast('.'), sorte, prive, dossier, id)
    }

    /** Ajoute un fichier déjà téléchargé (il est déplacé dans Elara). */
    suspend fun importerFichier(source: File, nom: String, prive: Boolean): Media? = withContext(Dispatchers.IO) {
        val extension = source.extension.lowercase().ifEmpty { "mp4" }
        val sorte = type(extension) ?: return@withContext null
        doublonDe(source)?.let { existant ->
            source.delete()
            signalerDoublon(existant)
            return@withContext existant
        }
        val id = UUID.randomUUID().toString()
        val dest = File(File(racine, if (prive) "prive" else "medias"), "$id.$extension")
        if (!source.renameTo(dest)) {
            source.copyTo(dest, overwrite = true)
            source.delete()
        }
        ajouter(dest, nom, sorte, prive, null, id)
    }

    private fun ajouter(fichier: File, nom: String, sorte: TypeMedia, prive: Boolean, dossier: String?, id: String): Media {
        val duree = runCatching {
            MediaMetadataRetriever().run {
                setDataSource(fichier.absolutePath)
                val d = extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                release()
                d
            }
        }.getOrDefault(0L)
        val media = Media(
            id = id, nom = nomLibre(nom), fichier = fichier.name, type = sorte, duree = duree,
            taille = fichier.length(), dossier = dossier, prive = prive, position = 0, date = System.currentTimeMillis(),
            empreinte = empreinte(fichier),
        )
        _medias.value = listOf(media) + _medias.value
        sauver()
        return media
    }

    /** « Vidéo », « Vidéo (2) », « Vidéo (3) »… */
    private fun nomLibre(nom: String): String {
        val noms = _medias.value.map { it.nom }.toSet()
        if (nom !in noms) return nom
        var n = 2
        while ("$nom ($n)" in noms) n++
        return "$nom ($n)"
    }

    // MARK: Modifications

    private fun modifier(id: String, transformation: (Media) -> Media) {
        _medias.value = _medias.value.map { if (it.id == id) transformation(it) else it }
        sauver()
    }

    fun renommer(media: Media, nom: String) {
        val propre = nom.trim()
        if (propre.isNotEmpty()) modifier(media.id) { it.copy(nom = propre) }
    }

    fun deplacer(media: Media, dossier: String?) = modifier(media.id) { it.copy(dossier = dossier) }

    /** Remplace le fichier d'un média par une nouvelle version (filigrane masqué…) ; nom, dossier et position sont gardés. */
    suspend fun remplacerFichier(media: Media, source: File): Boolean = withContext(Dispatchers.IO) {
        val ancien = fichier(media)
        val dest = File(ancien.parentFile, media.id + "-" + UUID.randomUUID().toString().take(6) + ".mp4")
        val ok = source.renameTo(dest) || runCatching { source.copyTo(dest, overwrite = true); source.delete(); true }.getOrDefault(false)
        if (!ok) return@withContext false
        ancien.delete()
        miniature(media).delete()
        withContext(Dispatchers.Main) {
            modifier(media.id) { it.copy(fichier = dest.name, taille = dest.length(), empreinte = empreinte(dest)) }
        }
        true
    }

    fun memoriserPosition(id: String, position: Long) {
        val actuel = media(id) ?: return
        if (actuel.position == position) return
        modifier(id) { it.copy(position = position) }
    }

    /** Range un média dans le dossier privé, ou l'en sort. */
    fun basculerPrive(media: Media) {
        val avant = fichier(media)
        val apres = media.copy(prive = !media.prive, dossier = null)
        val dest = fichier(apres)
        if (avant.renameTo(dest)) modifier(media.id) { apres }
    }

    fun supprimer(media: Media) {
        fichier(media).delete()
        miniature(media).delete()
        _medias.value = _medias.value.filterNot { it.id == media.id }
        sauver()
    }

    fun creerDossier(nom: String): Dossier? {
        val propre = nom.trim().take(Dossier.LONGUEUR_MAX)
        if (propre.isEmpty()) return null
        val dossier = Dossier(UUID.randomUUID().toString(), propre)
        _dossiers.value = _dossiers.value + dossier
        sauver()
        return dossier
    }

    fun renommerDossier(dossier: Dossier, nom: String) {
        val propre = nom.trim().take(Dossier.LONGUEUR_MAX)
        if (propre.isEmpty()) return
        _dossiers.value = _dossiers.value.map { if (it.id == dossier.id) it.copy(nom = propre) else it }
        sauver()
    }

    /** Supprime le dossier ; ses médias reviennent à l'accueil. */
    fun supprimerDossier(dossier: Dossier) {
        _dossiers.value = _dossiers.value.filterNot { it.id == dossier.id }
        _medias.value = _medias.value.map { if (it.dossier == dossier.id) it.copy(dossier = null) else it }
        sauver()
    }

    // MARK: Doublons

    /** Taille + SHA-256 du début et de la fin du fichier : rapide, et identique pour deux copies. */
    private fun empreinte(f: File): String? = runCatching {
        val morceau = 1 shl 20
        val taille = f.length()
        val md = java.security.MessageDigest.getInstance("SHA-256")
        java.io.RandomAccessFile(f, "r").use { raf ->
            val tampon = ByteArray(morceau)
            val n = raf.read(tampon, 0, minOf(morceau.toLong(), taille).toInt())
            if (n > 0) md.update(tampon, 0, n)
            if (taille > morceau * 2L) {
                raf.seek(taille - morceau)
                val m = raf.read(tampon, 0, morceau)
                if (m > 0) md.update(tampon, 0, m)
            }
        }
        "$taille-" + md.digest().joinToString("") { "%02x".format(it) }
    }.getOrNull()

    private fun empreinteDe(media: Media): String? {
        media.empreinte?.let { return it }
        val e = empreinte(fichier(media)) ?: return null
        _medias.value = _medias.value.map { if (it.id == media.id) it.copy(empreinte = e) else it }
        sauver()
        return e
    }

    /** Média déjà présent avec exactement le même contenu. */
    private fun doublonDe(f: File): Media? {
        val taille = f.length()
        val candidats = _medias.value.filter { it.taille == taille }
        if (candidats.isEmpty()) return null
        val e = empreinte(f) ?: return null
        return candidats.firstOrNull { empreinteDe(it) == e }
    }

    private fun signalerDoublon(media: Media) {
        _doublon.value = media
        kotlinx.coroutines.MainScope().launch {
            kotlinx.coroutines.delay(4000)
            if (_doublon.value?.id == media.id) _doublon.value = null
        }
    }

    /** Supprime les copies en double (garde la plus ancienne). Renvoie le nombre supprimé. */
    suspend fun supprimerDoublons(): Int = withContext(Dispatchers.IO) {
        var supprimes = 0
        _medias.value.groupBy { it.taille }.values.filter { it.size > 1 }.forEach { groupe ->
            val vus = mutableSetOf<String>()
            groupe.sortedBy { it.date }.forEach { m ->
                val e = empreinteDe(m) ?: return@forEach
                if (!vus.add(e)) {
                    withContext(Dispatchers.Main) { supprimer(m) }
                    supprimes++
                }
            }
        }
        supprimes
    }

    // MARK: Miniatures

    private fun miniature(media: Media) = File(File(contexte.cacheDir, "miniatures").apply { mkdirs() }, "${media.id}.jpg")

    /** Image de la vidéo (créée une seule fois puis gardée en cache). */
    suspend fun miniature(media: Media, largeur: Int = 320): File? = withContext(Dispatchers.IO) {
        if (media.type != TypeMedia.VIDEO) return@withContext null
        val cache = miniature(media)
        if (cache.exists()) return@withContext cache
        runCatching {
            val r = MediaMetadataRetriever()
            r.setDataSource(fichier(media).absolutePath)
            val moment = (media.duree * 1000L / 10).coerceAtLeast(0)
            val image = if (android.os.Build.VERSION.SDK_INT >= 27) {
                r.getScaledFrameAtTime(moment, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, largeur, largeur * 9 / 16)
            } else {
                r.getFrameAtTime(moment, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            } ?: r.frameAtTime
            r.release()
            image?.let { bmp ->
                cache.outputStream().use { bmp.compress(Bitmap.CompressFormat.JPEG, 80, it) }
                cache
            }
        }.getOrNull()
    }
}
