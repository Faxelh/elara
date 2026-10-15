package com.kounandi.elara.ui.reglages

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kounandi.elara.BuildConfig
import com.kounandi.elara.MainActivity
import com.kounandi.elara.R
import com.kounandi.elara.donnees.Reglages
import com.kounandi.elara.ui.commun.Elara

/** Nom sous l'icône pour cette version (fixé à la compilation, fichier NOM du dépôt GitHub). */
@Composable
fun nomIcone(): String = LocalContext.current.applicationInfo.loadLabel(LocalContext.current.packageManager).toString()

/** Nom affiché dans Elara : celui choisi par l'utilisateur, sinon celui de l'icône. */
@Composable
fun nomAffiche(): String = Reglages.nomApp.ifBlank { nomIcone() }

/** Fenêtre « Nom de l'application » (Réglages, et proposée après chaque mise à jour). */
@Composable
fun DialogueNomApp(titre: String, avecNouveautes: Boolean = false, fermer: () -> Unit) {
    val contexte = LocalContext.current
    val icone = nomIcone()
    var brouillon by remember { mutableStateOf(Reglages.nomApp.ifBlank { icone }) }
    AlertDialog(
        onDismissRequest = fermer,
        title = { Text(titre) },
        text = {
            Column(Modifier.heightIn(max = 520.dp).verticalScroll(rememberScrollState())) {
                if (avecNouveautes) {
                    val derniere = remember { Nouveautes.lire(contexte).firstOrNull() }
                    if (derniere != null) {
                        Text(stringResource(R.string.nouveautes) + " — " + derniere.titre, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold, color = Elara.accent)
                        Spacer(Modifier.height(6.dp))
                        ListeChangements(derniere)
                        Spacer(Modifier.height(14.dp))
                    }
                }
                OutlinedTextField(brouillon, { brouillon = it.take(30) }, singleLine = true, label = { Text(stringResource(R.string.nom_application)) })
                Spacer(Modifier.height(10.dp))
                Text(stringResource(R.string.nom_application_aide, icone), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                TextButton(onClick = {
                    MainActivity.actuelle?.garderOuvert = true
                    contexte.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/Faxelh/elara/edit/main/NOM")))
                }) { Text(stringResource(R.string.nom_icone_github), color = Elara.accent) }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val propre = brouillon.trim()
                Reglages.changerNomApp(if (propre == icone) "" else propre)
                fermer()
            }) { Text(stringResource(R.string.enregistrer), color = Elara.accent) }
        },
        dismissButton = { TextButton(onClick = fermer) { Text(stringResource(R.string.annuler)) } },
    )
}

/** Après une mise à jour : on propose de changer le nom de l'application. */
@Composable
fun ProposerNomApresMiseAJour() {
    var afficher by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        val vue = Reglages.texte("nomApp.versionVue")
        val actuelle = BuildConfig.VERSION_CODE.toString()
        if (vue == null) Reglages.ecrireTexte("nomApp.versionVue", actuelle)
        else if (vue != actuelle) afficher = true
    }
    if (afficher) {
        DialogueNomApp(stringResource(R.string.maj_installee), avecNouveautes = true) {
            Reglages.ecrireTexte("nomApp.versionVue", BuildConfig.VERSION_CODE.toString())
            afficher = false
        }
    }
}
