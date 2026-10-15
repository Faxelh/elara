package com.kounandi.elara.ui.commun

import android.graphics.Bitmap
import android.graphics.RectF
import android.media.MediaMetadataRetriever
import android.widget.Toast
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.kounandi.elara.R
import com.kounandi.elara.donnees.Bibliotheque
import com.kounandi.elara.donnees.Filigrane
import com.kounandi.elara.donnees.Media
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

private val positions = listOf(
    R.string.coin_haut_gauche to RectF(0.03f, 0.04f, 0.39f, 0.12f),
    R.string.coin_haut_droite to RectF(0.61f, 0.04f, 0.97f, 0.12f),
    R.string.coin_bas_gauche to RectF(0.03f, 0.86f, 0.39f, 0.94f),
    R.string.coin_bas_droite to RectF(0.61f, 0.86f, 0.97f, 0.94f),
    R.string.coin_bas_centre to RectF(0.25f, 0.86f, 0.75f, 0.94f),
)

/** Masquer un filigrane sur une ou plusieurs vidéos : on place des zones, Elara les floute. */
@Composable
fun FiligraneEcran(medias: List<Media>, fermer: () -> Unit) {
    val contexte = LocalContext.current
    val scope = rememberCoroutineScope()
    var apercu by remember { mutableStateOf<Bitmap?>(null) }
    val zones = remember { mutableStateListOf(RectF(positions[3].second)) }
    var choisie by remember { mutableIntStateOf(0) }
    var garder by remember { mutableStateOf(false) }
    var mode by remember { mutableStateOf(Filigrane.Mode.EFFACER) }
    var enCours by remember { mutableStateOf(false) }
    var rang by remember { mutableIntStateOf(0) }
    var progression by remember { mutableStateOf(0f) }
    var menuPosition by remember { mutableStateOf(false) }
    var tache by remember { mutableStateOf<Job?>(null) }

    LaunchedEffect(medias) {
        val premier = medias.firstOrNull() ?: return@LaunchedEffect
        apercu = withContext(Dispatchers.IO) {
            runCatching {
                val r = MediaMetadataRetriever()
                r.setDataSource(Bibliotheque.fichier(premier).absolutePath)
                val image = r.getFrameAtTime(1_000_000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                r.release()
                image
            }.getOrNull()
        }
    }

    fun appliquer() {
        val liste = medias
        val choix = zones.map { RectF(it) }
        val methode = mode
        enCours = true
        tache = scope.launch {
            var reussis = 0
            for ((i, media) in liste.withIndex()) {
                rang = i
                progression = 0f
                try {
                    val sortie = Filigrane.traiter(contexte, Bibliotheque.fichier(media), choix, methode) { progression = it }
                    if (garder) {
                        val nouveau = Bibliotheque.importerFichier(sortie, media.nom + " (sans filigrane)", media.prive)
                        if (nouveau != null && media.dossier != null) Bibliotheque.deplacer(nouveau, media.dossier)
                    } else {
                        Bibliotheque.remplacerFichier(media, sortie)
                    }
                    reussis++
                } catch (e: kotlinx.coroutines.CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Toast.makeText(contexte, media.nom + " : " + (e.message ?: contexte.getString(R.string.erreur_inconnue)), Toast.LENGTH_LONG).show()
                }
            }
            enCours = false
            if (reussis > 0) {
                Toast.makeText(contexte, contexte.getString(R.string.filigrane_termine, reussis), Toast.LENGTH_SHORT).show()
                fermer()
            }
        }
    }

    Dialog(
        onDismissRequest = { if (!enCours) fermer() },
        properties = DialogProperties(usePlatformDefaultWidth = false, dismissOnClickOutside = false),
    ) {
        Column(
            Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).statusBarsPadding().navigationBarsPadding(),
        ) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { tache?.cancel(); fermer() }) { Text(stringResource(R.string.fermer), color = Elara.accent) }
                Text(
                    stringResource(R.string.retirer_filigrane), fontWeight = FontWeight.Bold, fontSize = 17.sp,
                    modifier = Modifier.weight(1f), textAlign = TextAlign.Center,
                )
                Spacer(Modifier.size(64.dp))
            }

            // Aperçu de la vidéo avec les zones à flouter.
            Box(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 16.dp), contentAlignment = Alignment.Center) {
                val image = apercu
                val ratio = if (image != null && image.height > 0) image.width.toFloat() / image.height else 9f / 16f
                BoxWithConstraints(Modifier.aspectRatio(ratio, matchHeightConstraintsFirst = ratio < 1f).clip(RoundedCornerShape(12.dp))) {
                    val densite = LocalDensity.current
                    val largeurPx = with(densite) { maxWidth.toPx() }
                    val hauteurPx = with(densite) { maxHeight.toPx() }
                    if (image != null) {
                        Image(image.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.FillBounds)
                    } else {
                        Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(color = Color.White)
                        }
                    }
                    if (mode == Filigrane.Mode.RECADRER) {
                        // Partie coupée, assombrie.
                        val g = Filigrane.partieGardee(zones)
                        val sombre = Color.Black.copy(alpha = 0.6f)
                        androidx.compose.foundation.Canvas(Modifier.fillMaxSize()) {
                            val l = size.width; val h = size.height
                            drawRect(sombre, size = androidx.compose.ui.geometry.Size(l, g.top * h))
                            drawRect(sombre, topLeft = androidx.compose.ui.geometry.Offset(0f, g.bottom * h), size = androidx.compose.ui.geometry.Size(l, (1f - g.bottom) * h))
                            drawRect(sombre, topLeft = androidx.compose.ui.geometry.Offset(0f, g.top * h), size = androidx.compose.ui.geometry.Size(g.left * l, (g.bottom - g.top) * h))
                            drawRect(sombre, topLeft = androidx.compose.ui.geometry.Offset(g.right * l, g.top * h), size = androidx.compose.ui.geometry.Size((1f - g.right) * l, (g.bottom - g.top) * h))
                        }
                    }
                    zones.forEachIndexed { i, z ->
                        val active = i == choisie
                        Box(
                            Modifier
                                .offset { IntOffset((z.left * largeurPx).roundToInt(), (z.top * hauteurPx).roundToInt()) }
                                .size(with(densite) { (z.width() * largeurPx).toDp() }, with(densite) { (z.height() * hauteurPx).toDp() })
                                .background(Color.White.copy(alpha = 0.35f))
                                .border(2.dp, if (active) Elara.accent else Color.White)
                                .pointerInput(i, largeurPx, hauteurPx) {
                                    detectDragGestures(onDragStart = { choisie = i }) { change, d ->
                                        change.consume()
                                        val r = zones[i]
                                        val dx = (d.x / largeurPx).coerceIn(-r.left, 1f - r.right)
                                        val dy = (d.y / hauteurPx).coerceIn(-r.top, 1f - r.bottom)
                                        zones[i] = RectF(r.left + dx, r.top + dy, r.right + dx, r.bottom + dy)
                                    }
                                },
                        ) {
                            // Rond en bas à droite : agrandir / réduire la zone.
                            Box(
                                Modifier
                                    .align(Alignment.BottomEnd)
                                    .size(28.dp)
                                    .padding(4.dp)
                                    .clip(CircleShape)
                                    .background(if (active) Elara.accent else Color.White)
                                    .pointerInput(i, largeurPx, hauteurPx) {
                                        detectDragGestures(onDragStart = { choisie = i }) { change, d ->
                                            change.consume()
                                            val r = zones[i]
                                            val droite = (r.right + d.x / largeurPx).coerceIn(r.left + 0.04f, 1f)
                                            val bas = (r.bottom + d.y / hauteurPx).coerceIn(r.top + 0.04f, 1f)
                                            zones[i] = RectF(r.left, r.top, droite, bas)
                                        }
                                    },
                            )
                        }
                    }
                }
            }

            Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(Filigrane.Mode.EFFACER to R.string.effacer, Filigrane.Mode.RECADRER to R.string.recadrer).forEach { (m, titre) ->
                    val actif = mode == m
                    Button(
                        onClick = { mode = m }, enabled = !enCours, modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (actif) Elara.accent else MaterialTheme.colorScheme.surfaceVariant,
                            contentColor = if (actif) Color.White else MaterialTheme.colorScheme.onSurface,
                        ),
                    ) { Text(stringResource(titre)) }
                }
            }
            Text(
                stringResource(if (mode == Filigrane.Mode.EFFACER) R.string.aide_effacer else R.string.aide_recadrer), fontSize = 13.sp, textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.fillMaxWidth().padding(16.dp, 8.dp),
            )
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box {
                    OutlinedButton(onClick = { menuPosition = true }, enabled = !enCours) { Text(stringResource(R.string.position)) }
                    DropdownMenu(expanded = menuPosition, onDismissRequest = { menuPosition = false }) {
                        positions.forEach { (titre, rect) ->
                            DropdownMenuItem(text = { Text(stringResource(titre)) }, onClick = {
                                if (zones.isEmpty()) { zones.add(RectF(rect)); choisie = 0 } else zones[choisie.coerceIn(0, zones.size - 1)] = RectF(rect)
                                menuPosition = false
                            })
                        }
                    }
                }
                OutlinedButton(onClick = {
                    zones.add(RectF(positions[if (zones.size % 2 == 0) 3 else 0].second))
                    choisie = zones.size - 1
                }, enabled = !enCours && zones.size < 4) { Text(stringResource(R.string.ajouter_zone)) }
                OutlinedButton(onClick = {
                    if (choisie in zones.indices) zones.removeAt(choisie)
                    choisie = (zones.size - 1).coerceAtLeast(0)
                }, enabled = !enCours && zones.isNotEmpty()) { Text(stringResource(R.string.retirer)) }
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = garder, onCheckedChange = { garder = it }, enabled = !enCours)
                Text(stringResource(R.string.garder_original))
            }
            if (enCours) {
                Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                    LinearProgressIndicator(
                        progress = { ((rang + progression) / medias.size.coerceAtLeast(1)).coerceIn(0f, 1f) },
                        modifier = Modifier.fillMaxWidth(), color = Elara.accent,
                    )
                    Text(
                        stringResource(R.string.video_n_sur, rang + 1, medias.size), fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 4.dp),
                    )
                }
            }
            Button(
                onClick = { appliquer() },
                enabled = !enCours && zones.isNotEmpty(),
                colors = ButtonDefaults.buttonColors(containerColor = Elara.accent),
                modifier = Modifier.fillMaxWidth().padding(16.dp).height(50.dp),
            ) {
                Text(
                    if (medias.size <= 1) stringResource(R.string.retirer_filigrane)
                    else stringResource(R.string.retirer_sur_n, medias.size),
                    fontWeight = FontWeight.Bold,
                )
            }
        }
    }
}
