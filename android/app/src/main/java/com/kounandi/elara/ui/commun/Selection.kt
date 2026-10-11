package com.kounandi.elara.ui.commun

import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DriveFileMove
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.kounandi.elara.MainActivity
import com.kounandi.elara.R
import com.kounandi.elara.donnees.Bibliotheque
import com.kounandi.elara.donnees.Dossier
import com.kounandi.elara.donnees.Galerie
import com.kounandi.elara.donnees.Media
import com.kounandi.elara.donnees.TypeMedia
import kotlinx.coroutines.launch

/** Mode « Sélectionner » : plusieurs médias à la fois. */
class Selection {
    var actif by mutableStateOf(false)
    var ids by mutableStateOf(setOf<String>())
        private set

    fun basculer(id: String) { ids = if (id in ids) ids - id else ids + id }
    fun toutBasculer(liste: List<Media>) {
        ids = if (liste.isNotEmpty() && ids.size == liste.size) emptySet() else liste.map { it.id }.toSet()
    }
    fun garderSeulement(liste: List<Media>) {
        val existants = liste.map { it.id }.toSet()
        if (!existants.containsAll(ids)) ids = ids intersect existants
    }
    fun quitter() { actif = false; ids = emptySet() }
}

@Composable
fun rememberSelection(): Selection = remember { Selection() }

/** Ligne au-dessus de la liste : « 12 médias · Sélectionner » ou « Tout sélectionner · 3 · Terminé ». */
@Composable
fun EnteteSelection(selection: Selection, medias: List<Media>) {
    BackHandler(enabled = selection.actif) { selection.quitter() }
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (selection.actif) {
            val tout = medias.isNotEmpty() && selection.ids.size == medias.size
            TextButton(onClick = { selection.toutBasculer(medias) }) {
                Text(stringResource(if (tout) R.string.tout_deselectionner else R.string.tout_selectionner), color = Elara.accent)
            }
            Text(
                stringResource(R.string.n_selectionnes, selection.ids.size),
                fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f),
            )
            TextButton(onClick = { selection.quitter() }) {
                Text(stringResource(R.string.termine), color = Elara.accent, fontWeight = FontWeight.Bold)
            }
        } else {
            Text(
                stringResource(R.string.n_medias, medias.size),
                color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp,
                modifier = Modifier.weight(1f).padding(start = 8.dp),
            )
            if (medias.isNotEmpty()) {
                TextButton(onClick = { selection.actif = true }) {
                    Text(stringResource(R.string.selectionner), color = Elara.accent)
                }
            }
        }
    }
}

/** Barre d'actions en bas pendant la sélection. */
@Composable
fun BarreSelection(selection: Selection, medias: List<Media>, dossiers: List<Dossier>, modifier: Modifier = Modifier) {
    if (!selection.actif) return
    val contexte = LocalContext.current
    val scope = rememberCoroutineScope()
    val choisis = medias.filter { it.id in selection.ids }
    var deplacer by remember { mutableStateOf(false) }
    var supprimer by remember { mutableStateOf(false) }
    var enregistrement by remember { mutableStateOf(false) }

    fun enregistrer() {
        enregistrement = true
        scope.launch {
            val n = Galerie.enregistrer(contexte, choisis)
            enregistrement = false
            val texte = if (n > 0) contexte.getString(R.string.enregistres_galerie, n) else contexte.getString(R.string.erreur_galerie)
            Toast.makeText(contexte, texte, Toast.LENGTH_LONG).show()
            if (n > 0) selection.quitter()
        }
    }
    val autorisation = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) enregistrer() else Toast.makeText(contexte, contexte.getString(R.string.erreur_galerie), Toast.LENGTH_LONG).show()
    }

    Row(
        modifier
            .widthIn(max = 640.dp)
            .fillMaxWidth()
            .padding(12.dp)
            .shadow(12.dp, RoundedCornerShape(22.dp))
            .clip(RoundedCornerShape(22.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(vertical = 6.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
    ) {
        val actif = choisis.isNotEmpty()
        Action(Icons.Filled.Download, stringResource(R.string.enregistrer_galerie), actif && !enregistrement, enregistrement) {
            if (Galerie.demandeAutorisation) autorisation.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE) else enregistrer()
        }
        Action(Icons.Filled.Share, stringResource(R.string.partager), actif) { partagerPlusieurs(contexte, choisis) }
        Action(Icons.AutoMirrored.Filled.DriveFileMove, stringResource(R.string.deplacer), actif && choisis.none { it.prive }) { deplacer = true }
        val tousPrives = actif && choisis.all { it.prive }
        Action(
            if (tousPrives) Icons.Filled.LockOpen else Icons.Filled.Lock,
            stringResource(if (tousPrives) R.string.retirer_prive else R.string.prive), actif,
        ) {
            choisis.filter { it.prive == tousPrives }.forEach { Bibliotheque.basculerPrive(it) }
            selection.quitter()
        }
        Action(Icons.Filled.Delete, stringResource(R.string.supprimer), actif, couleur = Elara.corail) { supprimer = true }
    }

    if (deplacer) {
        AlertDialog(
            onDismissRequest = { deplacer = false },
            title = { Text(stringResource(R.string.deplacer_vers)) },
            text = {
                Column {
                    TextButton(onClick = { choisis.forEach { Bibliotheque.deplacer(it, null) }; deplacer = false; selection.quitter() }) {
                        Text(stringResource(R.string.accueil_racine))
                    }
                    dossiers.forEach { d ->
                        TextButton(onClick = { choisis.forEach { Bibliotheque.deplacer(it, d.id) }; deplacer = false; selection.quitter() }) {
                            Text(d.nom)
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
            title = { Text(stringResource(R.string.supprimer_selection, choisis.size)) },
            confirmButton = {
                TextButton(onClick = { choisis.forEach { Bibliotheque.supprimer(it) }; supprimer = false; selection.quitter() }) {
                    Text(stringResource(R.string.supprimer), color = Elara.corail)
                }
            },
            dismissButton = { TextButton(onClick = { supprimer = false }) { Text(stringResource(R.string.annuler)) } },
        )
    }
}

@Composable
private fun Action(
    icone: ImageVector,
    titre: String,
    actif: Boolean,
    enCours: Boolean = false,
    couleur: Color = MaterialTheme.colorScheme.onSurface,
    action: () -> Unit,
) {
    Column(
        Modifier
            .clip(RoundedCornerShape(14.dp))
            .clickable(enabled = actif, onClick = action)
            .padding(horizontal = 8.dp, vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (enCours) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp, color = Elara.accent)
        else Icon(icone, null, tint = if (actif) couleur else couleur.copy(alpha = 0.35f))
        Spacer(Modifier.size(2.dp))
        Text(titre, fontSize = 11.sp, maxLines = 1, color = if (actif) couleur else couleur.copy(alpha = 0.35f))
    }
}

fun partagerPlusieurs(contexte: Context, medias: List<Media>) {
    if (medias.isEmpty()) return
    val uris = ArrayList<Uri>(medias.map { FileProvider.getUriForFile(contexte, contexte.packageName + ".fichiers", Bibliotheque.fichier(it)) })
    val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
        type = if (medias.all { it.type == TypeMedia.AUDIO }) "audio/*" else if (medias.all { it.type == TypeMedia.VIDEO }) "video/*" else "*/*"
        putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    MainActivity.actuelle?.garderOuvert = true
    contexte.startActivity(Intent.createChooser(intent, null))
}
