package com.kounandi.elara.donnees

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.webkit.CookieManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.kounandi.elara.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLDecoder
import java.nio.ByteBuffer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

class ErreurTelechargement(message: String) : Exception(message)

/**
 * Télécharge une vidéo ou une musique depuis un lien direct,
 * ou depuis Facebook (vidéos publiques ou visibles par le compte connecté dans Elara).
 * Les plateformes de streaming et les autres réseaux sociaux sont refusés.
 */
object Telechargeur {
    var enCours by mutableStateOf(false); private set
    var recherche by mutableStateOf(false); private set
    var progression by mutableFloatStateOf(0f); private set
    var octets by mutableLongStateOf(0L); private set

    @Volatile private var annule = false

    const val AGENT_MOBILE = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Mobile Safari/537.36"
    const val AGENT_ORDINATEUR = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36"

    private val facebook = listOf("facebook.com", "fb.watch", "fb.com", "fb.gg")
    private val refuses = listOf(
        "youtube.com", "youtu.be", "tiktok.com", "instagram.com", "twitter.com", "x.com", "netflix.com",
        "dailymotion.com", "vimeo.com", "spotify.com", "deezer.com", "snapchat.com", "primevideo.com", "disneyplus.com",
    )

    fun estFacebook(hote: String) = facebook.any { hote == it || hote.endsWith(".$it") }
    private fun estRefuse(hote: String) = refuses.any { hote == it || hote.endsWith(".$it") }

    fun annuler() { annule = true }

    private fun nomFacebook(): String =
        "Facebook " + SimpleDateFormat("yyyy-MM-dd HH'h'mm", Locale.ROOT).format(Date())

    /** Lien collé ou partagé. */
    suspend fun telecharger(ctx: Context, texte: String, prive: Boolean, sons: List<String> = emptyList()): Media {
        val lien = texte.trim()
        val url = runCatching { URL(lien) }.getOrNull()
        if (url == null || (url.protocol != "http" && url.protocol != "https")) {
            throw ErreurTelechargement(ctx.getString(R.string.erreur_lien_invalide))
        }
        val hote = url.host.lowercase()
        if (estRefuse(hote)) throw ErreurTelechargement(ctx.getString(R.string.erreur_plateforme))
        commencer()
        try {
            var cible = lien
            var nom: String? = null
            if (estFacebook(hote)) {
                recherche = true
                cible = ExtracteurFacebook.lienVideo(lien) ?: throw ErreurTelechargement(ctx.getString(R.string.erreur_facebook))
                recherche = false
                nom = nomFacebook()
            } else if (hote.endsWith("fbcdn.net")) {
                nom = nomFacebook()
            }
            var fichier = telechargerBrut(ctx, cible, 0f, if (sons.isEmpty()) 1f else 0.8f)
            // Vidéo sans son (Facebook sépare souvent l'image et le son) : on ajoute le son.
            if (sons.isNotEmpty()) {
                val (image, son) = withContext(Dispatchers.IO) { pistes(fichier) }
                if (image && !son) {
                    for (lienSon in sons) {
                        val audio = runCatching { telechargerBrut(ctx, lienSon, 0.8f, 0.2f) }.getOrNull() ?: continue
                        val sortie = File(dossierTemp(ctx), UUID.randomUUID().toString() + ".mp4")
                        val ok = withContext(Dispatchers.IO) {
                            pistes(audio).second && runCatching { fusionner(fichier, audio, sortie) }.getOrDefault(false)
                        }
                        audio.delete()
                        if (ok) { fichier.delete(); fichier = sortie; break } else sortie.delete()
                    }
                }
            }
            val type = Bibliotheque.type(fichier.extension)
            if (type == null) {
                fichier.delete()
                throw ErreurTelechargement(ctx.getString(R.string.erreur_pas_media))
            }
            return Bibliotheque.importerFichier(fichier, nom ?: nomDepuis(cible), prive)
                ?: throw ErreurTelechargement(ctx.getString(R.string.erreur_ajout))
        } finally {
            finir()
        }
    }

