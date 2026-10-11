package com.kounandi.elara.ui.lecteur

import android.content.Context
import android.media.AudioManager
import android.view.ViewGroup
import android.view.WindowManager
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.material.icons.filled.AspectRatio
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.FitScreen
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.RepeatOne
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.ScreenRotation
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.FullscreenExit
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PictureInPictureAlt
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.rounded.Forward10
import androidx.compose.material.icons.rounded.Replay10
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import com.kounandi.elara.MainActivity
import com.kounandi.elara.R
import com.kounandi.elara.donnees.Format
import com.kounandi.elara.donnees.Reglages
import com.kounandi.elara.ui.commun.Elara
import kotlinx.coroutines.delay

private data class Indicateur(val icone: ImageVector, val valeur: Float)

@Composable
fun LecteurEcran(activite: MainActivity) {
    val media = Lecteur.mediaActuel ?: return
    BackHandler { Lecteur.fermer() }

    // Contenu privé : pas de capture d'écran ni d'aperçu dans le sélecteur d'apps.
    DisposableEffect(media.prive) {
        activite.protegerEcran(media.prive)
        onDispose { activite.protegerEcran(false) }
    }
    // L'écran reste allumé pendant une vidéo.
    DisposableEffect(Lecteur.estVideo) {
        if (Lecteur.estVideo) activite.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose { activite.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
    }

    if (Lecteur.estVideo) LecteurVideo(activite) else LecteurAudio()
}

// MARK: - Vidéo

@Composable
private fun LecteurVideo(activite: MainActivity) {
    var visibles by remember { mutableStateOf(true) }
    var jeton by remember { mutableIntStateOf(0) }
    var mode by remember { mutableIntStateOf(0) }   // 0 = ajuster, 1 = remplir, 2 = étirer
    var verrouille by remember { mutableStateOf(false) }
    var boutonDeverrouiller by remember { mutableStateOf(false) }
    var defilement by remember { mutableStateOf<Long?>(null) }
    var departDefilement by remember { mutableLongStateOf(0L) }
    var tempsRestant by remember { mutableStateOf(false) }
    var glisse by remember { mutableStateOf<Long?>(null) }
    var saut by remember { mutableStateOf<Boolean?>(null) }   // true = +10 s, false = −10 s
    var sautJeton by remember { mutableIntStateOf(0) }
    var indicateur by remember { mutableStateOf<Indicateur?>(null) }

    fun rearmer() { jeton++; visibles = true }

    LaunchedEffect(boutonDeverrouiller) {
        if (boutonDeverrouiller) { delay(3000); boutonDeverrouiller = false }
    }
    LaunchedEffect(jeton, Lecteur.enLecture, glisse, verrouille) {
        if (verrouille) {
            visibles = false
        } else if (Lecteur.enLecture && glisse == null) {
            delay(3500)
            visibles = false
        } else {
            visibles = true
        }
    }
    LaunchedEffect(sautJeton) {
        if (saut != null) { delay(700); saut = null }
    }

    fun sauter(avant: Boolean) {
        Lecteur.sauter(if (avant) 10_000 else -10_000)
        saut = avant
        sautJeton++
        rearmer()
    }

    val contexte = LocalContext.current
    val audio = remember { contexte.getSystemService(Context.AUDIO_SERVICE) as AudioManager }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        VueVideo(mode, Modifier.fillMaxSize())

        // Gestes : toucher = commandes, double toucher = ±10 s, glisser horizontalement = avancer / reculer,
        // glisser verticalement à gauche = luminosité, à droite = volume.
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val largeurPx = constraints.maxWidth.toFloat()
            val hauteurPx = constraints.maxHeight.toFloat()
            var cote by remember { mutableIntStateOf(0) }   // 1 = luminosité, 2 = volume
            var valeur by remember { mutableFloatStateOf(0f) }
            Box(
                Modifier
                    .fillMaxSize()
                    .pointerInput(largeurPx) {
                        detectTapGestures(
                            onTap = {
                                if (verrouille) boutonDeverrouiller = !boutonDeverrouiller
                                else if (visibles) { visibles = false; jeton++ } else rearmer()
                            },
                            onDoubleTap = { p -> if (!verrouille) sauter(p.x > largeurPx / 2) },
                        )
                    }
                    .pointerInput(largeurPx) {
                        var total = 0f
                        detectHorizontalDragGestures(
                            onDragStart = {
                                total = 0f
                                if (!verrouille) {
                                    departDefilement = Lecteur.position
                                    defilement = Lecteur.position
                                }
                            },
                            onDragEnd = {
                                defilement?.let { Lecteur.chercher(it) }
                                defilement = null
                                if (!verrouille) rearmer()
                            },
                            onDragCancel = { defilement = null },
                            onHorizontalDrag = { change, dx ->
                                if (defilement != null) {
                                    change.consume()
                                    total += dx
                                    // Toute la largeur de l'écran = 90 secondes.
                                    var cible = departDefilement + (total / largeurPx * 90_000f).toLong()
                                    cible = cible.coerceAtLeast(0)
                                    if (Lecteur.duree > 0) cible = cible.coerceAtMost(Lecteur.duree)
                                    defilement = cible
                                }
                            },
                        )
                    }
                    .pointerInput(largeurPx, hauteurPx) {
                        detectVerticalDragGestures(
                            onDragStart = { p ->
                                val gauche = p.x < largeurPx / 2
                                cote = when {
                                    verrouille -> 0
                                    gauche && Reglages.gesteLuminosite -> 1
                                    !gauche && Reglages.gesteVolume -> 2
                                    else -> 0
                                }
                                valeur = if (cote == 1) {
                                    val b = activite.window.attributes.screenBrightness
                                    if (b < 0) 0.5f else b
                                } else {
                                    audio.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat() /
                                        audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
                                }
                            },
                            onDragEnd = { cote = 0; indicateur = null },
                            onDragCancel = { cote = 0; indicateur = null },
                            onVerticalDrag = { change, delta ->
                                if (cote != 0) {
                                    change.consume()
                                    valeur = (valeur - delta / (hauteurPx * 0.7f)).coerceIn(0f, 1f)
                                    if (cote == 1) {
                                        val attrs = activite.window.attributes
                                        attrs.screenBrightness = valeur.coerceAtLeast(0.01f)
                                        activite.window.attributes = attrs
                                        indicateur = Indicateur(Icons.Filled.WbSunny, valeur)
                                    } else {
                                        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                                        audio.setStreamVolume(AudioManager.STREAM_MUSIC, (valeur * max).toInt(), 0)
                                        indicateur = Indicateur(
                                            if (valeur == 0f) Icons.AutoMirrored.Filled.VolumeOff
                                            else Icons.AutoMirrored.Filled.VolumeUp,
                                            valeur,
                                        )
                                    }
                                }
                            },
                        )
                    },
            )
        }

        indicateur?.let { ind ->
            Row(
                Modifier
                    .align(Alignment.Center)
                    .clip(RoundedCornerShape(50))
                    .background(Color.Black.copy(alpha = 0.55f))
                    .padding(horizontal = 18.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(ind.icone, null, tint = Color.White)
                Spacer(Modifier.width(12.dp))
                LinearProgressIndicator(
                    progress = { ind.valeur },
                    modifier = Modifier.width(120.dp),
                    color = Color.White,
                    trackColor = Color.White.copy(alpha = 0.25f),
                )
            }
        }

        defilement?.let { cible ->
            val ecart = cible - departDefilement
            Column(
                Modifier
                    .align(Alignment.Center)
                    .clip(RoundedCornerShape(18.dp))
                    .background(Color.Black.copy(alpha = 0.6f))
                    .padding(horizontal = 22.dp, vertical = 14.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    "${Format.duree(cible)} / ${Format.duree(Lecteur.duree)}",
                    color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold,
                )
                Text(
                    (if (ecart >= 0) "+" else "−") + Format.duree(kotlin.math.abs(ecart)),
                    color = Elara.accent, fontSize = 15.sp,
                )
            }
        }

        if (verrouille) {
            AnimatedVisibility(boutonDeverrouiller, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.Center)) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(
                        Modifier
                            .size(64.dp)
                            .clip(CircleShape)
                            .background(Elara.degrade)
                            .clickable { verrouille = false; boutonDeverrouiller = false; rearmer() },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Filled.LockOpen, stringResource(R.string.deverrouiller_ecran), tint = Color.White)
                    }
                    Spacer(Modifier.height(8.dp))
                    Text(stringResource(R.string.toucher_deverrouiller), color = Color.White.copy(alpha = 0.8f), fontSize = 12.sp)
                }
            }
        }

        saut?.let { avant ->
            Box(
                Modifier
                    .align(if (avant) Alignment.CenterEnd else Alignment.CenterStart)
                    .padding(horizontal = 40.dp)
                    .size(96.dp)
                    .clip(CircleShape)
                    .background(Elara.accent.copy(alpha = 0.55f)),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(if (avant) Icons.Rounded.Forward10 else Icons.Rounded.Replay10, null,
                        tint = Color.White, modifier = Modifier.size(36.dp))
                    Text(if (avant) "+10 s" else "−10 s", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                }
            }
        }

        AnimatedVisibility(visibles && !verrouille, enter = fadeIn(), exit = fadeOut()) {
            Box(Modifier.fillMaxSize()) {
                // Dégradés haut et bas pour lire les commandes sur n'importe quelle image.
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(160.dp)
                        .align(Alignment.TopCenter)
                        .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.7f), Color.Transparent))),
                )
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(200.dp)
                        .align(Alignment.BottomCenter)
                        .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.8f)))),
                )

                Column(Modifier.fillMaxSize().safeDrawingPadding()) {
                    Entete(clair = true, activite = activite, surVerrouiller = { verrouille = true; boutonDeverrouiller = false })
                    Spacer(Modifier.weight(1f))
                    Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
                        BarreElara(
                            valeur = glisse ?: Lecteur.position,
                            total = Lecteur.duree,
                            surChangement = { glisse = it; rearmer() },
                            surFin = { Lecteur.chercher(it); glisse = null; rearmer() },
                        )
                        Row(Modifier.fillMaxWidth()) {
                            Text(Format.duree(glisse ?: Lecteur.position), color = Color.White.copy(alpha = 0.85f), fontSize = 12.sp)
                            Spacer(Modifier.weight(1f))
                            // Toucher la durée : affiche le temps restant.
                            Text(
                                if (tempsRestant) "−" + Format.duree((Lecteur.duree - (glisse ?: Lecteur.position)).coerceAtLeast(0))
                                else Format.duree(Lecteur.duree),
                                color = Color.White.copy(alpha = 0.85f), fontSize = 12.sp,
                                modifier = Modifier.clickable { tempsRestant = !tempsRestant; rearmer() },
                            )
                        }
                        Spacer(Modifier.height(8.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            MenuVitesse { rearmer() }
                            Spacer(Modifier.width(10.dp))
                            Pastille(onClick = { mode = (mode + 1) % 3; rearmer() }) {
                                Icon(
                                    when (mode) { 0 -> Icons.Filled.FitScreen; 1 -> Icons.Filled.Fullscreen; else -> Icons.Filled.AspectRatio },
                                    stringResource(when (mode) { 0 -> R.string.ajuster_ecran; 1 -> R.string.remplir_ecran; else -> R.string.etirer }),
                                    tint = Color.White,
                                )
                            }
                            if (Lecteur.repeterUn) {
                                Spacer(Modifier.width(10.dp))
                                Pastille(onClick = { Lecteur.repeterUn = false; rearmer() }) {
                                    Icon(Icons.Filled.RepeatOne, stringResource(R.string.ne_plus_repeter), tint = Elara.accent)
                                }
                            }
                            Spacer(Modifier.weight(1f))
                            Pastille(onClick = { verrouille = true; boutonDeverrouiller = false }) {
                                Icon(Icons.Filled.Lock, stringResource(R.string.verrouiller_ecran), tint = Color.White)
                            }
                            Spacer(Modifier.width(10.dp))
                            if (activite.peutPip()) {
                                Pastille(onClick = { activite.entrerPip() }) {
                                    Icon(Icons.Filled.PictureInPictureAlt, stringResource(R.string.image_dans_image), tint = Color.White)
                                }
                            }
                        }
                    }
                }

                CommandesCentre(Modifier.align(Alignment.Center), clair = true, surSaut = { sauter(it) }, surAction = { rearmer() })
            }
        }
    }
}

