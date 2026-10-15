package com.kounandi.elara

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.view.WindowManager
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.IntentCompat
import androidx.lifecycle.lifecycleScope
import com.kounandi.elara.donnees.Bibliotheque
import com.kounandi.elara.donnees.Coffre
import com.kounandi.elara.donnees.Reglages
import com.kounandi.elara.ui.Racine
import com.kounandi.elara.ui.commun.ElaraTheme
import com.kounandi.elara.ui.lecteur.Lecteur
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {

    /** Vrai juste avant d'ouvrir un sélecteur de fichiers depuis le dossier privé. */
    var garderOuvert = false

    /** Lien reçu par « Partager vers Elara » : ouvre le téléchargeur. */
    var lienPartage by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        actuelle = this
        setContent {
            ElaraTheme { Racine(this) }
        }
        if (savedInstanceState == null) traiter(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        traiter(intent)
    }

    override fun onDestroy() {
        if (actuelle === this) actuelle = null
        super.onDestroy()
    }

    private fun traiter(intent: Intent?) {
        intent ?: return
        when (intent.action) {
            Intent.ACTION_SEND -> {
                val flux = IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
                if (flux != null) {
                    importer(listOf(flux), lire = false)
                } else {
                    val texte = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
                    Regex("""https?://\S+""").find(texte)?.value?.let { lienPartage = it }
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val liste = IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
                if (!liste.isNullOrEmpty()) importer(liste, lire = false)
            }
            Intent.ACTION_VIEW -> intent.data?.let { importer(listOf(it), lire = true) }
        }
    }

    private fun importer(uris: List<Uri>, lire: Boolean) {
        lifecycleScope.launch {
            val ajoutes = uris.mapNotNull { Bibliotheque.importer(it) }
            Reglages.changerOnglet(0)
            if (lire) ajoutes.firstOrNull()?.let { Lecteur.lire(it, listOf(it)) }
        }
    }

    // MARK: Image dans l'image

    fun peutPip(): Boolean =
        Reglages.imageDansImage && Lecteur.ouvert && Lecteur.estVideo &&
            packageManager.hasSystemFeature("android.software.picture_in_picture")

    fun entrerPip() {
        if (!peutPip()) return
        val l = Lecteur.largeurVideo.coerceAtLeast(1)
        val h = Lecteur.hauteurVideo.coerceAtLeast(1)
        // Android refuse les formats plus extrêmes que 2,39:1.
        val ratio = (l.toFloat() / h).coerceIn(1f / 2.39f, 2.39f)
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(Rational((ratio * 1000).toInt(), 1000))
            .build()
        runCatching { enterPictureInPictureMode(params) }
    }

    /** Android 12+ : passe tout seul en image dans l'image quand on quitte l'app pendant une vidéo. */
    fun majPipAuto() {
        if (android.os.Build.VERSION.SDK_INT < 31) return
        val l = Lecteur.largeurVideo.coerceAtLeast(1)
        val h = Lecteur.hauteurVideo.coerceAtLeast(1)
        val ratio = (l.toFloat() / h).coerceIn(1f / 2.39f, 2.39f)
        runCatching {
            setPictureInPictureParams(
                PictureInPictureParams.Builder()
                    .setAspectRatio(Rational((ratio * 1000).toInt(), 1000))
                    .setAutoEnterEnabled(peutPip() && Lecteur.enLecture)
                    .build()
            )
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Lecteur.enLecture) entrerPip()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        Lecteur.enPip = isInPictureInPictureMode
    }

    override fun onStop() {
        super.onStop()
        // La fenêtre flottante a été fermée, ou l'app passe en arrière-plan : on arrête la vidéo.
        if (!isInPictureInPictureMode && Lecteur.estVideo) Lecteur.pause()
        Lecteur.sauverPosition()
        // Le dossier privé se referme dès qu'on quitte l'app.
        if (garderOuvert) garderOuvert = false
        else if (!isInPictureInPictureMode) {
            Coffre.verrouiller()
            if (Lecteur.mediaActuel?.prive == true) Lecteur.fermer()
        }
    }

    /** Empêche les captures d'écran pendant que le contenu privé est affiché. */
    fun protegerEcran(actif: Boolean) {
        if (actif) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    companion object {
        var actuelle: MainActivity? = null
            private set
    }
}
