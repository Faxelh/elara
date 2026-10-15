package com.kounandi.elara.ui.x

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
import com.kounandi.elara.ui.commun.AntiApp
import com.kounandi.elara.ui.commun.Elara
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import org.json.JSONTokener
import kotlin.coroutines.resume

/** Vidéo repérée dans X : le numéro du post (le plus fiable) et le fichier vu passer pendant la lecture. */
data class LectureX(val numero: String?, val fichier: String?) {
    val cle: String get() = numero ?: fichier ?: ""

    companion object {
        fun depuis(json: String?): LectureX? = runCatching {
            val o = org.json.JSONObject(json ?: return null)
            val n = o.optString("numero").ifEmpty { null }
            val f = o.optString("fichier").takeIf { it.startsWith("https://") }
            if (n == null && f == null) null else LectureX(n, f)
        }.getOrNull()
    }
}

/** Navigateur X (Twitter) intégré : quand une vidéo joue, Elara propose de la télécharger. */
object NavigateurX {
    const val ACCUEIL = "https://x.com/home"

    private var vue: WebView? = null
    private var enveloppe: MutableContextWrapper? = null
    private val principal = Handler(Looper.getMainLooper())
    var chargement by mutableStateOf(false); private set
    var peutReculer by mutableStateOf(false); private set
    var video by mutableStateOf<LectureX?>(null)
    private val ignorees = mutableSetOf<String>()
    private val vus = ArrayList<String>()

    @SuppressLint("SetJavaScriptEnabled")
    fun vue(ctx: Context): WebView {
        vue?.let { w -> enveloppe?.baseContext = ctx; return w }
        val env = MutableContextWrapper(ctx)
        enveloppe = env
        val w = WebView(env)
        AntiApp.installer(w)
        w.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            textZoom = 100
            userAgentString = Telechargeur.AGENT_MOBILE
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(w, true)
        w.addJavascriptInterface(Pont(), "ElaraX")
        w.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                chargement = true
                view.evaluateJavascript(SCRIPT, null)
                view.evaluateJavascript(AntiApp.SCRIPT, null)
            }
            override fun onPageFinished(view: WebView, url: String?) {
                chargement = false
                peutReculer = view.canGoBack()
                view.evaluateJavascript(SCRIPT, null)
                view.evaluateJavascript(AntiApp.SCRIPT, null)
                CookieManager.getInstance().flush()
            }
            override fun doUpdateVisitedHistory(view: WebView, url: String?, isReload: Boolean) {
                peutReculer = view.canGoBack()
            }
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val schema = request.url.scheme ?: return true
                return schema != "http" && schema != "https" || AntiApp.bloque(request.url)   // « Ouvrir l'app X » reste dans Elara
            }
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                val u = request.url
                if (u.host == "video.twimg.com" && (u.path ?: "").endsWith(".mp4")) {
                    val t = u.toString()
                    synchronized(vus) { vus.remove(t); vus.add(t); while (vus.size > 20) vus.removeAt(0) }
                }
                return null
            }
        }
        w.loadUrl(ACCUEIL)
        vue = w
        return w
    }

    fun reculer() { vue?.goBack() }
    fun recharger() { vue?.reload() }
    fun allerAccueil() { vue?.loadUrl(ACCUEIL) }

    fun fermerBandeau() { video?.let { ignorees += it.cle }; video = null }
    fun marquerTelechargee(lecture: LectureX) { ignorees += lecture.cle }

    /** Vidéo affichée (celle qui joue, sinon la plus visible), ou le post ouvert. */
    suspend fun lectureVisible(): LectureX? {
        val w = vue ?: return null
        val js = "JSON.stringify(window.__elaraX ? window.__elaraX() : {})"
        val brut: String? = suspendCancellableCoroutine<String?> { suite ->
            w.evaluateJavascript(js) { r -> suite.resume(runCatching { JSONTokener(r).nextValue() as? String }.getOrNull()) }
        }
        val l = LectureX.depuis(brut)
        val numero = l?.numero ?: Telechargeur.numeroX(w.url)
        val fichier = l?.fichier ?: synchronized(vus) { vus.lastOrNull() }
        return if (numero == null && fichier == null) null else LectureX(numero, fichier)
    }

    private class Pont {
        @JavascriptInterface
        fun lecture(json: String) {
            principal.post {
                val l = LectureX.depuis(json) ?: return@post
                val complete = if (l.fichier == null) l.copy(fichier = synchronized(vus) { vus.lastOrNull() }) else l
                if (complete.cle !in ignorees) video = complete
            }
        }
    }

    private val SCRIPT = """
(function () {
  if (window.__elaraXPret) return;
  window.__elaraXPret = true;
  var fichiers = [];
  function noter(u) {
    try {
      if (u && typeof u === 'object' && u.url) u = u.url;
      if (typeof u !== 'string' || u.indexOf('video.twimg.com') < 0) return;
      var chemin = u.split('?')[0];
      if (!/\.mp4$/i.test(chemin)) return;
      fichiers.push(u); if (fichiers.length > 30) fichiers.shift();
    } catch (e) {}
  }
  var f = window.fetch;
  if (f) window.fetch = function () { noter(arguments[0]); return f.apply(this, arguments); };
  var ouvrir = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (m, u) { noter(u); return ouvrir.apply(this, arguments); };

  function numeroPost(v) {
    var article = v.closest ? v.closest('article') : null;
    if (article) {
      var liens = article.querySelectorAll('a[href*="/status/"]');
      for (var i = 0; i < liens.length; i++) {
        var m = liens[i].getAttribute('href').match(/\/status\/(\d+)/);
        if (m) return m[1];
      }
    }
    var p = location.pathname.match(/\/status\/(\d+)/);
    return p ? p[1] : '';
  }
  function fichier(v) {
    var s = v.currentSrc || v.src || '';
    if (s.indexOf('https://') === 0 && /\.mp4/i.test(s)) return s;
    return fichiers.length ? fichiers[fichiers.length - 1] : '';
  }
  function decrire(v) { return JSON.stringify({ numero: numeroPost(v), fichier: fichier(v) }); }

  window.__elaraX = function () {
    var meilleure = null, score = 0;
    document.querySelectorAll('video').forEach(function (v) {
      var r = v.getBoundingClientRect();
      var visible = Math.max(0, Math.min(r.bottom, innerHeight) - Math.max(r.top, 0)) * Math.max(0, Math.min(r.right, innerWidth) - Math.max(r.left, 0));
      var s = visible * (v.paused ? 1 : 4);
      if (s > score) { score = s; meilleure = v; }
    });
    if (!meilleure) {
      var p = location.pathname.match(/\/status\/(\d+)/);
      return { numero: p ? p[1] : '', fichier: '' };
    }
    return JSON.parse(decrire(meilleure));
  };
  document.addEventListener('play', function (e) {
    var v = e.target;
    if (!v || v.tagName !== 'VIDEO') return;
    setTimeout(function () { try { ElaraX.lecture(decrire(v)); } catch (err) {} }, 300);
  }, true);
})();
""".trimIndent()
}

