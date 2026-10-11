package com.kounandi.elara.ui.reglages

import android.widget.Toast
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.kounandi.elara.R
import com.kounandi.elara.donnees.MiseAJour
import com.kounandi.elara.donnees.Reglages
import com.kounandi.elara.donnees.VersionDisponible
import com.kounandi.elara.ui.commun.Elara
import kotlinx.coroutines.launch

/** Au démarrage : cherche une nouvelle version (une fois par jour) et la propose. */
@Composable
fun VerificationMiseAJour() {
    var proposee by remember { mutableStateOf<VersionDisponible?>(null) }
    LaunchedEffect(Unit) {
        val v = MiseAJour.verifier()
        if (v != null && Reglages.texte("maj.ignoree") != v.numero.toString()) proposee = v
    }
    proposee?.let { v ->
        DialogueMiseAJour(v) { ignorer ->
            if (ignorer) Reglages.ecrireTexte("maj.ignoree", v.numero.toString())
            proposee = null
        }
    }
}

@Composable
fun DialogueMiseAJour(version: VersionDisponible, fermer: (ignorer: Boolean) -> Unit) {
    val contexte = LocalContext.current
    val scope = rememberCoroutineScope()
    AlertDialog(
        onDismissRequest = { if (!MiseAJour.telechargement) fermer(false) },
        title = { Text(stringResource(R.string.maj_disponible)) },
        text = {
            Column {
                Text(stringResource(R.string.maj_texte, version.version, com.kounandi.elara.BuildConfig.VERSION_NAME))
                if (version.notes.isNotBlank()) {
                    Spacer(Modifier.height(8.dp))
                    Text(version.notes.take(400))
                }
                if (MiseAJour.telechargement) {
                    Spacer(Modifier.height(12.dp))
                    LinearProgressIndicator(progress = { MiseAJour.progression }, modifier = Modifier.fillMaxWidth(), color = Elara.accent)
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = !MiseAJour.telechargement,
                onClick = {
                    scope.launch {
                        val ok = MiseAJour.installer(contexte, version)
                        if (ok) fermer(false)
                        else if (MiseAJour.derniereErreur != null) {
                            Toast.makeText(contexte, contexte.getString(R.string.maj_erreur), Toast.LENGTH_LONG).show()
                        } else {
                            Toast.makeText(contexte, contexte.getString(R.string.maj_autoriser), Toast.LENGTH_LONG).show()
                        }
                    }
                },
            ) { Text(stringResource(R.string.mettre_a_jour), color = Elara.accent) }
        },
        dismissButton = {
            TextButton(enabled = !MiseAJour.telechargement, onClick = { fermer(true) }) { Text(stringResource(R.string.plus_tard)) }
        },
    )
}
