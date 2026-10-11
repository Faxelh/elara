package com.kounandi.elara.ui.facebook

import android.annotation.SuppressLint
import android.content.Context
import android.content.MutableContextWrapper
import android.graphics.Bitmap
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.kounandi.elara.donnees.ExtracteurFacebook
import com.kounandi.elara.donnees.Reglages
import com.kounandi.elara.donnees.Telechargeur
import kotlinx.coroutines.suspendCancellableCoroutine
import org.json.JSONObject
import org.json.JSONTokener
import kotlin.coroutines.resume

/** Vidéo que l'utilisateur vient de lancer dans l'onglet Facebook. */
data class VideoDetectee(val source: String, val page: String, val lien: String)

/** Ce qu'il faut télécharger : un fichier complet, ou les derniers morceaux vus (image / son séparés). */
sealed class SourceFacebook {
    data class Direct(val lien: String) : SourceFacebook()
    data class Flux(val liens: List<String>) : SourceFacebook()
}

/** Navigateur Facebook intégré : il reste ouvert quand on change d'onglet et se souvient de la dernière page. */
object NavigateurFacebook {
    const val ACCUEIL = "https://m.facebook.com/"

    private var vue: WebView? = null
    private var enveloppe: MutableContextWrapper? = null
    var video by mutableStateOf<VideoDetectee?>(null)
    /** Image touchée longuement : bandeau « Enregistrer ». */
    var imageDetectee by mutableStateOf<String?>(null)
    var chargement by mutableStateOf(false); private set
    var peutReculer by mutableStateOf(false); private set
    var peutAvancer by mutableStateOf(false); private set
    var surReel by mutableStateOf(false); private set

    private val ignorees = mutableSetOf<String>()
    private val principal = Handler(Looper.getMainLooper())

    /** Fichiers vidéo / son reçus par la page pendant la lecture (le plus récent à la fin). */
    private data class Flux(val url: String, val chemin: String, val audio: Boolean, val video: Boolean, val asset: String?)
    private val flux = ArrayList<Flux>()