@Composable
private fun VueVideo(mode: Int, modifier: Modifier) {
    AndroidView(
        factory = { ctx ->
            PlayerView(ctx).apply {
                layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                useController = false
                setShutterBackgroundColor(android.graphics.Color.BLACK)
                setKeepContentOnPlayerReset(true)
                player = Lecteur.player
            }
        },
        update = { vue ->
            if (vue.player !== Lecteur.player) vue.player = Lecteur.player
            vue.resizeMode = when (mode) {
                1 -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                2 -> AspectRatioFrameLayout.RESIZE_MODE_FILL
                else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
            }
        },
        onRelease = { it.player = null },
        modifier = modifier,
    )
}

/** Affichage dans la fenêtre flottante (image dans l'image) : seulement la vidéo. */
@Composable
fun VideoPip() {
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        VueVideo(mode = 0, modifier = Modifier.fillMaxSize())
    }
}

// MARK: - Audio

@Composable
private fun LecteurAudio() {
    var glisse by remember { mutableStateOf<Long?>(null) }
    val echelle by animateFloatAsState(if (Lecteur.enLecture) 1f else 0.92f, label = "pochette")
    val media = Lecteur.mediaActuel ?: return
    Column(
        Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .safeDrawingPadding(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Entete(clair = false)
        Spacer(Modifier.weight(1f))
        Box(
            Modifier
                .size(260.dp)
                .scale(echelle)
                .shadow(24.dp, RoundedCornerShape(32.dp), ambientColor = Elara.accent, spotColor = Elara.accent)
                .clip(RoundedCornerShape(32.dp))
                .background(Elara.degrade),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.MusicNote, null, tint = Color.White, modifier = Modifier.size(110.dp))
        }
        Spacer(Modifier.height(28.dp))
        Text(
            media.nom, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(horizontal = 24.dp),
        )
        if (Lecteur.file.size > 1) {
            Text(
                stringResource(R.string.position_file, Lecteur.index + 1, Lecteur.file.size),
                color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp,
            )
        }
        Spacer(Modifier.height(24.dp))
        Column(Modifier.padding(horizontal = 28.dp)) {
            BarreElara(
                valeur = glisse ?: Lecteur.position,
                total = Lecteur.duree,
                surChangement = { glisse = it },
                surFin = { Lecteur.chercher(it); glisse = null },
                pisteClaire = false,
            )
            Row(Modifier.fillMaxWidth()) {
                Text(Format.duree(glisse ?: Lecteur.position), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
                Spacer(Modifier.weight(1f))
                Text(Format.duree(Lecteur.duree), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
            }
        }
        Spacer(Modifier.height(20.dp))
        CommandesCentre(Modifier, clair = false, surSaut = { Lecteur.sauter(if (it) 10_000 else -10_000) }, surAction = {}, toujoursPistes = true)
        Spacer(Modifier.height(12.dp))
        MenuVitesse(clair = false) {}
        Spacer(Modifier.weight(1f))
    }
}

// MARK: - Éléments communs

@Composable
private fun Entete(clair: Boolean, activite: MainActivity? = null, surVerrouiller: (() -> Unit)? = null) {
    val couleur = if (clair) Color.White else MaterialTheme.colorScheme.onBackground
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { Lecteur.fermer() }) {
            Icon(Icons.Filled.KeyboardArrowDown, stringResource(R.string.fermer_lecteur), tint = couleur, modifier = Modifier.size(32.dp))
        }
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("ELARA", color = Elara.accent, fontSize = 10.sp, fontWeight = FontWeight.Black, letterSpacing = 3.sp)
            Text(
                Lecteur.mediaActuel?.nom ?: "", color = couleur, fontWeight = FontWeight.SemiBold,
                maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
            if (Lecteur.minuterieActive) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Bedtime, null, tint = Elara.accent, modifier = Modifier.size(12.dp))
                    Spacer(Modifier.width(4.dp))
                    Text(
                        Lecteur.minuterieFin?.let {
                            java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT).format(java.util.Date(it))
                        } ?: stringResource(R.string.fin_video),
                        color = Elara.accent, fontSize = 11.sp,
                    )
                }
            }
        }
        if (activite != null) {
            // Pivoter : paysage ↔ portrait.
            IconButton(onClick = {
                val paysage = activite.resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
                activite.requestedOrientation = if (paysage) android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
                else android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            }) {
                Icon(Icons.Filled.ScreenRotation, stringResource(R.string.pivoter_ecran), tint = couleur)
            }
            DisposableEffect(Unit) {
                onDispose { activite.requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED }
            }
        }
        Box {
            IconButton(onClick = { menu = true }) {
                Icon(Icons.Filled.MoreVert, stringResource(R.string.plus_options), tint = couleur)
            }
            MenuLecteur(menu, { menu = false }, surVerrouiller)
        }
    }
}

