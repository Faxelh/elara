package com.kounandi.elara.ui.accueil

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Download
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kounandi.elara.R
import com.kounandi.elara.donnees.Format
import com.kounandi.elara.donnees.Media
import com.kounandi.elara.donnees.Telechargeur
import com.kounandi.elara.ui.commun.Elara
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TelechargerFeuille(lienInitial: String?, demarrerSeul: Boolean, surFermer: () -> Unit) {
    val etat = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val contexte = LocalContext.current
    val presse = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    var lien by remember { mutableStateOf(lienInitial ?: "") }
    var prive by remember { mutableStateOf(false) }
    var erreur by remember { mutableStateOf<String?>(null) }
    var ajoute by remember { mutableStateOf<Media?>(null) }

    fun lancer() {
        erreur = null
        ajoute = null
        scope.launch {
            try {
                ajoute = Telechargeur.telecharger(contexte, lien, prive)
            } catch (e: Exception) {
                erreur = e.message ?: contexte.getString(R.string.erreur_inconnue)
            }
        }
    }
    LaunchedEffect(Unit) { if (demarrerSeul && lien.isNotBlank()) lancer() }

    ModalBottomSheet(onDismissRequest = surFermer, sheetState = etat) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 22.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(stringResource(R.string.telecharger), fontSize = 22.sp, fontWeight = FontWeight.Bold)
            OutlinedTextField(
                value = lien,
                onValueChange = { lien = it },
                label = { Text(stringResource(R.string.lien_fichier)) },
                modifier = Modifier.fillMaxWidth(),
                maxLines = 3,
            )
            OutlinedButton(onClick = { presse.getText()?.text?.let { lien = it.trim() } }) {
                Icon(Icons.Filled.ContentPaste, null)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.coller_lien))
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.ranger_prive), modifier = Modifier.weight(1f))
                Switch(
                    checked = prive, onCheckedChange = { prive = it },
                    colors = SwitchDefaults.colors(checkedTrackColor = Elara.accent),
                )
            }
            Text(
                stringResource(R.string.aide_telecharger),
                color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp,
            )

            if (Telechargeur.enCours) {
                Text(
                    if (Telechargeur.recherche) stringResource(R.string.recherche_video)
                    else stringResource(R.string.telechargement_en_cours, (Telechargeur.progression * 100).toInt(), Format.taille(Telechargeur.octets)),
                    fontWeight = FontWeight.SemiBold,
                )
                if (Telechargeur.recherche || Telechargeur.progression <= 0f) {
                    LinearProgressIndicator(Modifier.fillMaxWidth(), color = Elara.accent)
                } else {
                    LinearProgressIndicator(progress = { Telechargeur.progression }, modifier = Modifier.fillMaxWidth(), color = Elara.accent)
                }
                TextButton(onClick = { Telechargeur.annuler() }) {
                    Text(stringResource(R.string.annuler), color = Elara.corail)
                }
            } else {
                Button(
                    onClick = { lancer() },
                    enabled = lien.isNotBlank(),
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Elara.accent),
                ) {
                    Icon(Icons.Filled.Download, null)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.telecharger), fontSize = 17.sp)
                }
            }
            erreur?.let { Text(it, color = Elara.corail) }
            ajoute?.let { m ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.CheckCircle, null, tint = Elara.vert)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.ajoute_a_elara, m.nom), fontWeight = FontWeight.SemiBold)
                }
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}
