package com.kounandi.elara.ui.facebook

import android.view.ViewGroup
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.FullscreenExit
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.KeyboardDoubleArrowRight
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.kounandi.elara.R
import com.kounandi.elara.donnees.Format
import com.kounandi.elara.donnees.Media
import com.kounandi.elara.donnees.Telechargeur
import com.kounandi.elara.ui.commun.Elara
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun FacebookEcran(marges: PaddingValues, pleinEcran: Boolean, changerPleinEcran: (Boolean) -> Unit) {
    val contexte = LocalContext.current
    val scope = rememberCoroutineScope()
    var menu by remember { mutableStateOf(false) }
    var deconnexion by remember { mutableStateOf(false) }
    var erreur by remember { mutableStateOf<String?>(null) }
    var ajoute by remember { mutableStateOf<Media?>(null) }
    var succesImage by remember { mutableStateOf(false) }
    var enregistrementImage by remember { mutableStateOf(false) }

    // Plein écran : on cache aussi les barres d'Android (on les fait réapparaître en glissant depuis le bord).
    val activite = contexte as? android.app.Activity
    DisposableEffect(pleinEcran) {
        val fenetre = activite?.window
        val controle = fenetre?.let { WindowCompat.getInsetsController(it, it.decorView) }
        if (pleinEcran) {
            controle?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controle?.hide(WindowInsetsCompat.Type.systemBars())
        } else {
            controle?.show(WindowInsetsCompat.Type.systemBars())
        }
        onDispose { controle?.show(WindowInsetsCompat.Type.systemBars()) }
    }

    // Plein écran automatique sur les Reels.
    LaunchedEffect(NavigateurFacebook.surReel) { changerPleinEcran(NavigateurFacebook.surReel) }
    BackHandler(enabled = NavigateurFacebook.peutReculer) { NavigateurFacebook.reculer() }
    // Une nouvelle vidéo démarre : on remplace « Vidéo ajoutée » / l'erreur par la proposition de télécharger.
    LaunchedEffect(NavigateurFacebook.video) {
        if (NavigateurFacebook.video != null && !Telechargeur.enCours) {
            ajoute = null
            erreur = null
        }
    }

    fun enregistrerImage(lien: String) {
        enregistrementImage = true
        scope.launch {
            val ok = com.kounandi.elara.donnees.Galerie.enregistrerImage(contexte, lien)
            enregistrementImage = false
            NavigateurFacebook.imageDetectee = null
            if (ok) {
                succesImage = true
                delay(2500)
                succesImage = false
            } else {
                erreur = contexte.getString(R.string.erreur_image)
                delay(6000)
                erreur = null
            }
        }
    }

    fun telecharger(video: VideoDetectee?) {
        erreur = null
        ajoute = null
        NavigateurFacebook.video = null
        scope.launch {
            try {
                val source = NavigateurFacebook.source(video)
                    ?: throw Exception(contexte.getString(R.string.erreur_introuvable))
                val media = when (source) {
                    is SourceFacebook.Direct -> Telechargeur.telecharger(contexte, source.lien, false, NavigateurFacebook.sonsRecents())
                    is SourceFacebook.Flux -> Telechargeur.telechargerFlux(contexte, source.liens, false)
                }
                NavigateurFacebook.marquerTelechargee(video)
                ajoute = media
                // Le bandeau « Vidéo ajoutée » se ferme tout seul.
                delay(2500)
                if (ajoute == media) ajoute = null
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                val message = e.message ?: contexte.getString(R.string.erreur_inconnue)
                erreur = message
                delay(6000)
                if (erreur == message) erreur = null
            }
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .padding(bottom = if (pleinEcran) 0.dp else marges.calculateBottomPadding()),
    ) {
        if (!pleinEcran) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.surface)
                    .statusBarsPadding()
                    .padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = { NavigateurFacebook.reculer() }, enabled = NavigateurFacebook.peutReculer) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.page_precedente))
                }
                IconButton(onClick = { NavigateurFacebook.avancer() }, enabled = NavigateurFacebook.peutAvancer) {
                    Icon(Icons.AutoMirrored.Filled.ArrowForward, stringResource(R.string.page_suivante))
                }
                Text("Facebook", fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.weight(1f).padding(start = 8.dp))
                IconButton(onClick = { telecharger(null) }, enabled = !Telechargeur.enCours) {
                    Icon(Icons.Filled.Download, stringResource(R.string.telecharger_video_affichee), tint = Elara.accent)
                }
                Box {
                    IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, stringResource(R.string.actions)) }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.plein_ecran)) },
                            leadingIcon = { Icon(Icons.Filled.Fullscreen, null) },
                            onClick = { menu = false; changerPleinEcran(true) },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.recharger)) },
                            leadingIcon = { Icon(Icons.Filled.Refresh, null) },
                            onClick = { menu = false; NavigateurFacebook.recharger() },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.fil_actualite)) },
                            leadingIcon = { Icon(Icons.Filled.Home, null) },
                            onClick = { menu = false; NavigateurFacebook.allerAccueil() },
                        )
                        HorizontalDivider()
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.se_deconnecter), color = Elara.corail) },
                            leadingIcon = { Icon(Icons.AutoMirrored.Filled.Logout, null, tint = Elara.corail) },
                            onClick = { menu = false; deconnexion = true },
                        )
                    }
                }
            }
            if (NavigateurFacebook.chargement) {
                LinearProgressIndicator(Modifier.fillMaxWidth(), color = Elara.accent)
            }
        }

        Box(Modifier.weight(1f).fillMaxWidth()) {
            AndroidView(
                factory = { ctx ->
                    NavigateurFacebook.vue(ctx).also { v ->
                        (v.parent as? ViewGroup)?.removeView(v)
                        v.layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    }
                },
                onRelease = { v -> (v.parent as? ViewGroup)?.removeView(v) },
                modifier = Modifier.fillMaxSize(),
            )

            if (pleinEcran) {
                // Sur le côté gauche, au milieu : ne cache ni les boutons de Facebook ni ceux des Reels.
                Column(
                    Modifier.align(Alignment.CenterStart).padding(10.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    BoutonFlottant(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.page_precedente)) { NavigateurFacebook.reculer() }
                    BoutonFlottant(Icons.Filled.Download, stringResource(R.string.telecharger_video_affichee)) {
                        if (!Telechargeur.enCours) telecharger(null)
                    }
                    BoutonFlottant(Icons.Filled.FullscreenExit, stringResource(R.string.quitter_plein_ecran)) { changerPleinEcran(false) }
                }
            }

            Box(
                Modifier
                    .align(Alignment.BottomCenter)
                    .then(if (pleinEcran) Modifier.navigationBarsPadding() else Modifier)
                    .widthIn(max = 640.dp)
                    .padding(12.dp),
            ) {
                Bandeau(
                    erreur = erreur,
                    ajoute = ajoute,
                    succesImage = succesImage,
                    enregistrementImage = enregistrementImage,
                    surEnregistrerImage = { enregistrerImage(it) },
                    fermerSuccesImage = { succesImage = false },
                    surTelecharger = { telecharger(it) },
                    fermerErreur = { erreur = null },
                    fermerAjoute = { ajoute = null },
                )
            }
        }
    }

    if (deconnexion) {
        AlertDialog(
            onDismissRequest = { deconnexion = false },
            title = { Text(stringResource(R.string.deconnexion_titre)) },
            confirmButton = {
                TextButton(onClick = { deconnexion = false; NavigateurFacebook.deconnecter() }) {
                    Text(stringResource(R.string.se_deconnecter), color = Elara.corail)
                }
            },
            dismissButton = { TextButton(onClick = { deconnexion = false }) { Text(stringResource(R.string.annuler)) } },
        )
    }
}

