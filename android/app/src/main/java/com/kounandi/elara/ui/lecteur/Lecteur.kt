package com.kounandi.elara.ui.lecteur

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.kounandi.elara.donnees.Bibliotheque
import com.kounandi.elara.donnees.Media
import com.kounandi.elara.donnees.ModeLectureAuto
import com.kounandi.elara.donnees.Reglages
import com.kounandi.elara.donnees.TypeMedia
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Lecteur unique d'Elara (vidéo et audio) avec sa file de lecture. */
object Lecteur {
    lateinit var player: ExoPlayer
        private set

    var ouvert by mutableStateOf(false)
    var enPip by mutableStateOf(false)
    var file by mutableStateOf<List<Media>>(emptyList()); private set
    var index by mutableStateOf(0); private set
    var enLecture by mutableStateOf(false); private set
    /** Vidéo arrivée au bout : le bouton devient « Revoir ». */
    var termine by mutableStateOf(false); private set
    var position by mutableStateOf(0L); private set
    var duree by mutableStateOf(0L); private set
    var vitesse by mutableStateOf(1f); private set
    var largeurVideo by mutableStateOf(16); private set
    var hauteurVideo by mutableStateOf(9); private set

    /** Répéter la vidéo en cours (bouton du lecteur). */
    var repeterUn by mutableStateOf(false)
    /** Minuterie de veille : heure de fin (ms), ou fin de la vidéo en cours. */
    var minuterieFin by mutableStateOf<Long?>(null); private set
    var minuterieFinVideo by mutableStateOf(false); private set
    private var tacheMinuterie: kotlinx.coroutines.Job? = null
    /** Change quand les pistes disponibles changent (audio, sous-titres). */
    var versionPistes by mutableStateOf(0); private set
    /** Dernière erreur de lecture (affichée dans le lecteur), null si tout va bien. */
    var erreur by mutableStateOf<String?>(null); private set
    private var essais = 0

    val mediaActuel: Media? get() = file.getOrNull(index)
    val estVideo: Boolean get() = mediaActuel?.type == TypeMedia.VIDEO

    private val scope = MainScope()

    fun init(ctx: Context) {
        // Si le décodeur matériel du téléphone refuse la vidéo, on essaie automatiquement un autre décodeur.
        val rendus = androidx.media3.exoplayer.DefaultRenderersFactory(ctx)
            .setEnableDecoderFallback(true)
            .setExtensionRendererMode(androidx.media3.exoplayer.DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
        player = ExoPlayer.Builder(ctx, rendus)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                    .build(),
                true,
            )
            .setHandleAudioBecomingNoisy(true)
            .build()
        player.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                enLecture = isPlaying
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                termine = playbackState == Player.STATE_ENDED
                if (playbackState == Player.STATE_ENDED) finDeLecture()
                if (playbackState == Player.STATE_READY) {
                    erreur = null
                    val d = player.duration
                    if (d > 0) duree = d
                }
            }

