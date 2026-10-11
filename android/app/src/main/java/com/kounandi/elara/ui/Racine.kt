package com.kounandi.elara.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.OndemandVideo
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SmartDisplay
import androidx.compose.material.icons.filled.MusicVideo
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.res.stringResource
import com.kounandi.elara.MainActivity
import com.kounandi.elara.R
import com.kounandi.elara.donnees.Reglages
import com.kounandi.elara.ui.accueil.AccueilEcran
import com.kounandi.elara.ui.accueil.TelechargerFeuille
import com.kounandi.elara.ui.commun.Elara
import com.kounandi.elara.ui.facebook.FacebookEcran
import com.kounandi.elara.ui.lecteur.Lecteur
import com.kounandi.elara.ui.lecteur.LecteurEcran
import com.kounandi.elara.ui.lecteur.VideoPip
import com.kounandi.elara.ui.reglages.ReglagesEcran

@Composable
fun Racine(activite: MainActivity) {
    if (Lecteur.enPip) {
        VideoPip()
        return
    }
    var pleinEcranFacebook by remember { mutableStateOf(false) }
    val onglet = Reglages.ongletActuel.coerceIn(0, 4)

    Box(Modifier.fillMaxSize()) {
        Scaffold(
            bottomBar = {
                if (!(onglet == 1 && pleinEcranFacebook) && !(onglet == 3 && com.kounandi.elara.ui.youtube.NavigateurYouTube.vuePleinEcran != null)) {
                    NavigationBar {
                        val couleurs = NavigationBarItemDefaults.colors(
                            selectedIconColor = Elara.accent,
                            selectedTextColor = Elara.accent,
                            indicatorColor = Elara.accent.copy(alpha = 0.16f),
                        )
                        NavigationBarItem(
                            selected = onglet == 0, onClick = { Reglages.changerOnglet(0) },
                            icon = { Icon(Icons.Filled.Home, null) },
                            label = { Text(stringResource(R.string.onglet_accueil)) }, colors = couleurs,
                        )
                        NavigationBarItem(
                            selected = onglet == 1, onClick = { Reglages.changerOnglet(1) },
                            icon = { Icon(Icons.Filled.OndemandVideo, null) },
                            label = { Text("Facebook") }, colors = couleurs,
                        )
                        NavigationBarItem(
                            selected = onglet == 4, onClick = { Reglages.changerOnglet(4) },
                            icon = { Icon(Icons.Filled.MusicVideo, null) },
                            label = { Text("TikTok") }, colors = couleurs,
                        )
                        NavigationBarItem(
                            selected = onglet == 3, onClick = { Reglages.changerOnglet(3) },
                            icon = { Icon(Icons.Filled.SmartDisplay, null) },
                            label = { Text("YouTube") }, colors = couleurs,
                        )
                        NavigationBarItem(
                            selected = onglet == 2, onClick = { Reglages.changerOnglet(2) },
                            icon = { Icon(Icons.Filled.Settings, null) },
                            label = { Text(stringResource(R.string.onglet_reglages)) }, colors = couleurs,
                        )
                    }
                }
            },
        ) { marges ->
            when (onglet) {
                0 -> AccueilEcran(marges, activite)
                1 -> FacebookEcran(marges, pleinEcranFacebook) { pleinEcranFacebook = it }
                3 -> com.kounandi.elara.ui.youtube.YouTubeEcran(marges)
                4 -> com.kounandi.elara.ui.tiktok.TikTokEcran(marges)
                else -> ReglagesEcran(marges, activite)
            }
        }

        com.kounandi.elara.ui.reglages.VerificationMiseAJour()

        if (Lecteur.ouvert) LecteurEcran(activite)

        // « Déjà dans Elara » : le fichier importé ou téléchargé existait déjà.
        val doublon by com.kounandi.elara.donnees.Bibliotheque.doublon.collectAsState()
        androidx.compose.animation.AnimatedVisibility(
            visible = doublon != null,
            modifier = Modifier.align(androidx.compose.ui.Alignment.TopCenter).statusBarsPadding().padding(12.dp),
            enter = androidx.compose.animation.slideInVertically { -it },
            exit = androidx.compose.animation.slideOutVertically { -it },
        ) {
            androidx.compose.foundation.layout.Row(
                Modifier
                    .clip(androidx.compose.foundation.shape.RoundedCornerShape(16.dp))
                    .background(androidx.compose.material3.MaterialTheme.colorScheme.surfaceVariant)
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
            ) {
                Icon(androidx.compose.material.icons.Icons.Filled.ContentCopy, null, tint = Elara.accent)
                androidx.compose.foundation.layout.Spacer(Modifier.width(10.dp))
                androidx.compose.foundation.layout.Column {
                    Text(stringResource(R.string.deja_dans_elara), fontWeight = androidx.compose.ui.text.font.FontWeight.Bold)
                    Text(doublon?.nom ?: "", maxLines = 1, fontSize = 13.sp)
                }
            }
        }

        activite.lienPartage?.let { lien ->
            TelechargerFeuille(lienInitial = lien, demarrerSeul = true) { activite.lienPartage = null }
        }
    }
}