@Composable
private fun BoutonFlottant(icone: ImageVector, titre: String, action: () -> Unit) {
    Box(
        Modifier
            .size(42.dp)
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.5f))
            .clickable(onClick = action),
        contentAlignment = Alignment.Center,
    ) { Icon(icone, titre, tint = Color.White, modifier = Modifier.size(22.dp)) }
}

@Composable
private fun Bandeau(
    erreur: String?,
    ajoute: Media?,
    succesImage: Boolean,
    enregistrementImage: Boolean,
    surEnregistrerImage: (String) -> Unit,
    fermerSuccesImage: () -> Unit,
    surTelecharger: (VideoDetectee) -> Unit,
    fermerErreur: () -> Unit,
    fermerAjoute: () -> Unit,
) {
    // Pendant un téléchargement, le bandeau se range sur le côté (petite pastille) pour libérer la vidéo.
    var deploye by remember { mutableStateOf(false) }
    LaunchedEffect(Telechargeur.enCours) { if (Telechargeur.enCours) deploye = false }
    if (Telechargeur.enCours && !deploye) {
        Row(Modifier.fillMaxWidth().padding(bottom = 70.dp), horizontalArrangement = Arrangement.End) {
            Box(
                Modifier
                    .size(58.dp)
                    .shadow(8.dp, CircleShape)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.6f))
                    .clickable { deploye = true },
                contentAlignment = Alignment.Center,
            ) {
                if (Telechargeur.recherche || Telechargeur.progression <= 0f) {
                    CircularProgressIndicator(Modifier.size(44.dp), color = Elara.accent, strokeWidth = 4.dp)
                } else {
                    CircularProgressIndicator(
                        progress = { Telechargeur.progression }, modifier = Modifier.size(44.dp),
                        color = Elara.accent, strokeWidth = 4.dp, trackColor = Color.White.copy(alpha = 0.25f),
                    )
                    Text("${(Telechargeur.progression * 100).toInt()}%", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
        return
    }
    val video = NavigateurFacebook.video
    val image = NavigateurFacebook.imageDetectee
    val visible = Telechargeur.enCours || erreur != null || ajoute != null || video != null || image != null || succesImage
    AnimatedVisibility(visible, enter = slideInVertically { it }, exit = slideOutVertically { it }) {
        Row(
            Modifier
                .fillMaxWidth()
                .pointerInput(Telechargeur.enCours) {
                    // Glisser vers la droite pendant un téléchargement : range le bandeau sur le côté.
                    var total = 0f
                    detectHorizontalDragGestures(
                        onDragStart = { total = 0f },
                        onDragEnd = { if (total > 120f && Telechargeur.enCours) deploye = false },
                        onHorizontalDrag = { _, dx -> total += dx },
                    )
                }
                .shadow(12.dp, RoundedCornerShape(20.dp))
                .clip(RoundedCornerShape(20.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            when {
                Telechargeur.enCours -> {
                    if (Telechargeur.recherche || Telechargeur.progression <= 0f) {
                        CircularProgressIndicator(Modifier.size(26.dp), color = Elara.accent, strokeWidth = 3.dp)
                    } else {
                        CircularProgressIndicator(progress = { Telechargeur.progression }, modifier = Modifier.size(26.dp), color = Elara.accent, strokeWidth = 3.dp)
                    }
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            stringResource(if (Telechargeur.recherche) R.string.recherche_video else R.string.telechargement),
                            fontWeight = FontWeight.Bold, fontSize = 15.sp,
                        )
                        if (!Telechargeur.recherche) {
                            Text(
                                "${(Telechargeur.progression * 100).toInt()} % · ${Format.taille(Telechargeur.octets)}",
                                fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    TextButton(onClick = { Telechargeur.annuler() }) { Text(stringResource(R.string.annuler), color = Elara.corail) }
                    IconButton(onClick = { deploye = false }) {
                        Icon(Icons.Filled.KeyboardDoubleArrowRight, stringResource(R.string.reduire))
                    }
                }
                erreur != null -> {
                    Icon(Icons.Filled.Warning, null, tint = Color(0xFFFFA726))
                    Spacer(Modifier.width(12.dp))
                    Text(erreur, fontSize = 14.sp, modifier = Modifier.weight(1f))
                    Fermer(fermerErreur)
                }
                ajoute != null -> {
                    Icon(Icons.Filled.CheckCircle, null, tint = Elara.vert, modifier = Modifier.size(28.dp))
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            stringResource(
                                if (com.kounandi.elara.donnees.Bibliotheque.doublon.value?.id == ajoute.id) R.string.deja_dans_elara
                                else R.string.video_ajoutee,
                            ),
                            fontWeight = FontWeight.Bold, fontSize = 15.sp,
                        )
                        Text(ajoute.nom, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Fermer(fermerAjoute)
                }
                succesImage -> {
                    Icon(Icons.Filled.CheckCircle, null, tint = Elara.vert, modifier = Modifier.size(28.dp))
                    Spacer(Modifier.width(12.dp))
                    Text(stringResource(R.string.image_enregistree), fontWeight = FontWeight.Bold, fontSize = 15.sp, modifier = Modifier.weight(1f))
                    Fermer(fermerSuccesImage)
                }
                image != null -> {
                    Icon(Icons.Filled.Image, null, tint = Elara.accent, modifier = Modifier.size(28.dp))
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(R.string.image), fontWeight = FontWeight.Bold, fontSize = 15.sp)
                        Text(stringResource(R.string.enregistrer_image_question), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (enregistrementImage) {
                        CircularProgressIndicator(Modifier.size(24.dp), color = Elara.accent, strokeWidth = 3.dp)
                    } else {
                        Button(
                            onClick = { surEnregistrerImage(image) },
                            colors = ButtonDefaults.buttonColors(containerColor = Elara.accent),
                            contentPadding = PaddingValues(horizontal = 14.dp),
                        ) { Text(stringResource(R.string.enregistrer_galerie)) }
                    }
                    Fermer { NavigateurFacebook.imageDetectee = null }
                }
                video != null -> {
                    Icon(Icons.Filled.PlayCircle, null, tint = Elara.accent, modifier = Modifier.size(28.dp))
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(R.string.video_en_lecture), fontWeight = FontWeight.Bold, fontSize = 15.sp)
                        Text(stringResource(R.string.la_telecharger), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Button(
                        onClick = { surTelecharger(video) },
                        colors = ButtonDefaults.buttonColors(containerColor = Elara.accent),
                        contentPadding = PaddingValues(horizontal = 14.dp),
                    ) { Text(stringResource(R.string.telecharger)) }
                    Fermer { NavigateurFacebook.fermerBandeau() }
                }
            }
        }
    }
}

@Composable
private fun Fermer(action: () -> Unit) {
    IconButton(onClick = action, modifier = Modifier.size(48.dp)) {
        Box(
            Modifier.size(32.dp).clip(CircleShape).background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Close, stringResource(R.string.fermer), tint = MaterialTheme.colorScheme.onSurface, modifier = Modifier.size(18.dp))
        }
    }
}