    @SuppressLint("SetJavaScriptEnabled")
    fun vue(ctx: Context): WebView {
        vue?.let { w ->
            // Après une rotation ou un changement de langue, la vue suit la nouvelle activité.
            enveloppe?.baseContext = ctx
            return w
        }
        val env = MutableContextWrapper(ctx)
        enveloppe = env
        val w = WebView(env)
        w.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            // Agent du vrai Chrome de l'appareil : Facebook sert la version adaptée
            // (téléphone, grand téléphone ou tablette) et la page suit la largeur de l'écran.
            userAgentString = agentAppareil(ctx)
            useWideViewPort = true
            loadWithOverviewMode = false
            textZoom = 100
            setSupportZoom(true)
            builtInZoomControls = true
            displayZoomControls = false
        }
        w.isVerticalScrollBarEnabled = false
        w.overScrollMode = WebView.OVER_SCROLL_NEVER
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(w, true)
        w.addJavascriptInterface(Pont(), "ElaraAndroid")
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            WebViewCompat.addDocumentStartJavaScript(
                w, SCRIPT, setOf("https://facebook.com", "https://*.facebook.com"),
            )
        }
        w.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                chargement = true
                maj(view)
                if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) view.evaluateJavascript(SCRIPT, null)
            }

            override fun onPageFinished(view: WebView, url: String?) {
                chargement = false
                maj(view)
                if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) view.evaluateJavascript(SCRIPT, null)
                url?.let { u -> if (Uri.parse(u).host?.let { Telechargeur.estFacebook(it) } == true) Reglages.ecrireTexte("facebook.page", u) }
                CookieManager.getInstance().flush()
            }

            override fun doUpdateVisitedHistory(view: WebView, url: String?, isReload: Boolean) {
                maj(view)
            }

            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val schema = request.url.scheme ?: return true
                // Les liens « ouvrir l'application » (fb://, intent://) restent dans Elara.
                return schema != "http" && schema != "https"
            }

            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                noter(request.url)
                return null
            }
        }
        w.setDownloadListener { url, _, _, _, _ ->
            principal.post { video = VideoDetectee(url, url, url) }
        }
        val depart = Reglages.texte("facebook.page")?.takeIf { p ->
            Uri.parse(p).host?.let { Telechargeur.estFacebook(it) } == true
        } ?: accueil(ctx)
        // Sur tablette, la version mobile (m.facebook.com) s'affiche mal : on passe à la version complète.
        val adresse = if (estTablette(ctx)) depart.replace("://m.facebook.com", "://www.facebook.com") else depart
        w.loadUrl(adresse)
        vue = w
        return w
    }

    /** Tablette : écran d'au moins 600 dp dans sa plus petite dimension. */
    fun estTablette(ctx: Context) = ctx.resources.configuration.smallestScreenWidthDp >= 600

    private fun accueil(ctx: Context) = if (estTablette(ctx)) "https://www.facebook.com/" else ACCUEIL

    private fun agentAppareil(ctx: Context): String {
        val brut = runCatching { android.webkit.WebSettings.getDefaultUserAgent(ctx) }.getOrNull()
            ?: return Telechargeur.AGENT_MOBILE
        // On retire les marques « WebView » pour être traité comme Chrome.
        return brut.replace("; wv)", ")").replace(Regex("Version/\\d+\\.\\d+ "), "")
    }

    private fun maj(w: WebView) {
        peutReculer = w.canGoBack()
        peutAvancer = w.canGoForward()
        val chemin = Uri.parse(w.url ?: "").path ?: ""
        surReel = chemin.startsWith("/reel")
    }

    fun reculer() { vue?.goBack() }
    fun avancer() { vue?.goForward() }
    fun recharger() { vue?.reload() }
    fun allerAccueil() { vue?.let { it.loadUrl(accueil(it.context)) } }

    /** Une vidéo déjà téléchargée n'est plus proposée. */
    fun marquerTelechargee(v: VideoDetectee?) {
        v?.let { ignorees += it.source + it.page }
    }

    fun fermerBandeau() {
        video?.let { ignorees += it.source + it.page }
        video = null
    }

    fun deconnecter() {
        CookieManager.getInstance().removeAllCookies(null)
        CookieManager.getInstance().flush()
        WebStorage.getInstance().deleteAllData()
        vue?.clearCache(true)
        Reglages.ecrireTexte("facebook.page", null)
        allerAccueil()
    }

    // MARK: Fichiers vus passer sur le réseau

    private fun noter(url: Uri) {
        val hote = url.host ?: return
        val chemin = url.path ?: return
        if (!hote.endsWith("fbcdn.net") || !chemin.contains(".mp4")) return
        val propre = url.buildUpon().clearQuery().apply {
            url.queryParameterNames.filter { it != "bytestart" && it != "byteend" }.forEach { n ->
                url.getQueryParameter(n)?.let { appendQueryParameter(n, it) }
            }
        }.build().toString()
        val tag = runCatching {
            String(Base64.decode(url.getQueryParameter("efg") ?: "", Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING))
        }.getOrDefault("")
        // L'étiquette « efg » dit si le fichier est le son ou l'image, et à quelle vidéo il appartient.
        val code = Regex("\"vencode_tag\"\\s*:\\s*\"([^\"]*)\"").find(tag)?.groupValues?.get(1) ?: tag
        val audio = code.contains("audio", ignoreCase = true)
        val video = !audio && code.isNotBlank()
        val asset = Regex("\"xpv_asset_id\"\\s*:\\s*\"?(\\d+)").find(tag)?.groupValues?.get(1)
        synchronized(flux) {
            flux.removeAll { it.chemin == chemin }
            flux.add(Flux(propre, chemin, audio, video, asset))
            while (flux.size > 40) flux.removeAt(0)
        }
    }

    /** Image + son de la vidéo en cours (même numéro de vidéo), s'ils sont connus. */
    private fun paireActuelle(): List<String>? = synchronized(flux) {
        val recent = flux.lastOrNull { it.asset != null } ?: return null
        val memes = flux.filter { it.asset == recent.asset }
        val image = memes.lastOrNull { !it.audio } ?: return null
        val son = memes.lastOrNull { it.audio } ?: return null
        listOf(image.url, son.url)
    }

    /** Les derniers fichiers vus, le plus récent d'abord (Elara trie ensuite l'image et le son). */
    private fun candidats(): List<String> = synchronized(flux) {
        flux.takeLast(6).reversed().map { it.url }
    }

    /** Fichiers « son seul » vus récemment (pour ajouter le son à une vidéo muette). */
    fun sonsRecents(): List<String> = synchronized(flux) {
        val recent = flux.lastOrNull { it.asset != null }?.asset
        val sons = flux.filter { it.audio }.reversed()
        (sons.filter { it.asset == recent } + sons.filter { it.asset != recent }).map { it.url }.take(3)
    }

    // MARK: Recherche du fichier

    suspend fun source(detectee: VideoDetectee?): SourceFacebook? {
        // Le plus fiable : l'image et le son de la vidéo en train de jouer, vus passer sur le réseau.
        paireActuelle()?.let { return SourceFacebook.Flux(it) }
        val cible = detectee ?: videoVisible() ?: return candidats().takeIf { it.isNotEmpty() }?.let { SourceFacebook.Flux(it) }
        if (cible.source.startsWith("https://")) return SourceFacebook.Direct(cible.source)
        for (texte in listOf(cible.page, cible.lien)) {
            val id = numeroVideo(texte) ?: continue
            lienConnu(id)?.let { return SourceFacebook.Direct(it) }
        }
        candidats().takeIf { it.isNotEmpty() }?.let { return SourceFacebook.Flux(it) }
        for (texte in listOf(cible.lien, cible.page)) {
            if (estPageVideo(texte)) ExtracteurFacebook.lienVideo(texte)?.let { return SourceFacebook.Direct(it) }
        }
        lienUnique()?.let { return SourceFacebook.Direct(it) }
        return null
    }

    private suspend fun evaluer(js: String): String? {
        val w = vue ?: return null
        return suspendCancellableCoroutine { suite ->
            w.evaluateJavascript(js) { brut ->
                val texte = runCatching { JSONTokener(brut).nextValue() as? String }.getOrNull()
                suite.resume(texte)
            }
        }
    }

    private suspend fun lienConnu(id: String): String? {
        val texte = evaluer("JSON.stringify((window.__elaraVideos || {})['$id'] || null)") ?: return null
        val o = runCatching { JSONObject(texte) }.getOrNull() ?: return null
        return o.optString("hd").ifEmpty { o.optString("sd") }.ifEmpty { null }
    }

    private suspend fun lienUnique(): String? = evaluer(
        "(function(){var v=window.__elaraVideos||{};var k=Object.keys(v);if(k.length!==1)return '';return v[k[0]].hd||v[k[0]].sd||'';})()",
    )?.ifEmpty { null }

    private suspend fun videoVisible(): VideoDetectee? {
        val texte = evaluer("window.__elaraVideoVisible ? JSON.stringify(window.__elaraVideoVisible()) : ''") ?: return null
        val o = runCatching { JSONObject(texte) }.getOrNull() ?: return null
        return VideoDetectee(o.optString("src"), o.optString("page"), o.optString("lien"))
    }

    fun numeroVideo(texte: String): String? {
        val motifs = listOf("/(?:reel|videos|watch/live)/(\\d{6,})", "[?&](?:v|video_id)=(\\d{6,})", "/videos/[^/?]+/(\\d{6,})")
        for (m in motifs) Regex(m).find(texte)?.groupValues?.get(1)?.let { return it }
        return null
    }

    private fun estPageVideo(t: String) = listOf("/reel/", "/videos/", "/watch", "/share/v/", "/share/r/", "v=", "fb.watch").any { t.contains(it) }

    /** Reçoit les messages du script injecté. */
    private class Pont {
        @JavascriptInterface
        fun image(src: String) {
            principal.post { imageDetectee = src }
        }

        @JavascriptInterface
        fun lecture(json: String) {
            val o = runCatching { JSONObject(json) }.getOrNull() ?: return
            val d = VideoDetectee(o.optString("src"), o.optString("page"), o.optString("lien"))
            principal.post {
                if (d.source + d.page !in ignorees) video = d
            }
        }
    }

    /** Repère les vidéos lancées et garde les liens des fichiers vidéo envoyés à la page. */
    private val SCRIPT = """
    (function () {
      if (window.__elara) return;
      window.__elara = true;
      window.__elaraVideos = {};
      var compteur = 0;
      function analyser(t) {
        try {
          if (!t || typeof t !== 'string' || t.indexOf('_url') < 0 && t.indexOf('_src') < 0) return;
          var re = /"(browser_native_hd_url|browser_native_sd_url|playable_url_quality_hd|playable_url|hd_src|sd_src|progressive_url)":"((?:[^"\\]|\\.)+)"/g, m;
          while ((m = re.exec(t))) {
            var url;
            try { url = JSON.parse('"' + m[2] + '"'); } catch (e) { continue; }
            if (url.indexOf('https://') !== 0) continue;
            var avant = t.slice(Math.max(0, m.index - 3000), m.index);
            var ids = avant.match(/"(?:videoId|video_id|id)":"?(\d{6,})/g);
            var id = ids ? ids[ids.length - 1].match(/(\d{6,})/)[1] : ('x' + (compteur++));
            var e = window.__elaraVideos[id] || (window.__elaraVideos[id] = {});
            if (m[1].indexOf('hd') >= 0) { if (!e.hd) e.hd = url; } else { if (!e.sd) e.sd = url; }
          }
        } catch (e) {}
      }
      var f = window.fetch;
      if (f) {
        window.fetch = function () {
          return f.apply(this, arguments).then(function (r) {
            try { r.clone().text().then(analyser).catch(function () {}); } catch (e) {}
            return r;
          });
        };
      }
      var envoi = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function () {
        this.addEventListener('load', function () {
          try { if (this.responseType === '' || this.responseType === 'text') analyser(this.responseText); } catch (e) {}
        });
        return envoi.apply(this, arguments);
      };
      function analyserPage() { document.querySelectorAll('script').forEach(function (s) { analyser(s.textContent); }); }
      document.addEventListener('DOMContentLoaded', analyserPage);
      window.addEventListener('load', analyserPage);
      function lienProche(el) {
        var re = /\/(reel|videos|watch)\b|[?&]v=\d|\/share\/[vr]\/|fb\.watch/;
        for (var n = el, i = 0; n && n !== document.body && i < 15; n = n.parentElement, i++) {
          if (n.tagName === 'A' && re.test(n.href)) return n.href;
          var liens = n.querySelectorAll ? n.querySelectorAll('a[href]') : [];
          for (var j = 0; j < liens.length && j < 40; j++) { if (re.test(liens[j].href)) return liens[j].href; }
        }
        return '';
      }
      function decrire(v) { return { src: v.currentSrc || v.src || '', page: location.href, lien: lienProche(v) }; }
      window.__elaraVideoVisible = function () {
        var meilleure = null, surface = 0;
        document.querySelectorAll('video').forEach(function (v) {
          var r = v.getBoundingClientRect();
          var visible = Math.max(0, Math.min(r.bottom, innerHeight) - Math.max(r.top, 0)) * Math.max(0, Math.min(r.right, innerWidth) - Math.max(r.left, 0));
          var score = visible * (v.paused ? 1 : 4);
          if (score > surface) { surface = score; meilleure = v; }
        });
        return meilleure ? decrire(meilleure) : null;
      };
      // Appui long sur une image : Elara propose de l'enregistrer.
      (function () {
        try {
          var st = document.createElement('style');
          st.textContent = 'img{-webkit-touch-callout:none!important}';
          (document.head || document.documentElement).appendChild(st);
        } catch (e) {}
        var minuteur = null, depart = null;
        function imageSous(el) {
          for (var n = el, i = 0; n && n !== document.body && i < 6; n = n.parentElement, i++) {
            if (n.tagName === 'VIDEO') return '';
            if (n.tagName === 'IMG' && (n.currentSrc || n.src)) {
              if (n.naturalWidth && n.naturalWidth < 120) return '';
              return n.currentSrc || n.src;
            }
            var bg = '';
            try { bg = getComputedStyle(n).backgroundImage || ''; } catch (e) {}
            if (bg.indexOf('url(') >= 0) {
              var m = bg.match(/url\(["']?([^"')]+)["']?\)/);
              if (m) return m[1];
            }
          }
          return '';
        }
        document.addEventListener('touchstart', function (e) {
          if (e.touches.length !== 1) { clearTimeout(minuteur); return; }
          var t = e.touches[0], cible = e.target;
          depart = { x: t.clientX, y: t.clientY };
          clearTimeout(minuteur);
          minuteur = setTimeout(function () {
            var src = imageSous(cible);
            if (src && src.indexOf('http') === 0 && !/rsrc\.php|static\.xx\.fbcdn|emoji/.test(src)) ElaraAndroid.image(src);
          }, 600);
        }, { passive: true, capture: true });
        document.addEventListener('touchmove', function (e) {
          if (!depart || !e.touches[0]) return;
          var t = e.touches[0];
          if (Math.abs(t.clientX - depart.x) > 10 || Math.abs(t.clientY - depart.y) > 10) clearTimeout(minuteur);
        }, { passive: true, capture: true });
        document.addEventListener('touchend', function () { clearTimeout(minuteur); }, { passive: true, capture: true });
        document.addEventListener('touchcancel', function () { clearTimeout(minuteur); }, { passive: true, capture: true });
      })();
      document.addEventListener('play', function (e) {
        var v = e.target;
        if (!v || v.tagName !== 'VIDEO') return;
        try { ElaraAndroid.lecture(JSON.stringify(decrire(v))); } catch (err) {}
      }, true);
    })();
    """.trimIndent()
}
