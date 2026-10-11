package com.kounandi.elara.ui.prive

import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.Dialpad
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kounandi.elara.MainActivity
import com.kounandi.elara.R
import com.kounandi.elara.donnees.Bibliotheque
import com.kounandi.elara.donnees.Coffre
import com.kounandi.elara.donnees.MethodeVerrou
import com.kounandi.elara.donnees.Reglages
import com.kounandi.elara.ui.accueil.Tri
import com.kounandi.elara.ui.accueil.trier
import com.kounandi.elara.ui.commun.Elara
import com.kounandi.elara.ui.commun.BarreSelection
import com.kounandi.elara.ui.commun.EnteteSelection
import com.kounandi.elara.ui.commun.LigneMedia
import com.kounandi.elara.ui.commun.rememberSelection
import com.kounandi.elara.ui.lecteur.Lecteur
import kotlinx.coroutines.launch

@Composable
fun PriveEcran(marges: PaddingValues, activite: MainActivity, retour: () -> Unit) {
    val fermer = {
        Coffre.verrouiller()
        retour()
    }
    BackHandler(onBack = fermer)
    DisposableEffect(Unit) {
        activite.protegerEcran(true)
        onDispose {
            activite.protegerEcran(false)
            // On quitte le dossier privé (autre onglet, retour…) : il se reverrouille.
            Coffre.verrouiller()
        }
    }

    Box(Modifier.fillMaxSize().padding(marges)) {
        when {
            !Coffre.estConfigure && !Coffre.deverrouille -> ConfigurationVerrou(activite, annuler = fermer) {}
            !Coffre.deverrouille -> Deverrouillage(activite, annuler = fermer) {}
            else -> ContenuPrive(fermer)
        }
    }
}

// MARK: - Contenu

@Composable
private fun ContenuPrive(fermer: () -> Unit) {
    val medias by Bibliotheque.medias.collectAsState()
    val dossiers by Bibliotheque.dossiers.collectAsState()
    val prives = trier(medias.filter { it.prive }, Tri.DATE)
    val scope = rememberCoroutineScope()
    val fichiers = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris: List<Uri> ->
        scope.launch { uris.forEach { Bibliotheque.importer(it, prive = true) } }
    }
    val choisir = {
        MainActivity.actuelle?.garderOuvert = true
        fichiers.launch(arrayOf("video/*", "audio/*"))
    }

    val selection = rememberSelection()
    LaunchedEffect(prives) { selection.garderSeulement(prives) }
    Box(Modifier.fillMaxSize()) {
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 8.dp, bottom = if (selection.actif) 110.dp else 8.dp)) {
        item {
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = fermer) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.retour), tint = Elara.accent)
                }
                Text(stringResource(R.string.prive), fontSize = 26.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                IconButton(onClick = choisir) {
                    Icon(Icons.Filled.Add, stringResource(R.string.ajouter), tint = Elara.accent)
                }
                IconButton(onClick = fermer) {
                    Icon(Icons.Filled.Lock, stringResource(R.string.verrouiller), tint = Elara.corail)
                }
            }
        }
        if (prives.isEmpty()) {
            item {
                Text(
                    stringResource(R.string.vide_prive),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 28.dp, vertical = 30.dp),
                )
            }
        }
        if (prives.isNotEmpty()) {
            item { EnteteSelection(selection, prives) }
        }
        items(prives, key = { it.id }) { m ->
            LigneMedia(m, dossiers, selection) { Lecteur.lire(m, prives) }
        }
    }
    BarreSelection(selection, prives, dossiers, Modifier.align(Alignment.BottomCenter))
    }
}

// MARK: - Déverrouillage

