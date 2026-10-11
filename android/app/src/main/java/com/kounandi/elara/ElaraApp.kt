package com.kounandi.elara

import android.app.Application
import com.kounandi.elara.donnees.Bibliotheque
import com.kounandi.elara.donnees.Reglages
import com.kounandi.elara.ui.lecteur.Lecteur

class ElaraApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Reglages.init(this)
        Bibliotheque.init(this)
        Lecteur.init(this)
    }
}
