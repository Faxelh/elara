package com.kounandi.elara.ui.reglages

import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.BrightnessMedium
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PictureInPictureAlt
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.SystemUpdate
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import androidx.core.os.LocaleListCompat
import com.kounandi.elara.BuildConfig
import com.kounandi.elara.MainActivity
import com.kounandi.elara.R
import com.kounandi.elara.donnees.Coffre
import com.kounandi.elara.donnees.MethodeVerrou
import com.kounandi.elara.donnees.ModeLectureAuto
import com.kounandi.elara.donnees.Reglages
import com.kounandi.elara.donnees.Theme
import com.kounandi.elara.ui.commun.Elara
import com.kounandi.elara.ui.prive.ChangerVerrouDialogue
import com.kounandi.elara.ui.prive.biometrieDisponible
import kotlinx.coroutines.launch

private data class Choix<T>(val valeur: T, val libelle: String)

@Composable
fun ReglagesEcran(marges: PaddingValues, activite: MainActivity) {
    var dialogue by remember { mutableStateOf<String?>(null) }
    var changerVerrou by remember { mutableStateOf(false) }
    var versionTrouvee by remember { mutableStateOf<com.kounandi.elara.donnees.VersionDisponible?>(null) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val contexte = androidx.compose.ui.platform.LocalContext.current

    val langues = listOf(
        Choix("", stringResource(R.string.langue_systeme)),
        Choix("fr", "Français"),
        Choix("en", "English"),
        Choix("ru", "Русский"),
        Choix("es", "Español"),
    )
    val langueActuelle = AppCompatDelegate.getApplicationLocales().toLanguageTags().substringBefore('-').substringBefore(',')
    val themes = listOf(
        Choix(Theme.SYSTEME, stringResource(R.string.theme_systeme)),
        Choix(Theme.CLAIR, stringResource(R.string.theme_clair)),
        Choix(Theme.SOMBRE, stringResource(R.string.theme_sombre)),
    )
    val modes = listOf(
        Choix(ModeLectureAuto.ARRETER, stringResource(R.string.auto_arreter)),
        Choix(ModeLectureAuto.ENCHAINER, stringResource(R.string.auto_enchainer)),
        Choix(ModeLectureAuto.REPETER_UN, stringResource(R.string.auto_repeter)),
        Choix(ModeLectureAuto.BOUCLE, stringResource(R.string.auto_boucle)),
    )

    LazyColumn(contentPadding = PaddingValues(top = marges.calculateTopPadding() + 12.dp, bottom = marges.calculateBottomPadding() + 24.dp)) {
        item {
            Text(
                stringResource(R.string.onglet_reglages), fontSize = 34.sp, fontWeight = FontWeight.Black,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
            )
        }
        item {
            Section(stringResource(R.string.section_general)) {
                Ligne(Icons.Filled.Language, Elara.bleu, stringResource(R.string.langue),
                    langues.firstOrNull { it.valeur == langueActuelle }?.libelle ?: langues[0].libelle) { dialogue = "langue" }
                Separateur()
                Ligne(Icons.Filled.DarkMode, Elara.violet, stringResource(R.string.theme),
                    themes.first { it.valeur == Reglages.theme }.libelle) { dialogue = "theme" }
            }
        }
        item {
            Section(stringResource(R.string.section_lecture)) {
                Interrupteur(Icons.Filled.History, Elara.vert, stringResource(R.string.reprendre_lecture), Reglages.reprendreLecture) {
                    Reglages.changerReprendre(it)
                }
                Separateur()
                Ligne(Icons.Filled.Repeat, Elara.accent, stringResource(R.string.lecture_auto),
                    modes.first { it.valeur == Reglages.modeLectureAuto }.libelle) { dialogue = "auto" }
                Separateur()
                Interrupteur(Icons.Filled.PictureInPictureAlt, Elara.bleu, stringResource(R.string.image_dans_image), Reglages.imageDansImage) {
                    Reglages.changerImageDansImage(it)
                }
            }
        }
        item {
            Section(stringResource(R.string.section_gestes)) {
                Interrupteur(Icons.Filled.BrightnessMedium, Color(0xFFFFB300), stringResource(R.string.geste_luminosite), Reglages.gesteLuminosite) {
                    Reglages.changerGesteLuminosite(it)
                }
                Separateur()
                Interrupteur(Icons.AutoMirrored.Filled.VolumeUp, Elara.corail, stringResource(R.string.geste_volume), Reglages.gesteVolume) {
                    Reglages.changerGesteVolume(it)
                }
            }
        }
        item {
            Section(stringResource(R.string.prive)) {
                Ligne(
                    Icons.Filled.Lock, Elara.corail, stringResource(R.string.verrou),
                    when {
                        !Coffre.estConfigure -> stringResource(R.string.verrou_aucun)
                        Coffre.methode == MethodeVerrou.CODE -> stringResource(R.string.methode_code)
                        else -> stringResource(R.string.methode_schema)
                    },
                ) { changerVerrou = true }
                if (biometrieDisponible(activite)) {
                    Separateur()
                    Interrupteur(Icons.Filled.Fingerprint, Elara.accent, stringResource(R.string.empreinte_visage), Reglages.biometrie) {
                        Reglages.changerBiometrie(it)
                    }
                }
            }
        }
        item {
            Section(stringResource(R.string.a_propos)) {
                Ligne(Icons.Filled.Info, Color.Gray, "Elara", BuildConfig.VERSION_NAME, fleche = false) {}
                Separateur()
                Ligne(Icons.Filled.Person, Elara.accent, stringResource(R.string.auteur), "Faxel Kwadio", fleche = false) {}
                Separateur()
                Ligne(
                    Icons.Filled.SystemUpdate, Elara.vert, stringResource(R.string.rechercher_maj),
                    if (com.kounandi.elara.donnees.MiseAJour.recherche) "…" else "",
                ) {
                    scope.launch {
                        val v = com.kounandi.elara.donnees.MiseAJour.verifier(forcer = true)
                        if (v != null) versionTrouvee = v
                        else android.widget.Toast.makeText(
                            contexte,
                            if (com.kounandi.elara.donnees.MiseAJour.derniereErreur != null) contexte.getString(R.string.maj_erreur)
                            else contexte.getString(R.string.maj_a_jour),
                            android.widget.Toast.LENGTH_LONG,
                        ).show()
                    }
                }
            }
        }
    }

    when (dialogue) {
        "langue" -> Selection(stringResource(R.string.langue), langues, langueActuelle, { dialogue = null }) { tag ->
            AppCompatDelegate.setApplicationLocales(
                if (tag.isEmpty()) LocaleListCompat.getEmptyLocaleList() else LocaleListCompat.forLanguageTags(tag),
            )
        }
        "theme" -> Selection(stringResource(R.string.theme), themes, Reglages.theme, { dialogue = null }) { Reglages.changerTheme(it) }
        "auto" -> Selection(stringResource(R.string.lecture_auto), modes, Reglages.modeLectureAuto, { dialogue = null }) {
            Reglages.changerLectureAuto(it)
        }
    }
    if (changerVerrou) ChangerVerrouDialogue(activite) { changerVerrou = false }
    versionTrouvee?.let { v -> DialogueMiseAJour(v) { versionTrouvee = null } }
}

@Composable
private fun Section(titre: String, contenu: @Composable () -> Unit) {
    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        Text(
            titre.uppercase(), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 6.dp, bottom = 6.dp),
        )
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(18.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant),
        ) { contenu() }
    }
}

