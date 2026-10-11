package com.kounandi.elara.ui.commun

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DriveFileMove
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.kounandi.elara.R
import com.kounandi.elara.donnees.Bibliotheque
import com.kounandi.elara.donnees.Dossier
import com.kounandi.elara.donnees.Format
import com.kounandi.elara.donnees.Galerie
import com.kounandi.elara.donnees.Media
import com.kounandi.elara.donnees.TypeMedia
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Une ligne de média : miniature, nom, durée, taille, progression et menu d'actions. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LigneMedia(
    media: Media,
    dossiers: List<Dossier>,
    selection: Selection? = null,
    surLecture: () -> Unit,
) {
    val enSelection = selection?.actif == true
    val choisi = selection != null && media.id in selection.ids
    var menu by remember { mutableStateOf(false) }
    var renommer by remember { mutableStateOf(false) }
    var deplacer by remember { mutableStateOf(false) }
    var supprimer by remember { mutableStateOf(false) }
    val contexte = LocalContext.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()

    Row(
        Modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = { if (enSelection) selection?.basculer(media.id) else surLecture() },
                onLongClick = {
                    // Appui long : passe en mode sélection avec ce média coché.
                    if (selection != null) {
                        if (!selection.actif) selection.actif = true
                        selection.basculer(media.id)
                    } else menu = true
                },
            )
            .background(if (choisi) Elara.accent.copy(alpha = 0.12f) else Color.Transparent)
            .padding(horizontal = 20.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (enSelection) {
            Icon(
                if (choisi) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null,
                tint = if (choisi) Elara.accent else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(end = 12.dp).size(26.dp),
            )
        }
        Miniature(media, Modifier.size(width = 104.dp, height = 62.dp))
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(media.nom, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(
                "${Format.duree(media.duree)} · ${Format.taille(media.taille)}",
                color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp,
            )
            if (media.position > 0 && media.duree > 0) {
                Spacer(Modifier.height(6.dp))
                LinearProgressIndicator(
                    progress = { (media.position.toFloat() / media.duree).coerceIn(0f, 1f) },
                    modifier = Modifier.width(120.dp).height(4.dp).clip(RoundedCornerShape(2.dp)),
                    color = Elara.accent,
                    trackColor = MaterialTheme.colorScheme.surfaceVariant,
                )
            }
        }
        if (!enSelection) Box {
            IconButton(onClick = { menu = true }) {
                Icon(Icons.Filled.MoreVert, stringResource(R.string.actions))
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.renommer)) },
                    leadingIcon = { Icon(Icons.Filled.Edit, null) },
                    onClick = { menu = false; renommer = true },
                )
                if (!media.prive) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.deplacer)) },
                        leadingIcon = { Icon(Icons.AutoMirrored.Filled.DriveFileMove, null) },
                        onClick = { menu = false; deplacer = true },
                    )
                }
                DropdownMenuItem(
                    text = { Text(stringResource(if (media.prive) R.string.retirer_prive else R.string.mettre_prive)) },
                    leadingIcon = { Icon(if (media.prive) Icons.Filled.LockOpen else Icons.Filled.Lock, null) },
                    onClick = { menu = false; Bibliotheque.basculerPrive(media) },
                )
                if (media.type == TypeMedia.VIDEO || media.type == TypeMedia.AUDIO) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.enregistrer_galerie)) },
                        leadingIcon = { Icon(Icons.Filled.Download, null) },
                        onClick = {
                            menu = false
                            scope.launch {
                                val n = Galerie.enregistrer(contexte, listOf(media))
                                android.widget.Toast.makeText(
                                    contexte,
                                    if (n > 0) contexte.getString(R.string.enregistres_galerie, n) else contexte.getString(R.string.erreur_galerie),
                                    android.widget.Toast.LENGTH_LONG,
                                ).show()
                            }
                        },
                    )
                }
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.partager)) },
                    leadingIcon = { Icon(Icons.Filled.Share, null) },
                    onClick = { menu = false; partager(contexte, media) },
                )
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.supprimer), color = Elara.corail) },
                    leadingIcon = { Icon(Icons.Filled.Delete, null, tint = Elara.corail) },
                    onClick = { menu = false; supprimer = true },
                )
            }
        }
    }

    if (renommer) {
        DialogueNom(
            titre = stringResource(R.string.renommer),
            initial = media.nom,
            longueurMax = 120,
            surValider = { Bibliotheque.renommer(media, it) },
            surFermer = { renommer = false },
        )
    }
    if (deplacer) {
        AlertDialog(
            onDismissRequest = { deplacer = false },
            title = { Text(stringResource(R.string.deplacer_vers)) },
            text = {
                Column {
                    TextButton(onClick = { Bibliotheque.deplacer(media, null); deplacer = false }) {
                        Text(stringResource(R.string.accueil_racine))
                    }
                    dossiers.forEach { d ->
                        TextButton(onClick = { Bibliotheque.deplacer(media, d.id); deplacer = false }) {
                            Text(d.nom, fontWeight = if (media.dossier == d.id) FontWeight.Bold else FontWeight.Normal)
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { deplacer = false }) { Text(stringResource(R.string.annuler)) } },
        )
    }
    if (supprimer) {
        AlertDialog(
            onDismissRequest = { supprimer = false },
            title = { Text(stringResource(R.string.supprimer_titre)) },
            text = { Text(media.nom) },
            confirmButton = {
                TextButton(onClick = { Bibliotheque.supprimer(media); supprimer = false }) {
                    Text(stringResource(R.string.supprimer), color = Elara.corail)
                }
            },
            dismissButton = { TextButton(onClick = { supprimer = false }) { Text(stringResource(R.string.annuler)) } },
        )
    }
}

@Composable
fun Miniature(media: Media, modifier: Modifier) {
    var image by remember(media.id) { mutableStateOf<ImageBitmap?>(null) }
    LaunchedEffect(media.id) {
        image = withContext(Dispatchers.IO) {
            Bibliotheque.miniature(media)?.let { f -> BitmapFactory.decodeFile(f.absolutePath)?.asImageBitmap() }
        }
    }
    Box(
        modifier
            .clip(RoundedCornerShape(12.dp))
            .background(Elara.degrade),
        contentAlignment = Alignment.Center,
    ) {
        val img = image
        if (img != null) {
            Image(img, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        } else {
            Icon(
                if (media.type == TypeMedia.AUDIO) Icons.Filled.MusicNote else Icons.Filled.Movie,
                null, tint = Color.White, modifier = Modifier.size(28.dp),
            )
        }
    }
}

/** Boîte de dialogue pour saisir un nom (dossier, média…). */
@Composable
fun DialogueNom(
    titre: String,
    initial: String,
    longueurMax: Int,
    surValider: (String) -> Unit,
    surFermer: () -> Unit,
) {
    var texte by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = surFermer,
        title = { Text(titre) },
        text = {
            OutlinedTextField(
                value = texte,
                onValueChange = { texte = it.take(longueurMax) },
                singleLine = true,
                supportingText = { if (longueurMax <= 40) Text("${texte.length}/$longueurMax") },
            )
        },
        confirmButton = {
            TextButton(
                enabled = texte.isNotBlank(),
                onClick = { surValider(texte.trim()); surFermer() },
            ) { Text(stringResource(R.string.ok)) }
        },
        dismissButton = { TextButton(onClick = surFermer) { Text(stringResource(R.string.annuler)) } },
    )
}

fun partager(contexte: Context, media: Media) {
    val fichier = Bibliotheque.fichier(media)
    val uri = FileProvider.getUriForFile(contexte, contexte.packageName + ".fichiers", fichier)
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = if (media.type == TypeMedia.AUDIO) "audio/*" else "video/*"
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    com.kounandi.elara.MainActivity.actuelle?.garderOuvert = true
    contexte.startActivity(Intent.createChooser(intent, null))
}