@Composable
internal fun Deverrouillage(activite: MainActivity, annuler: () -> Unit, surOuvert: () -> Unit) {
    var saisie by remember { mutableStateOf("") }
    var secousse by remember { mutableIntStateOf(0) }
    var erreur by remember { mutableStateOf(false) }
    val bioPossible = Reglages.biometrie && biometrieDisponible(activite)
    val titre = stringResource(R.string.ouvrir_prive)
    val sousTitre = stringResource(R.string.bio_sous_titre)
    val boutonCode = stringResource(
        if (Coffre.methode == MethodeVerrou.CODE) R.string.utiliser_code else R.string.utiliser_schema,
    )
    val lancerBio = {
        demanderBiometrie(activite, titre, sousTitre, boutonCode) {
            Coffre.ouvrirParBiometrie()
            surOuvert()
        }
    }
    LaunchedEffect(Unit) { if (bioPossible) lancerBio() }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp)) {
            IconButton(onClick = annuler) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.retour), tint = Elara.accent)
            }
        }
        Icon(Icons.Filled.Lock, null, tint = Elara.corail, modifier = Modifier.size(44.dp))
        Spacer(Modifier.height(12.dp))
        Text(stringResource(R.string.prive), fontSize = 24.sp, fontWeight = FontWeight.Bold)
        Text(
            stringResource(
                when {
                    erreur && Coffre.methode == MethodeVerrou.CODE -> R.string.code_faux
                    erreur -> R.string.schema_faux
                    Coffre.methode == MethodeVerrou.CODE -> R.string.saisir_code
                    else -> R.string.dessiner_schema
                },
            ),
            color = if (erreur) Elara.corail else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 6.dp, bottom = 28.dp),
        )

        if (Coffre.methode == MethodeVerrou.CODE) {
            ClavierCode(
                saisie = saisie,
                longueurPoints = Coffre.longueurCode,
                secousse = secousse,
                biometrie = if (bioPossible) lancerBio else null,
                surChiffre = { c ->
                    if (saisie.length < Coffre.longueurCode) saisie += c
                    if (saisie.length == Coffre.longueurCode) {
                        if (Coffre.verifier(saisie)) surOuvert() else {
                            erreur = true
                            secousse++
                            saisie = ""
                        }
                    }
                },
                surEffacer = { saisie = saisie.dropLast(1); erreur = false },
            )
        } else {
            GrilleSchema(secousse, erreur) { points ->
                if (Coffre.verifier(schemaEnTexte(points))) surOuvert() else {
                    erreur = true
                    secousse++
                }
            }
            if (bioPossible) {
                Spacer(Modifier.height(24.dp))
                IconButton(onClick = lancerBio, modifier = Modifier.size(64.dp)) {
                    Icon(Icons.Filled.Fingerprint, null, tint = Elara.accent, modifier = Modifier.size(44.dp))
                }
            }
        }
    }
}

// MARK: - Première configuration