/** Menu « ⋮ » du lecteur : répéter, minuterie, pistes audio, sous-titres, verrouiller. */
@Composable
private fun MenuLecteur(ouvert: Boolean, fermer: () -> Unit, surVerrouiller: (() -> Unit)?) {
    val version = Lecteur.versionPistes
    val audios = remember(version, ouvert) { Lecteur.pistes(androidx.media3.common.C.TRACK_TYPE_AUDIO) }
    val textes = remember(version, ouvert) { Lecteur.pistes(androidx.media3.common.C.TRACK_TYPE_TEXT) }
    DropdownMenu(expanded = ouvert, onDismissRequest = fermer) {
        DropdownMenuItem(
            text = { Text(stringResource(if (Lecteur.repeterUn) R.string.ne_plus_repeter else R.string.repeter_video)) },
            leadingIcon = { Icon(Icons.Filled.RepeatOne, null, tint = if (Lecteur.repeterUn) Elara.accent else LocalContentColor.current) },
            onClick = { Lecteur.repeterUn = !Lecteur.repeterUn; fermer() },
        )
        HorizontalDivider()
        Titre(stringResource(R.string.minuterie))
        if (Lecteur.minuterieActive) {
            DropdownMenuItem(text = { Text(stringResource(R.string.desactiver_minuterie)) }, onClick = { Lecteur.annulerMinuterie(); fermer() })
        }
        listOf(15, 30, 45, 60, 90).forEach { m ->
            DropdownMenuItem(text = { Text("$m min") }, onClick = { Lecteur.programmerMinuterie(m); fermer() })
        }
        DropdownMenuItem(text = { Text(stringResource(R.string.fin_video)) }, onClick = { Lecteur.programmerMinuterie(null); fermer() })
        if (audios.size > 1) {
            HorizontalDivider()
            Titre(stringResource(R.string.piste_audio))
            audios.forEach { p ->
                DropdownMenuItem(
                    text = { Text(p.nom) },
                    trailingIcon = { if (p.choisie) Icon(Icons.Filled.Check, null, tint = Elara.accent) },
                    onClick = { Lecteur.choisirPiste(androidx.media3.common.C.TRACK_TYPE_AUDIO, p); fermer() },
                )
            }
        }
        if (textes.isNotEmpty()) {
            HorizontalDivider()
            Titre(stringResource(R.string.sous_titres))
            DropdownMenuItem(
                text = { Text(stringResource(R.string.desactives)) },
                trailingIcon = { if (textes.none { it.choisie }) Icon(Icons.Filled.Check, null, tint = Elara.accent) },
                onClick = { Lecteur.choisirPiste(androidx.media3.common.C.TRACK_TYPE_TEXT, null); fermer() },
            )
            textes.forEach { p ->
                DropdownMenuItem(
                    text = { Text(p.nom) },
                    trailingIcon = { if (p.choisie) Icon(Icons.Filled.Check, null, tint = Elara.accent) },
                    onClick = { Lecteur.choisirPiste(androidx.media3.common.C.TRACK_TYPE_TEXT, p); fermer() },
                )
            }
        }
        if (surVerrouiller != null) {
            HorizontalDivider()
            DropdownMenuItem(
                text = { Text(stringResource(R.string.verrouiller_ecran)) },
                leadingIcon = { Icon(Icons.Filled.Lock, null) },
                onClick = { surVerrouiller(); fermer() },
            )
        }
    }
}

