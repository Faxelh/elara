package com.kounandi.elara.ui.tiktok

import android.annotation.SuppressLint
import android.content.Context
import android.content.MutableContextWrapper
import android.graphics.Bitmap
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.kounandi.elara.R
import com.kounandi.elara.donnees.Bibliotheque
import com.kounandi.elara.donnees.Media
import com.kounandi.elara.donnees.Reglages
import com.kounandi.elara.donnees.Telechargeur
import com.kounandi.elara.ui.commun.Elara
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import org.json.JSONTokener
import kotlin.coroutines.resume

/** Navigateur TikTok intégré : quand une vidéo joue, Elara propose de la télécharger. */
object NavigateurTikTok {
    const val ACCUEIL = "https://www.tiktok.com/foryou"

    private var vue: WebView? = null
    private var enveloppe: MutableContextWrapper? = null
    private val principal = Handler(Looper.getMainLooper())
    var chargement by mutableStateOf(false); private set
    var peutReculer by mutableStateOf(false); private set
    var video by mutableStateOf<String?>(null)
    private val ignorees = mutableSetOf<String>()
    private val vus = ArrayList<String>()

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
            userAgentString = Telechargeur.AGENT_MOBILE
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(w, true)
        w.addJavascriptInterface(Pont(), "ElaraTikTok")
        w.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                chargement = true
                view.evaluateJavascript(SCRIPT, null)
            }
            override fun onPageFinished(view: WebView, url: String?) {
                chargement = false
                peutReculer = view.canGoBack()
                view.evaluateJavascript(SCRIPT, null)
                url?.let { if (Uri.parse(it).host?.contains("tiktok.com") == true) Reglages.ecrireTexte("tiktok.page", it) }
                CookieManager.getInstance().flush()
            }
            override fun doUpdateVisitedHistory(view: WebView, url: String?, isReload: Boolean) {
                peutReculer = view.canGoBack()
            }
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val schema = request.url.scheme ?: return true
                return schema != "http" && schema != "https"   // « Ouvrir l'app TikTok » reste dans Elara
            }
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                val u = request.url.toString()
                if (u.contains("/video/tos/") || u.contains("mime_type=video")) {
                    synchronized(vus) { vus.remove(u); vus.add(u); while (vus.size > 20) vus.removeAt(0) }
                }
                return null
            }
        }
        w.loadUrl(Reglages.texte("tiktok.page")?.takeIf { Uri.parse(it).host?.contains("tiktok.com") == true } ?: ACCUEIL)
        vue = w
        return w
    }

    fun reculer() { vue?.goBack() }
    fun recharger() { vue?.reload() }
    fun allerAccueil() { vue?.loadUrl(ACCUEIL) }

    fun fermerBandeau() { video?.let { ignorees += it }; video = null }
    fun marquerTelechargee(lien: String) { ignorees += lien }

    /** Fichier de la vidéo affichée (celle qui joue, sinon la plus visible, sinon le dernier fichier vu). */
    suspend fun lienVideoVisible(): String? {
        val w = vue ?: return null
        val js = "window.__elaraTikTok ? window.__elaraTikTok() : ''"
        val r: String? = suspendCancellableCoroutine<String?> { suite ->
            w.evaluateJavascript(js) { brut -> suite.resume(runCatching { JSONTokener(brut).nextValue() as? String }.getOrNull()) }
        }
        return r?.takeIf { it.startsWith("https://") } ?: synchronized(vus) { vus.lastOrNull() }
    }

    private class Pont {
        @JavascriptInterface
        fun lecture(src: String) {
            principal.post {
                val lien = src.takeIf { it.startsWith("https://") } ?: synchronized(vus) { vus.lastOrNull() } ?: return@post
                if (lien !in ignorees) video = lien
            }
        }
    }

    private val SCRIPT = """
    (function () {
      if (window.__elaraTT) return;
      window.__elaraTT = true;
      function source(v) {
        var s = v.currentSrc || v.src || '';
        if (s.indexOf('https://') !== 0) {
          var el = v.querySelector('source');
          if (el && el.src && el.src.indexOf('https://') === 0) s = el.src;
        }
        return s.indexOf('https://') === 0 ? s : '';
      }
      window.__elaraTikTok = function () {
        var meilleure = null, score = 0;
        document.querySelectorAll('video').forEach(function (v) {
          var r = v.getBoundingClientRect();
          var visible = Math.max(0, Math.min(r.bottom, innerHeight) - Math.max(r.top, 0)) * Math.max(0, Math.min(r.right, innerWidth) - Math.max(r.left, 0));
          var s = visible * (v.paused ? 1 : 4);
          if (s > score) { score = s; meilleure = v; }
        });
        return meilleure ? source(meilleure) : '';
      };
      document.addEventListener('play', function (e) {
        var v = e.target;
        if (!v || v.tagName !== 'VIDEO') return;
        setTimeout(function () { try { ElaraTikTok.lecture(source(v)); } catch (err) {} }, 300);
      }, true);
    })();
    """.trimIndent()
}