@Composable
fun XEcran(marges: PaddingValues) {
    val contexte = LocalContext.current
    val scope = rememberCoroutineScope()
    var erreur by remember { mutableStateOf<String?>(null) }
    var ajoute by remember { mutableStateOf<Media?>(null) }

    BackHandler(enabled = NavigateurX.peutReculer) { NavigateurX.reculer() }
    LaunchedEffect(NavigateurX.video) {
        if (NavigateurX.video != null && !Telechargeur.enCours) { ajoute = null; erreur = null }
    }

    fun telecharger(lecture: LectureX?) {
        erreur = null
        ajoute = null
        NavigateurX.video = null
        scope.launch {
            try {
                val cible = lecture ?: NavigateurX.lectureVisible()
                    ?: throw Exception(contexte.getString(R.string.erreur_introuvable))
                val media = Telechargeur.telechargerX(contexte, cible.numero, cible.fichier, false)
                NavigateurX.marquerTelechargee(cible)
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
            IconButton(onClick = { NavigateurX.reculer() }, enabled = NavigateurX.peutReculer) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.page_precedente))
            }
            Text("X", fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.weight(1f).padding(start = 8.dp))
            IconButton(onClick = { telecharger(null) }, enabled = !Telechargeur.enCours) {
                Icon(Icons.Filled.Download, stringResource(R.string.telecharger_video_affichee), tint = Elara.accent)
            }
            IconButton(onClick = { NavigateurX.allerAccueil() }) { Icon(Icons.Filled.Home, null) }
            IconButton(onClick = { NavigateurX.recharger() }) { Icon(Icons.Filled.Refresh, stringResource(R.string.recharger)) }
        }
        if (NavigateurX.chargement) LinearProgressIndicator(Modifier.fillMaxWidth(), color = Color(0xFF1D9BF0))
        Box(Modifier.weight(1f).fillMaxWidth()) {
            AndroidView(
                factory = { ctx ->
                    NavigateurX.vue(ctx).also { v ->
                        (v.parent as? ViewGroup)?.removeView(v)
                        v.layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    }
                },
                onRelease = { v -> (v.parent as? ViewGroup)?.removeView(v) },
                modifier = Modifier.fillMaxSize(),
            )
            val video = NavigateurX.video
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
                            IconButton(onClick = { NavigateurX.fermerBandeau() }) { Icon(Icons.Filled.Close, stringResource(R.string.fermer)) }
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