@Composable
private fun Titre(texte: String) {
    Text(
        texte, fontWeight = FontWeight.SemiBold, fontSize = 13.sp,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
    )
}

@Composable
private fun CommandesCentre(
    modifier: Modifier,
    clair: Boolean,
    surSaut: (Boolean) -> Unit,
    surAction: () -> Unit,
    toujoursPistes: Boolean = false,
) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(18.dp)) {
        if (Lecteur.file.size > 1 || toujoursPistes) {
            BoutonRond(Icons.Filled.SkipPrevious, stringResource(R.string.precedent), clair, 26) { Lecteur.precedent(); surAction() }
        }
        BoutonRond(Icons.Rounded.Replay10, stringResource(R.string.reculer_10), clair, 30) { surSaut(false) }
        Box(
            Modifier
                .size(78.dp)
                .shadow(18.dp, CircleShape, ambientColor = Elara.accent, spotColor = Elara.accent)
                .clip(CircleShape)
                .background(Elara.degrade)
                .clickable { Lecteur.basculerLecture(); surAction() },
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (Lecteur.enLecture) Icons.Filled.Pause else if (Lecteur.termine) Icons.Filled.Replay else Icons.Filled.PlayArrow,
                stringResource(if (Lecteur.enLecture) R.string.pause else R.string.lecture),
                tint = Color.White, modifier = Modifier.size(40.dp),
            )
        }
        BoutonRond(Icons.Rounded.Forward10, stringResource(R.string.avancer_10), clair, 30) { surSaut(true) }
        if (Lecteur.file.size > 1 || toujoursPistes) {
            BoutonRond(Icons.Filled.SkipNext, stringResource(R.string.suivant), clair, 26) { Lecteur.suivant(); surAction() }
        }
    }
}