@Composable
internal fun ConfigurationVerrou(activite: MainActivity, annuler: () -> Unit, surTermine: () -> Unit) {
    var methode by remember { mutableStateOf<MethodeVerrou?>(null) }
    var premier by remember { mutableStateOf<String?>(null) }
    var saisie by remember { mutableStateOf("") }
    var secousse by remember { mutableIntStateOf(0) }
    var message by remember { mutableStateOf<Int?>(null) }

    BackHandler(enabled = methode != null) { methode = null; premier = null; saisie = ""; message = null }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp)) {
            IconButton(onClick = { if (methode == null) annuler() else { methode = null; premier = null; saisie = "" } }) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.retour), tint = Elara.accent)
            }
        }
        Icon(Icons.Filled.Lock, null, tint = Elara.corail, modifier = Modifier.size(44.dp))
        Spacer(Modifier.height(12.dp))

        when (val m = methode) {
            null -> {
                Text(stringResource(R.string.proteger_prive), fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Text(
                    stringResource(R.string.proteger_prive_texte),
                    textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 32.dp, vertical = 10.dp),
                )
                Spacer(Modifier.height(16.dp))
                ChoixMethode(Icons.Filled.Dialpad, stringResource(R.string.methode_code), stringResource(R.string.methode_code_texte)) {
                    methode = MethodeVerrou.CODE
                }
                ChoixMethode(Icons.Filled.Apps, stringResource(R.string.methode_schema), stringResource(R.string.methode_schema_texte)) {
                    methode = MethodeVerrou.SCHEMA
                }
                if (biometrieDisponible(activite)) {
                    Row(Modifier.padding(24.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Fingerprint, null, tint = Elara.accent)
                        Text(
                            stringResource(R.string.bio_en_plus),
                            color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp,
                            modifier = Modifier.padding(start = 10.dp),
                        )
                    }
                }
            }
            MethodeVerrou.CODE -> {
                Text(
                    stringResource(if (premier == null) R.string.choisir_code else R.string.confirmer_code),
                    fontSize = 20.sp, fontWeight = FontWeight.Bold,
                )
                Text(
                    stringResource(message ?: R.string.code_longueur),
                    color = if (message != null) Elara.corail else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 6.dp, bottom = 24.dp),
                )
                val longueur = premier?.length ?: maxOf(4, saisie.length)
                ClavierCode(
                    saisie = saisie,
                    longueurPoints = longueur.coerceAtMost(8),
                    secousse = secousse,
                    biometrie = null,
                    surChiffre = { c ->
                        val p = premier
                        if (saisie.length < 8) saisie += c
                        if (p != null && saisie.length == p.length) {
                            if (saisie == p) { Coffre.definir(MethodeVerrou.CODE, saisie); surTermine() }
                            else { message = R.string.codes_differents; secousse++; saisie = ""; premier = null }
                        }
                    },
                    surEffacer = { saisie = saisie.dropLast(1) },
                )
                if (premier == null) {
                    TextButton(
                        enabled = saisie.length >= 4,
                        onClick = { premier = saisie; saisie = ""; message = null },
                    ) { Text(stringResource(R.string.continuer), fontSize = 17.sp) }
                }
            }
            MethodeVerrou.SCHEMA -> {
                Text(
                    stringResource(if (premier == null) R.string.dessiner_nouveau_schema else R.string.confirmer_schema),
                    fontSize = 20.sp, fontWeight = FontWeight.Bold,
                )
                Text(
                    stringResource(message ?: R.string.schema_minimum),
                    color = if (message != null) Elara.corail else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 6.dp, bottom = 24.dp),
                )
                GrilleSchema(secousse, message != null) { points ->
                    val texte = schemaEnTexte(points)
                    val p = premier
                    when {
                        points.size < 4 -> { message = R.string.schema_trop_court; secousse++ }
                        p == null -> { premier = texte; message = null }
                        p == texte -> { Coffre.definir(MethodeVerrou.SCHEMA, texte); surTermine() }
                        else -> { message = R.string.schemas_differents; secousse++; premier = null }
                    }
                }
            }
        }
    }
}

@Composable
private fun ChoixMethode(icone: ImageVector, titre: String, texte: String, action: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 6.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .clickable(onClick = action)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            Modifier.size(46.dp).clip(RoundedCornerShape(14.dp)).background(Elara.accent.copy(alpha = 0.18f)),
            contentAlignment = Alignment.Center,
        ) { Icon(icone, null, tint = Elara.accent) }
        Column {
            Text(titre, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            Text(texte, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp)
        }
    }
}

/** Réglages › Changer le verrou : on vérifie l'ancien code, puis on choisit le nouveau. */
@Composable
fun ChangerVerrouDialogue(activite: MainActivity, surFermer: () -> Unit) {
    var verifie by remember { mutableStateOf(!Coffre.estConfigure) }
    androidx.compose.ui.window.Dialog(
        onDismissRequest = surFermer,
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false),
    ) {
        androidx.compose.material3.Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            if (!verifie) {
                Deverrouillage(activite, annuler = surFermer) { verifie = true }
                LaunchedEffect(Coffre.deverrouille) { if (Coffre.deverrouille) verifie = true }
            } else {
                ConfigurationVerrou(activite, annuler = surFermer) { surFermer() }
            }
        }
    }
}