    /**
     * Reels : l'image et le son arrivent souvent en deux fichiers. On télécharge les derniers
     * fichiers vus pendant la lecture, on garde celui qui a l'image et celui qui a le son, puis on les assemble.
     */
    suspend fun telechargerFlux(ctx: Context, candidats: List<String>, prive: Boolean): Media {
        commencer()
        val temporaires = mutableListOf<File>()
        try {
            var complet: File? = null
            var image: File? = null
            var son: File? = null
            val part = 1f / candidats.size.coerceAtLeast(1)
            for ((rang, lien) in candidats.withIndex()) {
                if (annule) throw ErreurTelechargement(ctx.getString(R.string.telechargement_annule))
                val f = runCatching { telechargerBrut(ctx, lien, rang * part, part) }.getOrNull() ?: continue
                temporaires += f
                val (v, a) = withContext(Dispatchers.IO) { pistes(f) }
                if (v && a) { complet = f; break }
                if (v && image == null) image = f else if (a && son == null) son = f
                if (image != null && son != null) break
            }
            val im = image
            val so = son
            var resultat: File? = complet ?: im ?: so
            if (complet == null && im != null && so != null) {
                val sortie = File(dossierTemp(ctx), UUID.randomUUID().toString() + ".mp4")
                val ok = withContext(Dispatchers.IO) { runCatching { fusionner(im, so, sortie) }.getOrDefault(false) }
                if (ok) {
                    temporaires += sortie
                    resultat = sortie
                }
            }
            val choisi = resultat ?: throw ErreurTelechargement(ctx.getString(R.string.erreur_introuvable))
            val mp4 = File(dossierTemp(ctx), UUID.randomUUID().toString() + ".mp4")
            choisi.renameTo(mp4)
            return Bibliotheque.importerFichier(mp4, nomFacebook(), prive)
                ?: throw ErreurTelechargement(ctx.getString(R.string.erreur_ajout))
        } finally {
            temporaires.forEach { it.delete() }
            finir()
        }
    }

    private fun commencer() {
        annule = false
        enCours = true
        recherche = false
        progression = 0f
        octets = 0L
    }

    private fun finir() {
        enCours = false
        recherche = false
    }

    private fun dossierTemp(ctx: Context) = File(ctx.cacheDir, "telechargements").apply { mkdirs() }

    private fun nomDepuis(lien: String): String {
        val brut = runCatching { URLDecoder.decode(URL(lien).path.substringAfterLast('/'), "UTF-8") }.getOrDefault("")
        return brut.substringBeforeLast('.').ifBlank { "Téléchargement" }
    }

    /** Télécharge dans le cache en suivant la progression. */
    private suspend fun telechargerBrut(
        ctx: Context, lien: String, base: Float, part: Float,
        entetes: Map<String, String> = emptyMap(),
    ): File = withContext(Dispatchers.IO) {
        var adresse = lien
        var connexion = ouvrir(adresse, entetes)
        var redirections = 0
        while (connexion.responseCode in 300..399 && redirections < 8) {
            val suite = connexion.getHeaderField("Location") ?: break
            adresse = URL(URL(adresse), suite).toString()
            connexion.disconnect()
            connexion = ouvrir(adresse, entetes)
            redirections++
        }
        val code = connexion.responseCode
        if (code !in 200..299) {
            connexion.disconnect()
            throw ErreurTelechargement(ctx.getString(R.string.erreur_serveur, code))
        }
        val total = connexion.contentLengthLong
        val ext = extension(adresse, connexion.contentType, connexion.getHeaderField("Content-Disposition"))
        val dest = File(dossierTemp(ctx), UUID.randomUUID().toString() + "." + ext)
        try {
            connexion.inputStream.use { entree ->
                dest.outputStream().use { sortie ->
                    val tampon = ByteArray(64 * 1024)
                    var recu = 0L
                    while (true) {
                        if (annule) throw ErreurTelechargement(ctx.getString(R.string.telechargement_annule))
                        val n = entree.read(tampon)
                        if (n < 0) break
                        sortie.write(tampon, 0, n)
                        recu += n
                        octets = recu
                        if (total > 0) progression = base + part * (recu.toFloat() / total)
                    }
                }
            }
        } catch (e: Exception) {
            dest.delete()
            throw e
        } finally {
            connexion.disconnect()
        }
        dest
    }