@Composable
private fun Pictogramme(icone: ImageVector, couleur: Color) {
    Box(
        Modifier.size(32.dp).clip(RoundedCornerShape(9.dp)).background(couleur),
        contentAlignment = Alignment.Center,
    ) { Icon(icone, null, tint = Color.White, modifier = Modifier.size(19.dp)) }
}

@Composable
private fun Ligne(icone: ImageVector, couleur: Color, titre: String, valeur: String, fleche: Boolean = true, action: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = action).padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Pictogramme(icone, couleur)
        Spacer(Modifier.width(14.dp))
        Text(titre, modifier = Modifier.weight(1f), fontSize = 16.sp)
        Text(valeur, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 15.sp)
        if (fleche) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun Interrupteur(icone: ImageVector, couleur: Color, titre: String, valeur: Boolean, changer: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable { changer(!valeur) }.padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Pictogramme(icone, couleur)
        Spacer(Modifier.width(14.dp))
        Text(titre, modifier = Modifier.weight(1f), fontSize = 16.sp)
        Switch(checked = valeur, onCheckedChange = changer, colors = SwitchDefaults.colors(checkedTrackColor = Elara.accent))
    }
}

@Composable
private fun Separateur() {
    HorizontalDivider(Modifier.padding(start = 60.dp), color = MaterialTheme.colorScheme.background.copy(alpha = 0.6f))
}

@Composable
private fun <T> Selection(titre: String, choix: List<Choix<T>>, actuel: T, fermer: () -> Unit, choisir: (T) -> Unit) {
    AlertDialog(
        onDismissRequest = fermer,
        title = { Text(titre) },
        text = {
            Column {
                choix.forEach { c ->
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp))
                            .clickable { choisir(c.valeur); fermer() }.padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(
                            selected = c.valeur == actuel, onClick = { choisir(c.valeur); fermer() },
                            colors = RadioButtonDefaults.colors(selectedColor = Elara.accent),
                        )
                        Text(c.libelle, fontSize = 16.sp)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = fermer) { Text(stringResource(R.string.annuler)) } },
    )
}
