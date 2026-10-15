package com.kounandi.elara.ui.accueil

import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.CreateNewFolder
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kounandi.elara.MainActivity
import com.kounandi.elara.R
import com.kounandi.elara.donnees.Bibliotheque
import com.kounandi.elara.donnees.Dossier
import com.kounandi.elara.donnees.Media
import com.kounandi.elara.donnees.Reglages
import com.kounandi.elara.donnees.TypeMedia
import com.kounandi.elara.ui.commun.DialogueNom
import com.kounandi.elara.ui.commun.Elara
import com.kounandi.elara.ui.commun.BarreSelection
import com.kounandi.elara.ui.commun.EnteteSelection
import com.kounandi.elara.ui.commun.LigneMedia
import com.kounandi.elara.ui.commun.rememberSelection
import com.kounandi.elara.ui.lecteur.Lecteur
import com.kounandi.elara.ui.prive.PriveEcran
import kotlinx.coroutines.launch

enum class Tri { DATE, NOM, TAILLE, DUREE }

fun trier(liste: List<Media>, tri: Tri): List<Media> = when (tri) {
    Tri.DATE -> liste.sortedByDescending { it.date }
    Tri.NOM -> liste.sortedBy { it.nom.lowercase() }
    Tri.TAILLE -> liste.sortedByDescending { it.taille }
    Tri.DUREE -> liste.sortedByDescending { it.duree }
}