@Composable
fun TikTokEcran(marges: PaddingValues) {
    val contexte = LocalContext.current
    val scope = rememberCoroutineScope()
    var erreur by remember { mutableStateOf<String?>(null) }
    var ajoute by remember { mutableStateOf<Media?>(null) }

    BackHandler(enabled = NavigateurTikTok.peutReculer) { NavigateurTikTok.reculer() }
    LaunchedEffect(NavigateurTikTok.video) {
        if (NavigateurTikTok.video != null && !Telechargeur.enCours) { ajoute = null; erreur = null }
    }

    fun telecharger(lien: String?) {
        erreur = null
        ajoute = null
        NavigateurTikTok.video = null
        scope.launch {
            try {
                val cible = lien ?: NavigateurTikTok.lienVideoVisible()
                    ?: throw Exception(contexte.getString(R.string.erreur_introuvable))
                val media = Telechargeur.telechargerTikTok(contexte, cible, false)
                NavigateurTikTok.marquerTelechargee(cible)
                ajoute = media
                delay(2500)
                if (ajoute == media) ajoute = null
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                val m = e.message ?: contexte.getString(R.string.erreur_inconnue)
                erreur = m
                delay(6000)
                if (erreur == m) erreur = null
            }
        }
    }

    Column(Modifier.fillMaxSize().background(Color.Black).padding(bottom = marges.calculateBottomPadding())) {
        Row(
            Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface).statusBarsPadding().padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = { NavigateurTikTok.reculer() }, enabled = NavigateurTikTok.peutReculer) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.page_precedente))
            }
            Text("TikTok", fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.weight(1f).padding(start = 8.dp))
            IconButton(onClick = { telecharger(null) }, enabled = !Telechargeur.enCours) {
                Icon(Icons.Filled.Download, stringResource(R.string.telecharger_video_affichee), tint = Elara.accent)
            }
            IconButton(onClick = { NavigateurTikTok.allerAccueil() }) { Icon(Icons.Filled.Home, null) }
            IconButton(onClick = { NavigateurTikTok.recharger() }) { Icon(Icons.Filled.Refresh, stringResource(R.string.recharger)) }
        }
        if (NavigateurTikTok.chargement) LinearProgressIndicator(Modifier.fillMaxWidth(), color = Color(0xFFFE2C55))
        Box(Modifier.weight(1f).fillMaxWidth()) {
            AndroidView(
                factory = { ctx ->
                    NavigateurTikTok.vue(ctx).also { v ->
                        (v.parent as? ViewGroup)?.removeView(v)
                        v.layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    }
                },
                onRelease = { v -> (v.parent as? ViewGroup)?.removeView(v) },
                modifier = Modifier.fillMaxSize(),
            )
            val video = NavigateurTikTok.video
            val visible = Telechargeur.enCours || erreur != null || ajoute != null || video != null
            Glissant(visible, Modifier.align(Alignment.BottomCenter).widthIn(max = 640.dp).padding(12.dp)) {
                Row(
                    Modifier.fillMaxWidth().shadow(12.dp, RoundedCornerShape(20.dp)).clip(RoundedCornerShape(20.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant).padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    val e = erreur
                    val a = ajoute
                    when {
                        Telechargeur.enCours -> {
                            CircularProgressIndicator(
                                progress = { Telechargeur.progression }, modifier = Modifier.size(26.dp),
                                color = Elara.accent, strokeWidth = 3.dp,
                            )
                            Spacer(Modifier.width(12.dp))
                            Text(stringResource(R.string.telechargement), fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                            TextButton(onClick = { Telechargeur.annuler() }) { Text(stringResource(R.string.annuler), color = Elara.corail) }
                        }
                        e != null -> {
                            Icon(Icons.Filled.Warning, null, tint = Color(0xFFFFA726))
                            Spacer(Modifier.width(12.dp))
                            Text(e, fontSize = 14.sp, modifier = Modifier.weight(1f))
                            IconButton(onClick = { erreur = null }) { Icon(Icons.Filled.Close, stringResource(R.string.fermer)) }
                        }
                        a != null -> {
                            Icon(Icons.Filled.CheckCircle, null, tint = Elara.vert, modifier = Modifier.size(28.dp))
                            Spacer(Modifier.width(12.dp))
                            Column(Modifier.weight(1f)) {
                                Text(
                                    stringResource(if (Bibliotheque.doublon.value?.id == a.id) R.string.deja_dans_elara else R.string.video_ajoutee),
                                    fontWeight = FontWeight.Bold, fontSize = 15.sp,
                                )
                                Text(a.nom, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                            IconButton(onClick = { ajoute = null }) { Icon(Icons.Filled.Close, stringResource(R.string.fermer)) }
                        }
                        video != null -> {
                            Icon(Icons.Filled.PlayCircle, null, tint = Elara.accent, modifier = Modifier.size(28.dp))
                            Spacer(Modifier.width(12.dp))
                            Column(Modifier.weight(1f)) {
                                Text(stringResource(R.string.video_en_lecture), fontWeight = FontWeight.Bold, fontSize = 15.sp)
                                Text(stringResource(R.string.la_telecharger), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Button(
                                onClick = { telecharger(video) },
                                colors = ButtonDefaults.buttonColors(containerColor = Elara.accent),
                                contentPadding = PaddingValues(horizontal = 14.dp),
                            ) { Text(stringResource(R.string.telecharger)) }
                            IconButton(onClick = { NavigateurTikTok.fermerBandeau() }) { Icon(Icons.Filled.Close, stringResource(R.string.fermer)) }
                        }
                    }
                }
            }
        }
    }
}

/** Bandeau qui glisse depuis le bas (hors de la Column : évite la version « ColumnScope »). */
@Composable
private fun Glissant(visible: Boolean, modifier: Modifier, contenu: @Composable () -> Unit) {
    AnimatedVisibility(
        visible = visible, modifier = modifier,
        enter = slideInVertically { it }, exit = slideOutVertically { it },
    ) { contenu() }
}
