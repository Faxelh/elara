package com.kounandi.elara.donnees

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.InAppMuxer
import androidx.media3.transformer.Transformer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.coroutines.resume

/**
 * Assemble l'image d'un fichier et le son d'un autre en un MP4 que le lecteur d'Elara sait lire.
 *
 * Facebook envoie souvent des morceaux « DASH » (MP4 fragmenté, parfois en VP9 ou AV1).
 * L'assembleur d'Android les écrit mal pour ces codecs (fichier « malformé ») : on passe donc par
 * Media3, qui lit ces morceaux comme le lecteur et écrit un MP4 standard. Si le codec ne peut pas
 * être recopié tel quel, la vidéo est réencodée en H.264 / AAC.
 */
@OptIn(UnstableApi::class)
object Assemblage {

    suspend fun assembler(ctx: Context, video: File, audio: File?, sortie: File): Boolean {
        // 1er essai : recopie sans réencodage (rapide). 2e essai : réencodage H.264 / AAC (toujours lisible).
        if (exporter(ctx, video, audio, sortie, reencoder = false)) return true
        sortie.delete()
        if (exporter(ctx, video, audio, sortie, reencoder = true)) return true
        sortie.delete()
        return false
    }

    private suspend fun exporter(ctx: Context, video: File, audio: File?, sortie: File, reencoder: Boolean): Boolean =
        withContext(Dispatchers.Main) {
            suspendCancellableCoroutine<Boolean> { suite ->
                val principal = Handler(Looper.getMainLooper())
                val constructeur = Transformer.Builder(ctx)
                    .setMuxerFactory(InAppMuxer.Factory.Builder().build())
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                            if (suite.isActive) suite.resume(sortie.length() > 0)
                        }

                        override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                            if (suite.isActive) suite.resume(false)
                        }
                    })
                if (reencoder) {
                    constructeur.setVideoMimeType(MimeTypes.VIDEO_H264).setAudioMimeType(MimeTypes.AUDIO_AAC)
                }
                val transformer = constructeur.build()
                val composition = if (audio == null) {
                    Composition.Builder(EditedMediaItemSequence(element(video, sansSon = false))).build()
                } else {
                    Composition.Builder(
                        EditedMediaItemSequence(element(video, sansSon = true)),
                        EditedMediaItemSequence(element(audio, sansImage = true)),
                    ).build()
                }
                try {
                    transformer.start(composition, sortie.absolutePath)
                } catch (e: Exception) {
                    if (suite.isActive) suite.resume(false)
                    return@suspendCancellableCoroutine
                }
                suite.invokeOnCancellation { principal.post { transformer.cancel() } }
            }
        }

    private fun element(f: File, sansSon: Boolean = false, sansImage: Boolean = false): EditedMediaItem =
        EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(f)))
            .setRemoveAudio(sansSon)
            .setRemoveVideo(sansImage)
            .build()
}
