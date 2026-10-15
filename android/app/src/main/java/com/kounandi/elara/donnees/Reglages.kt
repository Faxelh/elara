package com.kounandi.elara.donnees

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

enum class ModeLectureAuto { ARRETER, ENCHAINER, REPETER_UN, BOUCLE }
enum class Theme { SYSTEME, CLAIR, SOMBRE }

/** Réglages de l'app, enregistrés et observables par l'interface. */
object Reglages {
    private lateinit var prefs: SharedPreferences

    var theme by mutableStateOf(Theme.SOMBRE); private set
    var reprendreLecture by mutableStateOf(true); private set
    var modeLectureAuto by mutableStateOf(ModeLectureAuto.ARRETER); private set
    var gesteLuminosite by mutableStateOf(true); private set
    var gesteVolume by mutableStateOf(true); private set
    var imageDansImage by mutableStateOf(true); private set
    var biometrie by mutableStateOf(true); private set
    var ongletActuel by mutableStateOf(0); private set
    /** Nom de l'application choisi par l'utilisateur (vide = nom sous l'icône). */
    var nomApp by mutableStateOf(""); private set

    fun init(ctx: Context) {
        prefs = ctx.getSharedPreferences("reglages", Context.MODE_PRIVATE)
        theme = runCatching { Theme.valueOf(prefs.getString("theme", "SOMBRE")!!) }.getOrDefault(Theme.SOMBRE)
        reprendreLecture = prefs.getBoolean("reprendre", true)
        modeLectureAuto = runCatching { ModeLectureAuto.valueOf(prefs.getString("lectureAuto", "ARRETER")!!) }
            .getOrDefault(ModeLectureAuto.ARRETER)
        gesteLuminosite = prefs.getBoolean("gesteLuminosite", true)
        gesteVolume = prefs.getBoolean("gesteVolume", true)
        imageDansImage = prefs.getBoolean("pip", true)
        biometrie = prefs.getBoolean("biometrie", true)
        ongletActuel = prefs.getInt("onglet", 0)
        nomApp = prefs.getString("nomApp", "") ?: ""
    }

    fun changerTheme(v: Theme) { theme = v; prefs.edit().putString("theme", v.name).apply() }
    fun changerReprendre(v: Boolean) { reprendreLecture = v; prefs.edit().putBoolean("reprendre", v).apply() }
    fun changerLectureAuto(v: ModeLectureAuto) { modeLectureAuto = v; prefs.edit().putString("lectureAuto", v.name).apply() }
    fun changerGesteLuminosite(v: Boolean) { gesteLuminosite = v; prefs.edit().putBoolean("gesteLuminosite", v).apply() }
    fun changerGesteVolume(v: Boolean) { gesteVolume = v; prefs.edit().putBoolean("gesteVolume", v).apply() }
    fun changerImageDansImage(v: Boolean) { imageDansImage = v; prefs.edit().putBoolean("pip", v).apply() }
    fun changerBiometrie(v: Boolean) { biometrie = v; prefs.edit().putBoolean("biometrie", v).apply() }
    fun changerOnglet(v: Int) { ongletActuel = v; prefs.edit().putInt("onglet", v).apply() }
    fun changerNomApp(v: String) { nomApp = v.trim().take(30); prefs.edit().putString("nomApp", nomApp).apply() }

    fun texte(cle: String): String? = prefs.getString(cle, null)
    fun ecrireTexte(cle: String, valeur: String?) {
        prefs.edit().apply { if (valeur == null) remove(cle) else putString(cle, valeur) }.apply()
    }
}
