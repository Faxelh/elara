package com.kounandi.elara.ui.commun

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import com.kounandi.elara.donnees.Reglages
import com.kounandi.elara.donnees.Theme

object Elara {
    val accent = Color(0xFF735CF5)
    val violet = Color(0xFF8F66FA)
    val bleu = Color(0xFF388CFA)
    val vert = Color(0xFF33B373)
    val corail = Color(0xFFF56B61)
    val degrade = Brush.linearGradient(listOf(violet, bleu))
}

@Composable
fun ElaraTheme(contenu: @Composable () -> Unit) {
    val sombre = when (Reglages.theme) {
        Theme.SYSTEME -> isSystemInDarkTheme()
        Theme.CLAIR -> false
        Theme.SOMBRE -> true
    }
    val couleurs = if (sombre) {
        darkColorScheme(
            primary = Elara.accent,
            secondary = Elara.bleu,
            background = Color.Black,
            surface = Color(0xFF111114),
            surfaceVariant = Color(0xFF1C1C21),
            surfaceContainer = Color(0xFF16161A),
            onPrimary = Color.White,
        )
    } else {
        lightColorScheme(
            primary = Elara.accent,
            secondary = Elara.bleu,
            background = Color(0xFFF6F5FB),
            surface = Color.White,
            surfaceVariant = Color(0xFFECEAF5),
            onPrimary = Color.White,
        )
    }
    MaterialTheme(colorScheme = couleurs, content = contenu)
}
