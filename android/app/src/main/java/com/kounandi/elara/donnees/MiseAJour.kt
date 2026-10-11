package com.kounandi.elara.donnees

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.FileProvider
import com.kounandi.elara.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/** Nouvelle version publiée sur GitHub (onglet « Releases » du dépôt). */
data class VersionDisponible(val numero: Int, val nom: String, val lienApk: String, val notes: String) {
    /** Version affichée, ex. « 2026.2.3 » (dernier mot du titre de la Release). */
    val version: String get() = nom.trim().substringAfterLast(' ')
}

/**
 * Mises à jour d'Elara depuis GitHub : chaque compilation publie l'APK dans une « Release »
 * (étiquette android-NUMÉRO). Elara compare ce numéro au sien, télécharge l'APK et lance l'installation.
 */
object MiseAJour {
    const val DEPOT = "Faxelh/elara"

    var disponible by mutableStateOf<VersionDisponible?>(null); private set
    var recherche by mutableStateOf(false); private set
    var telechargement by mutableStateOf(false); private set
    var progression by mutableFloatStateOf(0f); private set
    var derniereErreur by mutableStateOf<String?>(null); private set

    val versionActuelle: Int get() = BuildConfig.VERSION_CODE

    /** Vérifie au plus une fois par jour, sauf si `forcer`. Renvoie la version plus récente, ou null. */
    suspend fun verifier(forcer: Boolean = false): VersionDisponible? = withContext(Dispatchers.IO) {
        val maintenant = System.currentTimeMillis()
        val derniere = Reglages.texte("maj.derniere")?.toLongOrNull() ?: 0L
        if (!forcer && maintenant - derniere < 24 * 3600 * 1000L) return@withContext disponible
        recherche = true
        derniereErreur = null
        try {
            val c = URL("https://api.github.com/repos/$DEPOT/releases?per_page=20").openConnection() as HttpURLConnection
            c.setRequestProperty("Accept", "application/vnd.github+json")
            c.setRequestProperty("User-Agent", "Elara-Android")
            c.connectTimeout = 15_000
            c.readTimeout = 15_000
            if (c.responseCode !in 200..299) throw Exception("GitHub : ${c.responseCode}")
            val liste = JSONArray(c.inputStream.bufferedReader().readText())
            c.disconnect()
            var meilleure: VersionDisponible? = null
            for (i in 0 until liste.length()) {
                val r = liste.getJSONObject(i)
                val tag = r.optString("tag_name")
                if (!tag.startsWith("android-")) continue
                val numero = tag.removePrefix("android-").toIntOrNull() ?: continue
                val actifs = r.optJSONArray("assets") ?: continue
                val apk = (0 until actifs.length()).map { actifs.getJSONObject(it) }
                    .firstOrNull { it.optString("name").endsWith(".apk") } ?: continue
                if (meilleure == null || numero > meilleure.numero) {
                    meilleure = VersionDisponible(numero, r.optString("name", tag), apk.optString("browser_download_url"), r.optString("body"))
                }
            }
            Reglages.ecrireTexte("maj.derniere", maintenant.toString())
            disponible = meilleure?.takeIf { it.numero > versionActuelle }
            disponible
        } catch (e: Exception) {
            derniereErreur = e.message
            null
        } finally {
            recherche = false
        }
    }

    /** Télécharge l'APK puis ouvre l'installateur d'Android. */
    suspend fun installer(ctx: Context, version: VersionDisponible): Boolean {
        // Android demande une fois l'autorisation « Installer des applis inconnues » pour Elara.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !ctx.packageManager.canRequestPackageInstalls()) {
            ctx.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + ctx.packageName))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return false
        }
        val fichier = withContext(Dispatchers.IO) {
            telechargement = true
            progression = 0f
            try {
                val dossier = File(ctx.cacheDir, "maj").apply { mkdirs() }
                dossier.listFiles()?.forEach { it.delete() }
                val dest = File(dossier, "Elara-${version.numero}.apk")
                var adresse = version.lienApk
                var c = URL(adresse).openConnection() as HttpURLConnection
                var sauts = 0
                while (c.responseCode in 300..399 && sauts < 6) {
                    adresse = c.getHeaderField("Location") ?: break
                    c.disconnect()
                    c = URL(adresse).openConnection() as HttpURLConnection
                    sauts++
                }
                val total = c.contentLengthLong
                c.inputStream.use { entree ->
                    dest.outputStream().use { sortie ->
                        val tampon = ByteArray(64 * 1024)
                        var recu = 0L
                        while (true) {
                            val n = entree.read(tampon)
                            if (n < 0) break
                            sortie.write(tampon, 0, n)
                            recu += n
                            if (total > 0) progression = recu.toFloat() / total
                        }
                    }
                }
                c.disconnect()
                dest
            } catch (e: Exception) {
                derniereErreur = e.message
                null
            } finally {
                telechargement = false
            }
        } ?: return false
        val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".fichiers", fichier)
        ctx.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        return true
    }
}
