package com.kounandi.elara.donnees

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.security.MessageDigest
import java.security.SecureRandom

enum class MethodeVerrou { CODE, SCHEMA }

/**
 * Verrou du dossier privé : un code (4 à 8 chiffres) ou un schéma (points reliés),
 * avec l'empreinte digitale ou le visage en option.
 * Seule une empreinte salée (SHA-256) est enregistrée, jamais le code lui-même.
 */
object Coffre {
    var deverrouille by mutableStateOf(false)
        private set

    val estConfigure: Boolean get() = Reglages.texte("coffre.empreinte") != null

    val methode: MethodeVerrou
        get() = runCatching { MethodeVerrou.valueOf(Reglages.texte("coffre.methode") ?: "CODE") }
            .getOrDefault(MethodeVerrou.CODE)

    /** Nombre de chiffres du code (pour vérifier dès le dernier chiffre tapé). */
    val longueurCode: Int get() = Reglages.texte("coffre.longueur")?.toIntOrNull() ?: 4

    fun definir(methode: MethodeVerrou, secret: String) {
        val sel = ByteArray(16).also { SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it) }
        Reglages.ecrireTexte("coffre.sel", sel)
        Reglages.ecrireTexte("coffre.methode", methode.name)
        Reglages.ecrireTexte("coffre.empreinte", hacher(sel, secret))
        Reglages.ecrireTexte("coffre.longueur", secret.length.toString())
        deverrouille = true
    }

    fun verifier(secret: String): Boolean {
        val sel = Reglages.texte("coffre.sel") ?: return false
        val ok = hacher(sel, secret) == Reglages.texte("coffre.empreinte")
        if (ok) deverrouille = true
        return ok
    }

    fun ouvrirParBiometrie() { deverrouille = true }

    fun verrouiller() { deverrouille = false }

    private fun hacher(sel: String, secret: String): String =
        MessageDigest.getInstance("SHA-256").digest("$sel:$secret".toByteArray())
            .joinToString("") { "%02x".format(it) }
}