@Composable
fun AccueilEcran(marges: PaddingValues, activite: MainActivity) {
    // Navigation interne de l'onglet (gardée en mémoire quand on change d'onglet ou de langue).
    var dossierOuvert by rememberSaveable { mutableStateOf(Reglages.texte("accueil.dossier")) }
    var priveOuvert by rememberSaveable { mutableStateOf(false) }

    fun ouvrirDossier(id: String?) {
        dossierOuvert = id
        Reglages.ecrireTexte("accueil.dossier", id)
    }

    when {
        priveOuvert -> PriveEcran(marges, activite) { priveOuvert = false }
        dossierOuvert != null -> {
            val dossiers by Bibliotheque.dossiers.collectAsState()
            val dossier = dossiers.firstOrNull { it.id == dossierOuvert }
            if (dossier == null) {
                androidx.compose.runtime.LaunchedEffect(Unit) { ouvrirDossier(null) }
            } else {
                DossierEcran(marges, dossier) { ouvrirDossier(null) }
            }
        }
        else -> EcranBibliotheque(marges, ouvrirDossier = { ouvrirDossier(it) }, ouvrirPrive = { priveOuvert = true })
    }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun EcranBibliotheque(marges: PaddingValues, ouvrirDossier: (String) -> Unit, ouvrirPrive: () -> Unit) {
    val medias by Bibliotheque.medias.collectAsState()
    val dossiers by Bibliotheque.dossiers.collectAsState()
    var filtre by remember { mutableIntStateOf(Reglages.texte("accueil.filtre")?.toIntOrNull() ?: 0) }
    var tri by remember { mutableStateOf(runCatching { Tri.valueOf(Reglages.texte("accueil.tri") ?: "DATE") }.getOrDefault(Tri.DATE)) }
    var menuAjout by remember { mutableStateOf(false) }
    var menuTri by remember { mutableStateOf(false) }
    var nouveauDossier by remember { mutableStateOf(false) }
    var telecharger by remember { mutableStateOf(false) }
    var importEnCours by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()

    fun importer(uris: List<Uri>) {
        if (uris.isEmpty()) return
        importEnCours += uris.size
        scope.launch {
            uris.forEach { Bibliotheque.importer(it); importEnCours-- }
        }
    }
    val photos = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia()) { importer(it) }
    val fichiers = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { importer(it) }

    val selection = rememberSelection()
    var confirmerDoublons by remember { mutableStateOf(false) }
    val contexte = androidx.compose.ui.platform.LocalContext.current
    val visibles = trier(
        medias.filter { !it.prive && it.dossier == null }.filter {
            when (filtre) {
                1 -> it.type == TypeMedia.VIDEO
                2 -> it.type == TypeMedia.AUDIO
                else -> true
            }
        },
        tri,
    )

    androidx.compose.runtime.LaunchedEffect(visibles) { selection.garderSeulement(visibles) }
    Box(Modifier.fillMaxSize()) {
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = marges.calculateTopPadding() + 8.dp, bottom = marges.calculateBottomPadding() + if (selection.actif) 110.dp else 16.dp)) {
        item {
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Box {
                    IconButton(onClick = { menuAjout = true }) {
                        Icon(Icons.Filled.Add, stringResource(R.string.ajouter), tint = Elara.accent, modifier = Modifier.size(30.dp))
                    }
                    DropdownMenu(expanded = menuAjout, onDismissRequest = { menuAjout = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.nouveau_dossier)) },
                            leadingIcon = { Icon(Icons.Filled.CreateNewFolder, null) },
                            onClick = { menuAjout = false; nouveauDossier = true },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.telecharger_lien)) },
                            leadingIcon = { Icon(Icons.Filled.Download, null) },
                            onClick = { menuAjout = false; telecharger = true },
                        )
                    }
                }
                Spacer(Modifier.weight(1f))
                Box {
                    IconButton(onClick = { menuTri = true }) {
                        Icon(Icons.AutoMirrored.Filled.Sort, stringResource(R.string.trier), tint = Elara.accent)
                    }
                    DropdownMenu(expanded = menuTri, onDismissRequest = { menuTri = false }) {
                        listOf(
                            Tri.DATE to R.string.tri_date, Tri.NOM to R.string.tri_nom,
                            Tri.TAILLE to R.string.tri_taille, Tri.DUREE to R.string.tri_duree,
                        ).forEach { (t, libelle) ->
                            DropdownMenuItem(
                                text = { Text(stringResource(libelle)) },
                                trailingIcon = { if (tri == t) Icon(Icons.Filled.Check, null, tint = Elara.accent) },
                                onClick = { tri = t; Reglages.ecrireTexte("accueil.tri", t.name); menuTri = false },
                            )
                        }
                        HorizontalDivider()
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.supprimer_doublons)) },
                            leadingIcon = { Icon(Icons.Filled.ContentCopy, null) },
                            onClick = { menuTri = false; confirmerDoublons = true },
                        )
                    }
                }
            }
            Text(
                com.kounandi.elara.ui.reglages.nomAffiche(), fontSize = 40.sp, fontWeight = FontWeight.Black,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp),
            )
        }

        item {
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Tuile(stringResource(R.string.photos), Icons.Filled.PhotoLibrary, Color(0xFF0A1220), Elara.bleu, Modifier.weight(1f)) {
                    photos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.VideoOnly))
                }
                Tuile(stringResource(R.string.fichiers), Icons.Filled.VideoLibrary, Color(0xFF0B1A12), Elara.vert, Modifier.weight(1f)) {
                    fichiers.launch(arrayOf("video/*", "audio/*"))
                }
                Tuile(stringResource(R.string.prive), Icons.Filled.Lock, Color(0xFF1E0F0E), Elara.corail, Modifier.weight(1f)) {
                    ouvrirPrive()
                }
            }
        }

        if (importEnCours > 0) {
            item {
                Row(Modifier.padding(horizontal = 20.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = Elara.accent)
                    Spacer(Modifier.width(10.dp))
                    Text(stringResource(R.string.importation, importEnCours), fontSize = 14.sp)
                }
            }
        }

        items(dossiers, key = { "d" + it.id }) { d ->
            val nombre = medias.count { it.dossier == d.id && !it.prive }
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 5.dp)
                    .clip(RoundedCornerShape(18.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant)
                    .clickable { ouvrirDossier(d.id) }
                    .padding(14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier.size(52.dp).clip(RoundedCornerShape(14.dp)).background(Elara.bleu.copy(alpha = 0.18f)),
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.Filled.Folder, null, tint = Elara.bleu, modifier = Modifier.size(30.dp)) }
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(d.nom, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                    Text(
                        androidx.compose.ui.res.pluralStringResource(R.plurals.elements, nombre, nombre),
                        color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp,
                    )
                }
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }

        // La barre « Tout / Vidéos / Audio » reste collée en haut pendant le défilement.
        stickyHeader {
            SingleChoiceSegmentedButtonRow(
                Modifier
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.background)
                    .padding(horizontal = 20.dp, vertical = 12.dp),
            ) {
                listOf(R.string.tout, R.string.videos, R.string.audio).forEachIndexed { i, libelle ->
                    SegmentedButton(
                        selected = filtre == i,
                        onClick = { filtre = i; Reglages.ecrireTexte("accueil.filtre", i.toString()) },
                        shape = SegmentedButtonDefaults.itemShape(i, 3),
                        colors = SegmentedButtonDefaults.colors(activeContainerColor = Elara.accent.copy(alpha = 0.22f)),
                        icon = {},
                    ) { Text(stringResource(libelle)) }
                }
            }
        }

        if (visibles.isNotEmpty()) {
            item { EnteteSelection(selection, visibles) }
        }
        if (visibles.isEmpty()) {
            item {
                Text(
                    stringResource(R.string.vide_accueil),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 28.dp, vertical = 30.dp),
                )
            }
        }
        items(visibles, key = { it.id }) { m ->
            LigneMedia(m, dossiers, selection) { Lecteur.lire(m, visibles) }
            HorizontalDivider(Modifier.padding(start = 138.dp), color = MaterialTheme.colorScheme.surfaceVariant)
        }
    }
    BarreSelection(
        selection, visibles, dossiers,
        Modifier.align(Alignment.BottomCenter).padding(bottom = marges.calculateBottomPadding()),
    )
    }

    if (confirmerDoublons) {
        AlertDialog(
            onDismissRequest = { confirmerDoublons = false },
            title = { Text(stringResource(R.string.supprimer_doublons)) },
            text = { Text(stringResource(R.string.supprimer_doublons_texte)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmerDoublons = false
                    scope.launch {
                        val n = Bibliotheque.supprimerDoublons()
                        android.widget.Toast.makeText(
                            contexte,
                            if (n == 0) contexte.getString(R.string.aucun_doublon) else contexte.getString(R.string.doublons_supprimes, n),
                            android.widget.Toast.LENGTH_LONG,
                        ).show()
                    }
                }) { Text(stringResource(R.string.supprimer), color = Elara.corail) }
            },
            dismissButton = { TextButton(onClick = { confirmerDoublons = false }) { Text(stringResource(R.string.annuler)) } },
        )
    }

    if (nouveauDossier) {
        DialogueNom(
            titre = stringResource(R.string.nouveau_dossier),
            initial = "",
            longueurMax = Dossier.LONGUEUR_MAX,
            surValider = { Bibliotheque.creerDossier(it) },
            surFermer = { nouveauDossier = false },
        )
    }
    if (telecharger) {
        TelechargerFeuille(lienInitial = null, demarrerSeul = false) { telecharger = false }
    }
}