            override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                // Une nouvelle tentative (souvent suffisante après un accroc du décodeur), puis on affiche la cause.
                if (essais < 1) {
                    essais++
                    val pos = player.currentPosition
                    player.prepare()
                    player.seekTo(pos.coerceAtLeast(0))
                    player.play()
                } else {
                    erreur = "Lecture impossible (" + error.errorCodeName + ")"
                }
            }

            override fun onTracksChanged(tracks: androidx.media3.common.Tracks) {
                versionPistes++
            }

            override fun onVideoSizeChanged(videoSize: androidx.media3.common.VideoSize) {
                if (videoSize.width > 0 && videoSize.height > 0) {
                    largeurVideo = videoSize.width
                    hauteurVideo = videoSize.height
                }
            }
        })
        scope.launch {
            while (true) {
                delay(300)
                if (ouvert || enLecture) {
                    position = player.currentPosition.coerceAtLeast(0)
                    val d = player.duration
                    if (d > 0) duree = d
                }
            }
        }
    }

    fun lire(media: Media, liste: List<Media>) {
        sauverPosition()
        file = liste.ifEmpty { listOf(media) }
        index = file.indexOfFirst { it.id == media.id }.coerceAtLeast(0)
        charger()
        ouvert = true
    }

    private fun charger() {
        val enFile = mediaActuel ?: return
        val media = Bibliotheque.media(enFile.id) ?: enFile
        erreur = null
        essais = 0
        val fichier = Bibliotheque.fichier(media)
        if (!fichier.exists() || fichier.length() == 0L) {
            erreur = "Fichier introuvable : " + fichier.name
            return
        }
        player.setMediaItem(MediaItem.fromUri(Uri.fromFile(Bibliotheque.fichier(media))))
        player.prepare()
        duree = media.duree
        position = 0
        if (Reglages.reprendreLecture && media.position > 2000 && media.position < media.duree - 2000) {
            player.seekTo(media.position)
            position = media.position
        }
        player.setPlaybackSpeed(vitesse)
        player.play()
    }

    fun basculerLecture() {
        if (player.isPlaying) player.pause() else {
            // Lecteur bloqué après une erreur : on recharge la vidéo.
            if (player.playbackState == Player.STATE_IDLE) { essais = 0; player.prepare() }
            if (player.playbackState == Player.STATE_ENDED) player.seekTo(0)
            player.play()
        }
    }

    fun suivant() {
        if (file.isEmpty()) return
        sauverPosition()
        index = (index + 1) % file.size
        charger()
    }

    fun precedent() {
        if (file.isEmpty()) return
        if (player.currentPosition > 3000) { chercher(0); return }
        sauverPosition()
        index = (index - 1 + file.size) % file.size
        charger()
    }

    fun chercher(ms: Long) {
        player.seekTo(ms.coerceAtLeast(0))
        position = ms.coerceAtLeast(0)
    }

    fun sauter(deltaMs: Long) {
        var cible = (player.currentPosition + deltaMs).coerceAtLeast(0)
        if (duree > 0) cible = cible.coerceAtMost(duree)
        chercher(cible)
    }

    fun definirVitesse(v: Float) {
        vitesse = v
        player.setPlaybackSpeed(v)
    }

    fun pause() {
        player.pause()
        sauverPosition()
    }

    fun fermer() {
        sauverPosition()
        player.pause()
        ouvert = false
    }

    fun sauverPosition() {
        val media = mediaActuel ?: return
        Bibliotheque.memoriserPosition(media.id, player.currentPosition.coerceAtLeast(0))
    }

    // MARK: Minuterie

    /** `minutes = null` : s'arrêter à la fin de la vidéo en cours. */
    fun programmerMinuterie(minutes: Int?) {
        annulerMinuterie()
        if (minutes == null) { minuterieFinVideo = true; return }
        minuterieFin = System.currentTimeMillis() + minutes * 60_000L
        tacheMinuterie = scope.launch {
            delay(minutes * 60_000L)
            pause()
            minuterieFin = null
        }
    }

    fun annulerMinuterie() {
        tacheMinuterie?.cancel()
        tacheMinuterie = null
        minuterieFin = null
        minuterieFinVideo = false
    }

    val minuterieActive: Boolean get() = minuterieFin != null || minuterieFinVideo

    // MARK: Pistes audio et sous-titres

    data class Piste(val groupe: androidx.media3.common.TrackGroup, val index: Int, val nom: String, val choisie: Boolean)

    fun pistes(type: Int): List<Piste> {
        val liste = mutableListOf<Piste>()
        var n = 1
        for (g in player.currentTracks.groups) {
            if (g.type != type) continue
            for (i in 0 until g.length) {
                if (!g.isTrackSupported(i)) continue
                val f = g.getTrackFormat(i)
                val langue = f.language?.let { java.util.Locale(it).displayLanguage.replaceFirstChar { c -> c.uppercase() } }
                val nom = f.label ?: langue ?: "Piste ${n}"
                n++
                liste += Piste(g.mediaTrackGroup, i, nom, g.isTrackSelected(i))
            }
        }
        return liste
    }

    fun choisirPiste(type: Int, piste: Piste?) {
        val p = player.trackSelectionParameters.buildUpon()
        if (piste == null) {
            p.setTrackTypeDisabled(type, true)
        } else {
            p.setTrackTypeDisabled(type, false)
            p.setOverrideForType(androidx.media3.common.TrackSelectionOverride(piste.groupe, piste.index))
        }
        player.trackSelectionParameters = p.build()
        versionPistes++
    }

    private fun finDeLecture() {
        mediaActuel?.let { Bibliotheque.memoriserPosition(it.id, 0) }
        if (minuterieFinVideo) { annulerMinuterie(); return }
        if (repeterUn) { player.seekTo(0); player.play(); return }
        when (Reglages.modeLectureAuto) {
            ModeLectureAuto.ARRETER -> Unit
            ModeLectureAuto.REPETER_UN -> { player.seekTo(0); player.play() }
            ModeLectureAuto.ENCHAINER -> if (index + 1 < file.size) { index += 1; charger() }
            ModeLectureAuto.BOUCLE -> { index = (index + 1) % file.size.coerceAtLeast(1); charger() }
        }
    }
}