@Composable
private fun BoutonRond(icone: ImageVector, titre: String, clair: Boolean, taille: Int, action: () -> Unit) {
    Box(
        Modifier
            .size(52.dp)
            .clip(CircleShape)
            .background(if (clair) Color.White.copy(alpha = 0.16f) else MaterialTheme.colorScheme.surfaceVariant)
            .clickable(onClick = action),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icone, titre, tint = if (clair) Color.White else MaterialTheme.colorScheme.onSurface, modifier = Modifier.size(taille.dp))
    }
}

@Composable
private fun Pastille(onClick: () -> Unit, contenu: @Composable () -> Unit) {
    Box(
        Modifier
            .height(36.dp)
            .widthIn(min = 44.dp)
            .clip(RoundedCornerShape(50))
            .background(Color.White.copy(alpha = 0.16f))
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) { contenu() }
}

@Composable
private fun MenuVitesse(clair: Boolean = true, surChoix: () -> Unit) {
    var ouvert by remember { mutableStateOf(false) }
    val vitesses = listOf(0.25f, 0.5f, 0.75f, 1f, 1.25f, 1.5f, 1.75f, 2f, 3f)
    fun libelle(v: Float) = if (v == v.toInt().toFloat()) "${v.toInt()}×" else "${v}×"
    Box {
        Box(
            Modifier
                .height(36.dp)
                .clip(RoundedCornerShape(50))
                .background(if (clair) Color.White.copy(alpha = 0.16f) else MaterialTheme.colorScheme.surfaceVariant)
                .clickable { ouvert = true }
                .padding(horizontal = 14.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                libelle(Lecteur.vitesse), fontWeight = FontWeight.Bold,
                color = if (clair) Color.White else MaterialTheme.colorScheme.onSurface,
            )
        }
        DropdownMenu(expanded = ouvert, onDismissRequest = { ouvert = false }) {
            Text(
                stringResource(R.string.vitesse), fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
            )
            vitesses.forEach { v ->
                DropdownMenuItem(
                    text = { Text(libelle(v)) },
                    trailingIcon = { if (Lecteur.vitesse == v) Icon(Icons.Filled.Check, null, tint = Elara.accent) },
                    onClick = { Lecteur.definirVitesse(v); ouvert = false; surChoix() },
                )
            }
        }
    }
}