    private fun ouvrir(adresse: String, entetes: Map<String, String> = emptyMap()): HttpURLConnection {
        val c = URL(adresse).openConnection() as HttpURLConnection
        c.instanceFollowRedirects = false
        c.connectTimeout = 20_000
        c.readTimeout = 30_000
        c.setRequestProperty("User-Agent", AGENT_MOBILE)
        CookieManager.getInstance().getCookie(adresse)?.let { c.setRequestProperty("Cookie", it) }
        entetes.forEach { (k, v) -> c.setRequestProperty(k, v) }
        return c
    }

    /** Vidéo TikTok (onglet TikTok) : le fichier demande la connexion TikTok et la page d'origine. */
    suspend fun telechargerTikTok(ctx: Context, lien: String, prive: Boolean): Media {
        commencer()
        try {
            val cookies = CookieManager.getInstance().getCookie("https://www.tiktok.com") ?: ""
            val entetes = mapOf(
                "Referer" to "https://www.tiktok.com/",
                "Origin" to "https://www.tiktok.com",
                "Cookie" to cookies,
                "Range" to "bytes=0-",
            )
            val f = telechargerBrut(ctx, lien, 0f, 1f, entetes)
            val mp4 = File(f.parentFile, UUID.randomUUID().toString() + ".mp4")
            f.renameTo(mp4)
            val nom = "TikTok " + SimpleDateFormat("yyyy-MM-dd HH'h'mm", Locale.ROOT).format(Date())
            return Bibliotheque.importerFichier(mp4, nom, prive)
                ?: throw ErreurTelechargement(ctx.getString(R.string.erreur_ajout))
        } finally {
            finir()
        }
    }

    private fun extension(lien: String, type: String?, disposition: String?): String {
        val connues = setOf("mp4", "mov", "m4v", "3gp", "mkv", "webm", "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus")
        disposition?.let { Regex("filename\\*?=\"?([^\";]+)").find(it)?.groupValues?.get(1) }
            ?.substringAfterLast('.', "")?.lowercase()?.let { if (it in connues) return it }
        val chemin = runCatching { URL(lien).path }.getOrDefault("").substringAfterLast('.', "").lowercase()
        if (chemin in connues) return chemin
        return when (type?.substringBefore(';')?.trim()?.lowercase()) {
            "video/mp4" -> "mp4"
            "video/quicktime" -> "mov"
            "video/webm" -> "webm"
            "video/x-matroska" -> "mkv"
            "video/3gpp" -> "3gp"
            "audio/mpeg", "audio/mp3" -> "mp3"
            "audio/mp4", "audio/x-m4a" -> "m4a"
            "audio/aac" -> "aac"
            "audio/wav", "audio/x-wav" -> "wav"
            "audio/flac" -> "flac"
            "audio/ogg" -> "ogg"
            else -> if (lien.contains("fbcdn.net")) "mp4" else "bin"
        }
    }

    // MARK: Pistes image / son

