package com.kounandi.elara.ui.youtube

import com.kounandi.elara.ui.commun.AntiApp
import android.annotation.SuppressLint
import android.content.Context
import android.content.MutableContextWrapper
import android.graphics.Bitmap
import android.net.Uri
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.kounandi.elara.R
import com.kounandi.elara.donnees.Reglages

/** Navigateur YouTube intégré (on regarde YouTube dans Elara, sans téléchargement). */
object NavigateurYouTube {
    const val ACCUEIL = "https://m.youtube.com/"

    private var vue: WebView? = null
    private var enveloppe: MutableContextWrapper? = null
    var chargement by mutableStateOf(false); private set
    var peutReculer by mutableStateOf(false); private set
    var peutAvancer by mutableStateOf(false); private set
    /** Vidéo YouTube en plein écran (bouton plein écran du lecteur YouTube). */
    var vuePleinEcran by mutableStateOf<View?>(null); private set
    private var rappelPleinEcran: WebChromeClient.CustomViewCallback? = null

    @SuppressLint("SetJavaScriptEnabled")
    fun vue(ctx: Context): WebView {
        vue?.let { w -> enveloppe?.baseContext = ctx; return w }
        val env = MutableContextWrapper(ctx)
        enveloppe = env
        val w = WebView(env)
        w.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            textZoom = 100
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(w, true)
        w.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                chargement = true
                maj(view)
                view.evaluateJavascript(AntiApp.SCRIPT, null)
            }
            override fun onPageFinished(view: WebView, url: String?) {
                chargement = false
                maj(view)
                view.evaluateJavascript(AntiApp.SCRIPT, null)
                url?.let { if (Uri.parse(it).host?.contains("youtube.com") == true) Reglages.ecrireTexte("youtube.page", it) }
                CookieManager.getInstance().flush()
            }
            override fun doUpdateVisitedHistory(view: WebView, url: String?, isReload: Boolean) {
                maj(view)
                url?.let { if (Uri.parse(it).host?.contains("youtube.com") == true) Reglages.ecrireTexte("youtube.page", it) }
            }
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val schema = request.url.scheme ?: return true
                return schema != "http" && schema != "https" || AntiApp.bloque(request.url)   // « Ouvrir l'app YouTube » reste dans Elara
            }
        }
        w.webChromeClient = object : WebChromeClient() {
            override fun onShowCustomView(view: View, callback: CustomViewCallback) {
                vuePleinEcran = view
                rappelPleinEcran = callback
            }
            override fun onHideCustomView() {
                vuePleinEcran = null
                rappelPleinEcran = null
            }
        }
        w.loadUrl(Reglages.texte("youtube.page")?.takeIf { Uri.parse(it).host?.contains("youtube.com") == true } ?: ACCUEIL)
        vue = w
        return w
    }

    private fun maj(w: WebView) {
        peutReculer = w.canGoBack()
        peutAvancer = w.canGoForward()
    }

    fun quitterPleinEcran() {
        rappelPleinEcran?.onCustomViewHidden()
        vuePleinEcran = null
        rappelPleinEcran = null
    }

    fun reculer() { vue?.goBack() }
    fun avancer() { vue?.goForward() }
    fun recharger() { vue?.reload() }
    fun allerAccueil() { vue?.loadUrl(ACCUEIL) }
}

@Composable
fun YouTubeEcran(marges: PaddingValues) {
    val contexte = LocalContext.current
    val pleinEcran = NavigateurYouTube.vuePleinEcran

    BackHandler(enabled = pleinEcran != null || NavigateurYouTube.peutReculer) {
        if (pleinEcran != null) NavigateurYouTube.quitterPleinEcran() else NavigateurYouTube.reculer()
    }
    // Vidéo en plein écran : on cache les barres d'Android et on passe en paysage.
    DisposableEffect(pleinEcran) {
        val activite = contexte as? android.app.Activity
        val fenetre = activite?.window
        val controle = fenetre?.let { WindowCompat.getInsetsController(it, it.decorView) }
        if (pleinEcran != null) {
            controle?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controle?.hide(WindowInsetsCompat.Type.systemBars())
            activite?.requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        }
        onDispose {
            if (pleinEcran != null) {
                controle?.show(WindowInsetsCompat.Type.systemBars())
                activite?.requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            }
        }
    }

    if (pleinEcran != null) {
        AndroidView(
            factory = { pleinEcran.also { (it.parent as? ViewGroup)?.removeView(it) } },
            modifier = Modifier.fillMaxSize().background(Color.Black),
        )
        return
    }

    Column(Modifier.fillMaxSize().padding(bottom = marges.calculateBottomPadding())) {
        Row(
            Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surface)
                .statusBarsPadding()
                .padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = { NavigateurYouTube.reculer() }, enabled = NavigateurYouTube.peutReculer) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.page_precedente))
            }
            IconButton(onClick = { NavigateurYouTube.avancer() }, enabled = NavigateurYouTube.peutAvancer) {
                Icon(Icons.AutoMirrored.Filled.ArrowForward, stringResource(R.string.page_suivante))
            }
            Text("YouTube", fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.weight(1f).padding(start = 8.dp))
            IconButton(onClick = { NavigateurYouTube.allerAccueil() }) {
                Icon(Icons.Filled.Home, stringResource(R.string.accueil_youtube))
            }
            IconButton(onClick = { NavigateurYouTube.recharger() }) {
                Icon(Icons.Filled.Refresh, stringResource(R.string.recharger))
            }
        }
        if (NavigateurYouTube.chargement) {
            LinearProgressIndicator(Modifier.fillMaxWidth(), color = Color(0xFFFF0033))
        }
        Box(Modifier.weight(1f).fillMaxWidth()) {
            AndroidView(
                factory = { ctx ->
                    NavigateurYouTube.vue(ctx).also { v ->
                        (v.parent as? ViewGroup)?.removeView(v)
                        v.layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    }
                },
                onRelease = { v -> (v.parent as? ViewGroup)?.removeView(v) },
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}