@Composable
private fun Tuile(titre: String, icone: ImageVector, fond: Color, couleur: Color, modifier: Modifier, action: () -> Unit) {
    Column(
        modifier
            .height(118.dp)
            .clip(RoundedCornerShape(24.dp))
            .background(fond)
            .clickable(onClick = action)
            .padding(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(icone, null, tint = couleur, modifier = Modifier.size(40.dp))
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(titre, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, maxLines = 1)
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Color.White, modifier = Modifier.size(18.dp))
        }
    }
}

@Composable
private fun DossierEcran(marges: PaddingValues, dossier: Dossier, retour: () -> Unit) {
    BackHandler(onBack = retour)
    val medias by Bibliotheque.medias.collectAsState()
    val dossiers by Bibliotheque.dossiers.collectAsState()
    var menu by remember { mutableStateOf(false) }
    var renommer by remember { mutableStateOf(false) }
    var supprimer by remember { mutableStateOf(false) }
    val contenu = trier(medias.filter { it.dossier == dossier.id && !it.prive }, Tri.DATE)
    val selection = rememberSelection()
    androidx.compose.runtime.LaunchedEffect(contenu) { selection.garderSeulement(contenu) }

    Box(Modifier.fillMaxSize()) {
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = marges.calculateTopPadding() + 8.dp, bottom = marges.calculateBottomPadding() + if (selection.actif) 110.dp else 16.dp)) {
        item {
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = retour) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.retour), tint = Elara.accent)
                }
                Text(dossier.nom, fontSize = 26.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                Box {
                    IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, stringResource(R.string.actions)) }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.renommer)) },
                            leadingIcon = { Icon(Icons.Filled.Edit, null) },
                            onClick = { menu = false; renommer = true },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.supprimer_dossier), color = Elara.corail) },
                            leadingIcon = { Icon(Icons.Filled.Delete, null, tint = Elara.corail) },
                            onClick = { menu = false; supprimer = true },
                        )
                    }
                }
            }
        }
        if (contenu.isEmpty()) {
            item {
                Text(
                    stringResource(R.string.vide_dossier),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 28.dp, vertical = 30.dp),
                )
            }
        }
        if (contenu.isNotEmpty()) {
            item { EnteteSelection(selection, contenu) }
        }
        items(contenu, key = { it.id }) { m ->
            LigneMedia(m, dossiers, selection) { Lecteur.lire(m, contenu) }
        }
    }
    BarreSelection(
        selection, contenu, dossiers,
        Modifier.align(Alignment.BottomCenter).padding(bottom = marges.calculateBottomPadding()),
    )
    }

    if (renommer) {
        DialogueNom(
            titre = stringResource(R.string.renommer),
            initial = dossier.nom,
            longueurMax = Dossier.LONGUEUR_MAX,
            surValider = { Bibliotheque.renommerDossier(dossier, it) },
            surFermer = { renommer = false },
        )
    }
    if (supprimer) {
        AlertDialog(
            onDismissRequest = { supprimer = false },
            title = { Text(stringResource(R.string.supprimer_dossier)) },
            text = { Text(stringResource(R.string.supprimer_dossier_texte)) },
            confirmButton = {
                TextButton(onClick = { supprimer = false; Bibliotheque.supprimerDossier(dossier); retour() }) {
                    Text(stringResource(R.string.supprimer), color = Elara.corail)
                }
            },
            dismissButton = { TextButton(onClick = { supprimer = false }) { Text(stringResource(R.string.annuler)) } },
        )
    }
}
