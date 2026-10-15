package com.kounandi.elara.donnees

import android.content.Context
import android.graphics.RectF
import android.net.Uri
import android.opengl.GLES20
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.Crop
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Retire des filigranes (logo, texte, @pseudo…) d'une vidéo : en effaçant la zone (reconstruite avec
 * les couleurs autour, sans flou) ou en recadrant l'image. Zones en proportions (0…1), origine en haut à gauche.
 * Le son est conservé.
 */
@OptIn(UnstableApi::class)
object Filigrane {
    enum class Mode { EFFACER, RECADRER }

    /** Partie gardée quand on recadre : pour chaque zone, on coupe la bande du bord le plus proche. */
    fun partieGardee(zones: List<RectF>): RectF {
        val g = RectF(0f, 0f, 1f, 1f)
        for (z in zones) {
            when (listOf(z.top, 1f - z.bottom, z.left, 1f - z.right).withIndex().minBy { it.value }.index) {
                0 -> g.top = maxOf(g.top, z.bottom)
                1 -> g.bottom = minOf(g.bottom, z.top)
                2 -> g.left = maxOf(g.left, z.right)
                else -> g.right = minOf(g.right, z.left)
            }
        }
        return if (g.width() > 0.2f && g.height() > 0.2f) g else RectF(0f, 0f, 1f, 1f)
    }

    suspend fun traiter(ctx: Context, source: File, zones: List<RectF>, mode: Mode, progression: (Float) -> Unit): File =
        withContext(Dispatchers.Main) {
            val dossier = File(ctx.cacheDir, "filigrane").apply { mkdirs() }
            val sortie = File(dossier, UUID.randomUUID().toString() + ".mp4")
            suspendCancellableCoroutine<File> { suite ->
                val principal = Handler(Looper.getMainLooper())
                val transformer = Transformer.Builder(ctx)
                    .setVideoMimeType(MimeTypes.VIDEO_H264)
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                            if (suite.isActive) suite.resume(sortie)
                        }

                        override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                            sortie.delete()
                            if (suite.isActive) suite.resumeWithException(exportException)
                        }
                    })
                    .build()
                val element = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(source)))
                    .setEffects(Effects(listOf(), listOf(effet(zones, mode))))
                    .build()
                transformer.start(element, sortie.absolutePath)

                val etat = ProgressHolder()
                val suivi = object : Runnable {
                    override fun run() {
                        if (!suite.isActive) return
                        if (transformer.getProgress(etat) == Transformer.PROGRESS_STATE_AVAILABLE) progression(etat.progress / 100f)
                        principal.postDelayed(this, 300)
                    }
                }
                principal.post(suivi)
                suite.invokeOnCancellation {
                    principal.post {
                        transformer.cancel()
                        sortie.delete()
                    }
                }
            }
        }
}

private fun effet(zones: List<RectF>, mode: Filigrane.Mode): GlEffect = when (mode) {
    Filigrane.Mode.EFFACER -> ZoneFloue(zones.take(4))
    Filigrane.Mode.RECADRER -> {
        // Coordonnées OpenGL (-1…1, vers le haut).
        val g = Filigrane.partieGardee(zones)
        Crop(2f * g.left - 1f, 2f * g.right - 1f, 1f - 2f * g.bottom, 1f - 2f * g.top)
    }
}

/** Effet vidéo : efface jusqu'à 4 zones rectangulaires (reconstruites avec les pixels autour). */
@OptIn(UnstableApi::class)
class ZoneFloue(private val zones: List<RectF>) : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram = ProgrammeFlou(zones, useHdr)
}

@OptIn(UnstableApi::class)
private class ProgrammeFlou(private val zones: List<RectF>, useHdr: Boolean) : BaseGlShaderProgram(useHdr, 1) {
    private val programme = GlProgram(VERTEX, FRAGMENT)
    private var largeur = 1
    private var hauteur = 1

    init {
        programme.setBufferAttribute(
            "aFramePosition",
            GlUtil.getNormalizedCoordinateBounds(),
            GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE,
        )
    }

    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        largeur = inputWidth
        hauteur = inputHeight
        return Size(inputWidth, inputHeight)
    }

    override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
        programme.use()
        programme.setSamplerTexIdUniform("uTexSampler", inputTexId, 0)
        programme.setFloatsUniform("uTaille", floatArrayOf(largeur.toFloat(), hauteur.toFloat()))
        for (i in 0 until 4) {
            val z = zones.getOrNull(i)
            programme.setFloatsUniform("uZone$i", if (z == null) floatArrayOf(0f, 0f, 0f, 0f) else floatArrayOf(z.left, z.top, z.width(), z.height()))
        }
        programme.bindAttributesAndUniforms()
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
    }

    override fun release() {
        super.release()
        programme.delete()
    }

    companion object {
        private const val VERTEX = """#version 100
attribute vec4 aFramePosition;
varying vec2 vTexSamplingCoord;
void main() {
  gl_Position = aFramePosition;
  vTexSamplingCoord = vec2(aFramePosition.x * 0.5 + 0.5, aFramePosition.y * 0.5 + 0.5);
}
"""

        // Zones en coordonnées « haut gauche » : on retourne l'axe vertical de la texture.
        private const val FRAGMENT = """#version 100
precision mediump float;
uniform sampler2D uTexSampler;
uniform vec2 uTaille;
uniform vec4 uZone0;
uniform vec4 uZone1;
uniform vec4 uZone2;
uniform vec4 uZone3;
varying vec2 vTexSamplingCoord;

bool dans(vec4 z, vec2 p) {
  return z.z > 0.0 && p.x >= z.x && p.x <= z.x + z.z && p.y >= z.y && p.y <= z.y + z.w;
}

// Comme « delogo » : chaque point de la zone mélange les bords gauche/droite et haut/bas.
vec4 effacer(vec2 c, vec4 z) {
  vec2 e = vec2(1.5, 1.5) / uTaille;
  vec2 p = vec2(c.x, 1.0 - c.y);
  float gauche = clamp(z.x - e.x, 0.0, 1.0);
  float droite = clamp(z.x + z.z + e.x, 0.0, 1.0);
  float haut = clamp(1.0 - (z.y - e.y), 0.0, 1.0);
  float bas = clamp(1.0 - (z.y + z.w + e.y), 0.0, 1.0);
  vec4 g = texture2D(uTexSampler, vec2(gauche, c.y));
  vec4 d = texture2D(uTexSampler, vec2(droite, c.y));
  vec4 h = texture2D(uTexSampler, vec2(c.x, haut));
  vec4 b = texture2D(uTexSampler, vec2(c.x, bas));
  float tx = clamp((p.x - z.x) / z.z, 0.0, 1.0);
  float ty = clamp((p.y - z.y) / z.w, 0.0, 1.0);
  return 0.5 * (mix(g, d, tx) + mix(h, b, ty));
}

void main() {
  vec2 c = vTexSamplingCoord;
  vec2 p = vec2(c.x, 1.0 - c.y);
  vec4 couleur = texture2D(uTexSampler, c);
  if (dans(uZone0, p)) { couleur = effacer(c, uZone0); }
  else if (dans(uZone1, p)) { couleur = effacer(c, uZone1); }
  else if (dans(uZone2, p)) { couleur = effacer(c, uZone2); }
  else if (dans(uZone3, p)) { couleur = effacer(c, uZone3); }
  gl_FragColor = couleur;
}
"""
    }
}