    private fun pistes(f: File): Pair<Boolean, Boolean> {
        val ex = MediaExtractor()
        return try {
            ex.setDataSource(f.absolutePath)
            var image = false
            var son = false
            for (i in 0 until ex.trackCount) {
                val mime = ex.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("video/")) image = true
                if (mime.startsWith("audio/")) son = true
            }
            image to son
        } catch (e: Exception) {
            false to false
        } finally {
            ex.release()
        }
    }

    /** Assemble l'image d'un fichier et le son d'un autre, sans réencodage. */
    private fun fusionner(video: File, audio: File, sortie: File): Boolean {
        val exV = MediaExtractor().apply { setDataSource(video.absolutePath) }
        val exA = MediaExtractor().apply { setDataSource(audio.absolutePath) }
        var muxer: MediaMuxer? = null
        try {
            val iv = piste(exV, "video/") ?: return false
            val ia = piste(exA, "audio/") ?: return false
            exV.selectTrack(iv)
            exA.selectTrack(ia)
            val formatV = exV.getTrackFormat(iv)
            val formatA = exA.getTrackFormat(ia)
            val m = MediaMuxer(sortie.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = m
            if (formatV.containsKey(MediaFormat.KEY_ROTATION)) m.setOrientationHint(formatV.getInteger(MediaFormat.KEY_ROTATION))
            val tv = m.addTrack(formatV)
            val ta = m.addTrack(formatA)
            m.start()
            val taille = maxOf(
                if (formatV.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) formatV.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE) else 0,
                if (formatA.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) formatA.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE) else 0,
                4 * 1024 * 1024,
            )
            val tampon = ByteBuffer.allocateDirect(taille)
            val infos = MediaCodec.BufferInfo()
            var finV = false
            var finA = false
            // On écrit l'image et le son en alternance, dans l'ordre du temps.
            while (!finV || !finA) {
                val tempsV = if (finV) Long.MAX_VALUE else exV.sampleTime
                val tempsA = if (finA) Long.MAX_VALUE else exA.sampleTime
                if (tempsV < 0) { finV = true; continue }
                if (tempsA < 0) { finA = true; continue }
                val prendreV = tempsV <= tempsA
                val ex = if (prendreV) exV else exA
                tampon.clear()
                val n = ex.readSampleData(tampon, 0)
                if (n < 0) { if (prendreV) finV = true else finA = true; continue }
                infos.offset = 0
                infos.size = n
                infos.presentationTimeUs = ex.sampleTime
                infos.flags = if (ex.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                m.writeSampleData(if (prendreV) tv else ta, tampon, infos)
                ex.advance()
            }
            m.stop()
            return true
        } catch (e: Exception) {
            sortie.delete()
            return false
        } finally {
            runCatching { muxer?.release() }
            exV.release()
            exA.release()
        }
    }

    private fun piste(ex: MediaExtractor, prefixe: String): Int? =
        (0 until ex.trackCount).firstOrNull { ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith(prefixe) == true }

}

/** Retrouve le fichier mp4 d'une vidéo Facebook à partir du lien de sa page. */
object ExtracteurFacebook {
    private val cles = listOf(
        "browser_native_hd_url", "playable_url_quality_hd", "hd_src_no_ratelimit", "hd_src",
        "browser_native_sd_url", "playable_url", "sd_src_no_ratelimit", "sd_src",
    )

    suspend fun lienVideo(lien: String): String? = withContext(Dispatchers.IO) {
        for (agent in listOf(Telechargeur.AGENT_ORDINATEUR, Telechargeur.AGENT_MOBILE)) {
            val html = runCatching { page(lien, agent) }.getOrNull() ?: continue
            chercher(html)?.let { return@withContext it }
        }
        null
    }

    private fun page(lien: String, agent: String): String {
        val c = URL(lien).openConnection() as HttpURLConnection
        c.connectTimeout = 20_000
        c.readTimeout = 20_000
        c.setRequestProperty("User-Agent", agent)
        c.setRequestProperty("Accept", "text/html,application/xhtml+xml")
        c.setRequestProperty("Accept-Language", "fr-FR,fr;q=0.9,en;q=0.8")
        CookieManager.getInstance().getCookie(lien)?.let { c.setRequestProperty("Cookie", it) }
        return try { c.inputStream.bufferedReader().readText() } finally { c.disconnect() }
    }

    fun chercher(html: String): String? {
        for (cle in cles) {
            val motif = Regex("\"?" + cle + "\"?\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)+)\"")
            val brut = motif.find(html)?.groupValues?.get(1) ?: continue
            val lien = runCatching { org.json.JSONTokener("\"" + brut + "\"").nextValue() as String }.getOrNull() ?: continue
            if (lien.startsWith("https://")) return lien
        }
        val meta = Regex("<meta[^>]+property=\"og:video(?::secure_url|:url)?\"[^>]+content=\"([^\"]+)\"").find(html)
        return meta?.groupValues?.get(1)?.replace("&amp;", "&")?.takeIf { it.startsWith("https://") }
    }
}
