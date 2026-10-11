package com.kounandi.elara.donnees

import org.json.JSONObject

enum class TypeMedia { VIDEO, AUDIO }

data class Media(
    val id: String,
    val nom: String,
    val fichier: String,
    val type: TypeMedia,
    val duree: Long,      // millisecondes
    val taille: Long,     // octets
    val dossier: String?,
    val prive: Boolean,
    val position: Long,   // millisecondes, pour reprendre la lecture
    val date: Long,
    val empreinte: String? = null,   // pour repérer les doublons
) {
    fun json(): JSONObject = JSONObject()
        .put("id", id).put("nom", nom).put("fichier", fichier).put("type", type.name)
        .put("duree", duree).put("taille", taille).put("dossier", dossier ?: JSONObject.NULL)
        .put("prive", prive).put("position", position).put("date", date)
        .put("empreinte", empreinte ?: JSONObject.NULL)

    companion object {
        fun depuis(o: JSONObject) = Media(
            id = o.getString("id"),
            nom = o.getString("nom"),
            fichier = o.getString("fichier"),
            type = runCatching { TypeMedia.valueOf(o.getString("type")) }.getOrDefault(TypeMedia.VIDEO),
            duree = o.optLong("duree"),
            taille = o.optLong("taille"),
            dossier = if (o.isNull("dossier")) null else o.optString("dossier"),
            prive = o.optBoolean("prive"),
            position = o.optLong("position"),
            date = o.optLong("date"),
            empreinte = if (o.isNull("empreinte")) null else o.optString("empreinte").ifEmpty { null },
        )
    }
}

data class Dossier(val id: String, val nom: String) {
    fun json(): JSONObject = JSONObject().put("id", id).put("nom", nom)

    companion object {
        const val LONGUEUR_MAX = 20
        fun depuis(o: JSONObject) = Dossier(o.getString("id"), o.getString("nom"))
    }
}

object Format {
    fun duree(ms: Long): String {
        if (ms <= 0) return "00:00"
        val total = (ms + 500) / 1000
        val h = total / 3600
        val m = (total % 3600) / 60
        val s = total % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
    }

    fun taille(octets: Long): String {
        if (octets < 1024) return "$octets o"
        val ko = octets / 1024.0
        if (ko < 1024) return "%.0f Ko".format(ko)
        val mo = ko / 1024.0
        if (mo < 1024) return "%.1f Mo".format(mo)
        return "%.2f Go".format(mo / 1024.0)
    }
}