/** Barre de progression aux couleurs d'Elara (dégradé violet → bleu). */
@Composable
fun BarreElara(
    valeur: Long,
    total: Long,
    surChangement: (Long) -> Unit,
    surFin: (Long) -> Unit,
    pisteClaire: Boolean = true,
) {
    var actif by remember { mutableStateOf(false) }
    val totalActuel by rememberUpdatedState(total)
    val changement by rememberUpdatedState(surChangement)
    val fin by rememberUpdatedState(surFin)
    val epaisseur by animateFloatAsState(if (actif) 8f else 5f, label = "épaisseur")
    val rayon by animateFloatAsState(if (actif) 11f else 7f, label = "bouton")
    val piste = if (pisteClaire) Color.White.copy(alpha = 0.28f) else MaterialTheme.colorScheme.surfaceVariant
    val bouton = if (pisteClaire) Color.White else Elara.accent

    Canvas(
        Modifier
            .fillMaxWidth()
            .height(30.dp)
            .pointerInput(Unit) {
                awaitEachGesture {
                    val premier = awaitFirstDown()
                    actif = true
                    fun valeurA(x: Float): Long =
                        ((x / size.width).coerceIn(0f, 1f) * totalActuel.coerceAtLeast(0)).toLong()
                    var derniere = valeurA(premier.position.x)
                    changement(derniere)
                    drag(premier.id) { c ->
                        c.consume()
                        derniere = valeurA(c.position.x)
                        changement(derniere)
                    }
                    actif = false
                    fin(derniere)
                }
            },
    ) {
        val part = if (total > 0) (valeur.toFloat() / total).coerceIn(0f, 1f) else 0f
        val e = epaisseur.dp.toPx()
        val y = size.height / 2
        drawRoundRect(piste, Offset(0f, y - e / 2), Size(size.width, e), CornerRadius(e / 2))
        if (part > 0f) {
            drawRoundRect(
                Brush.horizontalGradient(listOf(Elara.violet, Elara.bleu), 0f, size.width),
                Offset(0f, y - e / 2), Size(size.width * part, e), CornerRadius(e / 2),
            )
        }
        drawCircle(Elara.accent.copy(alpha = 0.35f), rayon.dp.toPx() + 4.dp.toPx(), Offset(size.width * part, y))
        drawCircle(bouton, rayon.dp.toPx(), Offset(size.width * part, y))
    }
}
