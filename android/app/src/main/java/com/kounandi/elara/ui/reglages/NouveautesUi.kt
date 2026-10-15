package com.kounandi.elara.ui.reglages

import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kounandi.elara.R
import com.kounandi.elara.ui.commun.Elara

/** Une mise à jour : sa date et la liste de ses changements. */
data class SectionNouveautes(val titre: String, val lignes: List<String>)

/** Historique des nouveautés (fichier assets/nouveautes.txt : « # titre » puis « - changement »). */
object Nouveautes {
    fun lire(ctx: Context): List<SectionNouveautes> = runCatching {
        val sections = mutableListOf<SectionNouveautes>()
        var titre: String? = null
        val lignes = mutableListOf<String>()
        ctx.assets.open("nouveautes.txt").bufferedReader().useLines { tout ->
            tout.forEach { brute ->
                val l = brute.trim()
                when {
                    l.startsWith("# ") -> {
                        titre?.let { sections += SectionNouveautes(it, lignes.toList()) }
                        titre = l.removePrefix("# ")
                        lignes.clear()
                    }
                    l.startsWith("- ") -> lignes += l.removePrefix("- ")
                }
            }
        }
        titre?.let { sections += SectionNouveautes(it, lignes.toList()) }
        sections
    }.getOrDefault(emptyList())
}

@Composable
fun ListeChangements(section: SectionNouveautes) {
    Column {
        section.lignes.forEach { ligne ->
            Row(Modifier.padding(vertical = 3.dp)) {
                Text("✓", color = Elara.accent, fontWeight = FontWeight.Bold)
                Spacer(Modifier.width(8.dp))
                Text(ligne, fontSize = 14.sp)
            }
        }
    }
}

/** Tout l'historique (Réglages › À propos › Nouveautés). */
@Composable
fun DialogueNouveautes(fermer: () -> Unit) {
    val contexte = LocalContext.current
    val sections = remember { Nouveautes.lire(contexte) }
    AlertDialog(
        onDismissRequest = fermer,
        title = { Text(stringResource(R.string.nouveautes)) },
        text = {
            Column(Modifier.heightIn(max = 480.dp).verticalScroll(rememberScrollState())) {
                sections.forEach { s ->
                    Text(s.titre, fontWeight = FontWeight.Bold, fontSize = 15.sp, color = Elara.accent)
                    Spacer(Modifier.height(4.dp))
                    ListeChangements(s)
                    Spacer(Modifier.height(14.dp))
                }
            }
        },
        confirmButton = { TextButton(onClick = fermer) { Text("OK", color = Elara.accent) } },
    )
}
