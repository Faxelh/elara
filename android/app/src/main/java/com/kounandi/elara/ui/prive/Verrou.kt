package com.kounandi.elara.ui.prive

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Backspace
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.kounandi.elara.ui.commun.Elara
import kotlin.math.hypot
import kotlin.math.roundToInt

/** Petite secousse quand le code ou le schéma est faux. */
@Composable
fun rememberSecousse(declencheur: Int): Float {
    val decalage = remember { Animatable(0f) }
    LaunchedEffect(declencheur) {
        if (declencheur == 0) return@LaunchedEffect
        for (v in listOf(-18f, 16f, -12f, 8f, -4f, 0f)) decalage.animateTo(v, androidx.compose.animation.core.tween(45))
    }
    return decalage.value
}

/** Points du code + clavier numérique. */
@Composable
fun ClavierCode(
    saisie: String,
    longueurPoints: Int,
    secousse: Int,
    biometrie: (() -> Unit)?,
    surChiffre: (Char) -> Unit,
    surEffacer: () -> Unit,
) {
    val decalage = rememberSecousse(secousse)
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Row(Modifier.offset(x = decalage.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            repeat(longueurPoints) { i ->
                Box(
                    Modifier
                        .size(14.dp)
                        .clip(CircleShape)
                        .then(
                            if (i < saisie.length) Modifier.background(Elara.accent)
                            else Modifier.border(2.dp, MaterialTheme.colorScheme.onSurfaceVariant, CircleShape),
                        ),
                )
            }
        }
        Spacer(Modifier.height(36.dp))
        val touches = listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "bio", "0", "eff")
        touches.chunked(3).forEach { ligne ->
            Row(horizontalArrangement = Arrangement.spacedBy(26.dp)) {
                ligne.forEach { t ->
                    Box(
                        Modifier
                            .size(76.dp)
                            .clip(CircleShape)
                            .then(
                                when {
                                    t.length == 1 -> Modifier
                                        .background(MaterialTheme.colorScheme.surfaceVariant)
                                        .clickable { surChiffre(t[0]) }
                                    t == "bio" && biometrie != null -> Modifier.clickable { biometrie() }
                                    t == "eff" -> Modifier.clickable { surEffacer() }
                                    else -> Modifier
                                },
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        when {
                            t.length == 1 -> Text(t, fontSize = 30.sp, fontWeight = FontWeight.Medium)
                            t == "bio" && biometrie != null ->
                                Icon(Icons.Filled.Fingerprint, null, tint = Elara.accent, modifier = Modifier.size(38.dp))
                            t == "eff" -> Icon(Icons.AutoMirrored.Filled.Backspace, null)
                        }
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

/** Grille 3 × 3 : on relie au moins 4 points sans lever le doigt. */
@Composable
fun GrilleSchema(secousse: Int, erreur: Boolean, surSchema: (List<Int>) -> Unit) {
    val points = remember { mutableStateListOf<Int>() }
    var doigt by remember { mutableStateOf<Offset?>(null) }
    val fin by rememberUpdatedState(surSchema)
    val decalage = rememberSecousse(secousse)
    val couleurLigne = if (erreur) Elara.corail else Elara.accent
    val couleurPoint = MaterialTheme.colorScheme.onSurfaceVariant

    Canvas(
        Modifier
            .offset(x = decalage.dp)
            .width(290.dp)
            .aspectRatio(1f)
            .pointerInput(Unit) {
                val pas = size.width / 3f
                fun centre(i: Int) = Offset(pas * (i % 3) + pas / 2, pas * (i / 3) + pas / 2)
                fun toucher(p: Offset) {
                    for (i in 0 until 9) {
                        if (i !in points && hypot(p.x - centre(i).x, p.y - centre(i).y) < pas * 0.32f) {
                            // Relie aussi le point du milieu si on passe par-dessus (comme Android).
                            val dernier = points.lastOrNull()
                            if (dernier != null) {
                                val milieu = (dernier + i) / 2
                                val alignes = (dernier + i) % 2 == 0 &&
                                    ((dernier / 3 + i / 3) % 2 == 0) && ((dernier % 3 + i % 3) % 2 == 0)
                                if (alignes && milieu !in points && milieu != dernier && milieu != i) points.add(milieu)
                            }
                            points.add(i)
                        }
                    }
                }
                awaitEachGesture {
                    val debut = awaitFirstDown()
                    points.clear()
                    doigt = debut.position
                    toucher(debut.position)
                    drag(debut.id) { c ->
                        c.consume()
                        doigt = c.position
                        toucher(c.position)
                    }
                    doigt = null
                    if (points.isNotEmpty()) fin(points.toList())
                    points.clear()
                }
            },
    ) {
        val pas = size.width / 3f
        fun centre(i: Int) = Offset(pas * (i % 3) + pas / 2, pas * (i / 3) + pas / 2)
        val trait = 7.dp.toPx()
        for (k in 1 until points.size) {
            drawLine(couleurLigne, centre(points[k - 1]), centre(points[k]), trait, StrokeCap.Round)
        }
        val d = doigt
        if (d != null && points.isNotEmpty()) {
            drawLine(couleurLigne.copy(alpha = 0.6f), centre(points.last()), d, trait, StrokeCap.Round)
        }
        for (i in 0 until 9) {
            val actif = i in points
            drawCircle(if (actif) couleurLigne else couleurPoint, (if (actif) 11.dp else 8.dp).toPx(), centre(i))
            if (actif) drawCircle(couleurLigne.copy(alpha = 0.25f), 26.dp.toPx(), centre(i))
            else drawCircle(couleurPoint.copy(alpha = 0.25f), 26.dp.toPx(), centre(i), style = Stroke(1.5.dp.toPx()))
        }
    }
}

fun schemaEnTexte(points: List<Int>): String = points.joinToString("-")

// MARK: - Empreinte / visage

fun biometrieDisponible(activite: FragmentActivity): Boolean =
    BiometricManager.from(activite).canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK) ==
        BiometricManager.BIOMETRIC_SUCCESS

fun demanderBiometrie(
    activite: FragmentActivity,
    titre: String,
    sousTitre: String,
    boutonCode: String,
    surSucces: () -> Unit,
) {
    val prompt = BiometricPrompt(
        activite,
        ContextCompat.getMainExecutor(activite),
        object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                surSucces()
            }
        },
    )
    val infos = BiometricPrompt.PromptInfo.Builder()
        .setTitle(titre)
        .setSubtitle(sousTitre)
        .setNegativeButtonText(boutonCode)
        .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_WEAK)
        .build()
    prompt.authenticate(infos)
}

@Suppress("unused")
private fun Float.arrondi() = roundToInt()
