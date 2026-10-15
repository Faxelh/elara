#if PERSO
import Foundation
import Observation
import WebKit

/// Vidéo que l'utilisateur vient de lancer dans l'onglet Facebook.
struct VideoDetectee: Equatable {
    var source: String   // src de la balise <video> (souvent « blob: »)
    var page: String     // adresse de la page
    var lien: String     // lien vers la vidéo trouvé autour du lecteur
}

/// Ce que le téléchargement doit récupérer : un fichier complet, ou des morceaux (image / son séparés).
enum SourceFacebook {
    case direct(URL)
    case flux([URL])   // adresses vues pendant la lecture, la plus récente d'abord
}

/// Navigateur Facebook intégré (version perso).
/// Il reste ouvert quand on change d'onglet et se souvient de la dernière page.
@MainActor
@Observable
final class NavigateurFacebook: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    static let partage = NavigateurFacebook()
    static let accueil = URL(string: "https://m.facebook.com/")!
    private static let cleDernierePage = "facebook.dernierePage"

    @ObservationIgnored let vue: WKWebView
    private(set) var peutReculer = false
    private(set) var peutAvancer = false
    private(set) var chargement = false
    /// Vrai sur une page Reels : l'onglet passe en plein écran.
    private(set) var surReel = false
    /// Vidéo en cours de lecture : affiche le bandeau « Télécharger / Fermer ».
    var video: VideoDetectee?
    /// Image touchée longuement : affiche le bandeau « Enregistrer dans Photos ».
    var imageDetectee: String?
    @ObservationIgnored private var ignorees: Set<String> = []

    private override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        let controleur = WKUserContentController()
        controleur.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        AntiApp.installer(controleur)
        controleur.addUserScript(WKUserScript(source: Self.scriptReels, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController = controleur
        vue = WKWebView(frame: .zero, configuration: configuration)
        vue.customUserAgent = ExtracteurFacebook.agentMobile
        // Défilement fluide des Reels : pas de geste « retour » qui intercepte les glissements,
        // pas de rebond, et la page gère elle-même sa hauteur.
        vue.allowsBackForwardNavigationGestures = false
        vue.scrollView.bounces = false
        vue.scrollView.contentInsetAdjustmentBehavior = .never
        vue.scrollView.decelerationRate = .normal
        super.init()
        controleur.add(self, name: "elara")
        vue.navigationDelegate = self
        vue.uiDelegate = self
        surveillerAdresse()

        var depart = Self.accueil
        if let texte = UserDefaults.standard.string(forKey: Self.cleDernierePage),
           let url = URL(string: texte), let hote = url.host, ExtracteurFacebook.gere(hote) {
            depart = url
        }
        vue.load(URLRequest(url: depart))
    }

    func reculer() { vue.goBack() }
    func avancer() { vue.goForward() }
    func recharger() { vue.reload() }
    func allerAccueil() { vue.load(URLRequest(url: Self.accueil)) }

    /// Une vidéo déjà téléchargée n'est plus proposée.
    func marquerTelechargee(_ v: VideoDetectee?) {
        if let v { ignorees.insert(v.source + v.page) }
    }

    func fermerBandeau() {
        if let video { ignorees.insert(video.source + video.page) }
        video = nil
    }

    // MARK: - Recherche du fichier de la vidéo

    /// Trouve le lien du fichier mp4 de la vidéo détectée (ou de celle visible à l'écran).
    func lienFichier(pour detectee: VideoDetectee?) async throws -> SourceFacebook {
        var cible = detectee
        if cible == nil { cible = await videoVisible() }
        guard let cible else {
            throw ErreurTelechargement(message: String(localized: "Lancez d'abord la lecture de la vidéo, puis touchez Télécharger."))
        }
        // 1. Le lecteur lit directement un fichier mp4.
        if cible.source.hasPrefix("https://"), let url = URL(string: cible.source) { return .direct(url) }

        // 2. Numéro de la vidéo dans l'adresse de la page ou dans un lien proche du lecteur.
        for texte in [cible.page, cible.lien] {
            if let id = Self.numeroVideo(dans: texte), let url = await lienConnu(id: id) { return .direct(url) }
        }
        // 2b. Adresse du fichier vue passer sur le réseau pendant la lecture (Reels).
        let flux = await candidatsFlux()
        if !flux.isEmpty { return .flux(flux) }
        // 3. Ouvrir la page de la vidéo (avec la connexion Facebook) et y chercher le fichier.
        for texte in [cible.lien, cible.page] where Self.estPageVideo(texte) {
            if let url = URL(string: texte), let lien = try? await ExtracteurFacebook.lienVideo(depuis: url) {
                return .direct(lien)
            }
        }
        // 4. Une seule vidéo chargée sur la page : c'est forcément elle.
        if let url = await lienUnique() { return .direct(url) }
        throw ErreurTelechargement(message: String(localized: "Impossible de trouver le fichier de cette vidéo. Ouvrez la vidéo en plein écran (touchez-la) puis réessayez."))
    }

    private func lienConnu(id: String) async -> URL? {
        let js = "JSON.stringify((window.__elaraVideos || {})['\(id)'] || null)"
        guard let texte = await evaluer(js),
              let objet = try? JSONSerialization.jsonObject(with: Data(texte.utf8)) as? [String: String] else { return nil }
        return (objet["hd"] ?? objet["sd"]).flatMap(URL.init(string:))
    }

    /// Les 4 derniers fichiers vidéo / son reçus par la page, le plus récent d'abord.
    private func candidatsFlux() async -> [URL] {
        // L'image et le son de LA vidéo qui joue ; à défaut (fichiers sans étiquette), les derniers vus.
        let js = """
        JSON.stringify((window.__elaraPaire && window.__elaraPaire().length) ? window.__elaraPaire()
          : (window.__elaraFlux || []).filter(function(e){ return !e.asset; }).slice(-4).reverse().map(function(e){ return e.url; }))
        """
        guard let texte = await evaluer(js),
              let liste = try? JSONSerialization.jsonObject(with: Data(texte.utf8)) as? [String] else { return [] }
        return liste.compactMap(URL.init(string:))
    }

    private func lienUnique() async -> URL? {
        let js = """
        (function(){ var v = window.__elaraVideos || {}; var k = Object.keys(v);
          if (k.length !== 1) return ''; return v[k[0]].hd || v[k[0]].sd || ''; })()
        """
        guard let texte = await evaluer(js), !texte.isEmpty else { return nil }
        return URL(string: texte)
    }

    private func videoVisible() async -> VideoDetectee? {
        guard let texte = await evaluer("window.__elaraVideoVisible ? JSON.stringify(window.__elaraVideoVisible()) : ''"),
              let objet = try? JSONSerialization.jsonObject(with: Data(texte.utf8)) as? [String: String] else { return nil }
        return VideoDetectee(source: objet["src"] ?? "", page: objet["page"] ?? "", lien: objet["lien"] ?? "")
    }

    private func evaluer(_ js: String) async -> String? {
        await withCheckedContinuation { suite in
            vue.evaluateJavaScript(js) { resultat, _ in
                suite.resume(returning: resultat as? String)
            }
        }
    }

    nonisolated static func numeroVideo(dans texte: String) -> String? {
        let motifs = [#"/(?:reel|videos|watch/live)/(\d{6,})"#, #"[?&](?:v|video_id)=(\d{6,})"#, #"/videos/[^/?]+/(\d{6,})"#]
        for motif in motifs {
            if let regex = try? NSRegularExpression(pattern: motif),
               let m = regex.firstMatch(in: texte, range: NSRange(texte.startIndex..., in: texte)),
               let r = Range(m.range(at: 1), in: texte) {
                return String(texte[r])
            }
        }
        return nil
    }

    nonisolated static func estPageVideo(_ texte: String) -> Bool {
        texte.contains("/reel/") || texte.contains("/videos/") || texte.contains("/watch") ||
        texte.contains("/share/v/") || texte.contains("/share/r/") || texte.contains("v=") || texte.contains("fb.watch")
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ controleur: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let corps = message.body as? [String: Any] else { return }
        if corps["maj"] != nil { majBoutons(); return }
        if corps["type"] as? String == "image" {
            imageDetectee = corps["src"] as? String
            return
        }
        let detectee = VideoDetectee(
            source: corps["src"] as? String ?? "",
            page: corps["page"] as? String ?? "",
            lien: corps["lien"] as? String ?? ""
        )
        guard !ignorees.contains(detectee.source + detectee.page) else { return }
        video = detectee
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        chargement = true
        majBoutons()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        chargement = false
        majBoutons()
        if let url = webView.url, let hote = url.host, ExtracteurFacebook.gere(hote) {
            UserDefaults.standard.set(url.absoluteString, forKey: Self.cleDernierePage)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        chargement = false
        majBoutons()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        chargement = false
        majBoutons()
    }

    /// Liens « Ouvrir l'application » / App Store : on reste dans Elara.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        AntiApp.bloque(navigationAction.request.url) ? .cancel : .allow
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        majBoutons()
    }

    /// Liens qui ouvrent une nouvelle fenêtre : on les ouvre dans le même onglet.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    private func majBoutons() {
        peutReculer = vue.canGoBack
        peutAvancer = vue.canGoForward
        let chemin = vue.url?.path ?? ""
        surReel = chemin.hasPrefix("/reel") || chemin.hasPrefix("/reels")
    }

    /// Facebook change de page sans recharger (navigation interne) : on suit l'adresse.
    func surveillerAdresse() {
        observation = vue.observe(\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.majBoutons() }
        }
    }
    @ObservationIgnored private var observation: NSKeyValueObservation?

    // MARK: - Script injecté dans les pages Facebook

    /// Repère les vidéos lancées et garde en mémoire les liens des fichiers vidéo
    /// envoyés par Facebook à la page (pour retrouver celui de la vidéo regardée).
    /// Reels : à la fin d'un Reel, « Suivante dans 2 s » puis passage automatique au suivant.
    static let scriptReels = #"""
(function () {
  if (window.__elaraReels) return;
  window.__elaraReels = true;
  var minuteur = null, bulle = null;
  function surReel() { return /\/reels?\b/.test(location.pathname); }
  var decompte = null;
  function annuler() {
    if (minuteur) { clearTimeout(minuteur); minuteur = null; }
    if (decompte) { clearInterval(decompte); decompte = null; }
    if (bulle) { bulle.remove(); bulle = null; }
  }
  function defilant(el) {
    for (var n = el.parentElement; n && n !== document.body; n = n.parentElement) {
      var s = getComputedStyle(n);
      if (/(auto|scroll)/.test(s.overflowY) && n.scrollHeight > n.clientHeight + 10) return n;
    }
    return null;
  }
  function suivante(v) {
    annuler();
    var r0 = v.getBoundingClientRect();
    var prochaine = null, haut = Infinity;
    document.querySelectorAll('video').forEach(function (x) {
      if (x === v) return;
      var t = x.getBoundingClientRect().top;
      if (t > r0.top + 20 && t < haut) { haut = t; prochaine = x; }
    });
    var c = defilant(v);
    if (prochaine) prochaine.scrollIntoView({ behavior: 'smooth', block: 'center' });
    else if (c) c.scrollBy({ top: c.clientHeight, behavior: 'smooth' });
    else window.scrollBy({ top: innerHeight, behavior: 'smooth' });
  }
  // À la fin d'un Reel : « Suivante dans 2 s », puis passage au Reel suivant.
  function annoncer(v) {
    if (minuteur || !surReel()) return;
    bulle = document.createElement('div');
    bulle.textContent = 'Suivante dans 2 s';
    bulle.style.cssText = 'position:fixed;left:50%;bottom:120px;transform:translateX(-50%);z-index:2147483647;' +
      'background:rgba(0,0,0,.72);color:#fff;font:600 14px -apple-system,Roboto,sans-serif;padding:8px 14px;' +
      'border-radius:18px;pointer-events:none';
    (document.body || document.documentElement).appendChild(bulle);
    // Compte à rebours visible : 2… 1… puis vidéo suivante.
    var reste = 2;
    decompte = setInterval(function () {
      reste--;
      if (reste > 0 && bulle) bulle.textContent = 'Suivante dans ' + reste + ' s';
    }, 1000);
    minuteur = setTimeout(function () { minuteur = null; suivante(v); }, 2000);
  }
  document.addEventListener('ended', function (e) {
    if (e.target && e.target.tagName === 'VIDEO') annoncer(e.target);
  }, true);
  // Les Reels tournent en boucle : on repère le retour au début.
  document.addEventListener('timeupdate', function (e) {
    var v = e.target;
    if (!v || v.tagName !== 'VIDEO') return;
    var avant = v.__elaraT || 0;
    v.__elaraT = v.currentTime;
    if (v.duration > 2 && avant > v.duration - 1.2 && v.currentTime < 1) annoncer(v);
  }, true);
  // Le moindre geste de l'utilisateur annule le passage automatique.
  ['touchstart', 'wheel'].forEach(function (t) { document.addEventListener(t, annuler, { capture: true, passive: true }); });
})();
"""#

    static let script = #"""
    (function () {
      if (window.__elara) return;
      window.__elara = true;
      window.__elaraVideos = {};
      window.__elaraFlux = [];
      window.__elaraActivite = {};

      // Vidéo en cours de lecture = celle dont la page demande le plus de morceaux en ce moment
      // (les Reels suivants ne sont que préchargés). On renvoie SON image et SON son, jamais ceux d'une autre.
      window.__elaraPaire = function () {
        var liste = window.__elaraFlux, act = window.__elaraActivite, maintenant = Date.now();
        var meilleur = '', score = -1, dernier = 0;
        Object.keys(act).forEach(function (a) {
          if (!liste.some(function (e) { return e.asset === a && !e.audio; })) return;
          var n = act[a].filter(function (t) { return maintenant - t < 15000; }).length * 1000
                + act[a].filter(function (t) { return maintenant - t < 60000; }).length;
          var d = act[a][act[a].length - 1];
          if (n > score || (n === score && d > dernier)) { meilleur = a; score = n; dernier = d; }
        });
        if (!meilleur) return [];
        var memes = liste.filter(function (e) { return e.asset === meilleur; });
        var image = memes.filter(function (e) { return !e.audio; }).pop();
        var son = memes.filter(function (e) { return e.audio; }).pop();
        return [image, son].filter(Boolean).map(function (e) { return e.url; });
      };
      var compteur = 0;

      // Les Reels lisent des segments « blob: » : on note les vraies adresses des fichiers reçus.
      function noter(u) {
        try {
          if (u && typeof u === 'object' && u.url) u = u.url;
          if (typeof u !== 'string') return;
          var x = new URL(u, location.href);
          if (x.hostname.indexOf('fbcdn.net') < 0 || x.pathname.indexOf('.mp4') < 0) return;
          x.searchParams.delete('bytestart'); x.searchParams.delete('byteend');
          var tag = '';
          try { tag = atob((x.searchParams.get('efg') || '').replace(/-/g, '+').replace(/_/g, '/')); } catch (e) {}
          // L'étiquette « efg » dit si le fichier est le son ou l'image, et à quelle vidéo il appartient.
          var code = (tag.match(/"vencode_tag"\s*:\s*"([^"]*)"/) || [])[1] || tag;
          var audio = /audio/i.test(code);
          var asset = (tag.match(/"xpv_asset_id"\s*:\s*"?(\d+)/) || [])[1] || '';
          var maintenant = Date.now();
          if (asset) {
            var act = window.__elaraActivite[asset] || (window.__elaraActivite[asset] = []);
            act.push(maintenant);
            if (act.length > 200) act.shift();
          }
          var liste = window.__elaraFlux;
          for (var i = liste.length - 1; i >= 0; i--) { if (liste[i].chemin === x.pathname) liste.splice(i, 1); }
          liste.push({ url: x.href, chemin: x.pathname, audio: audio, asset: asset, t: maintenant });
          if (liste.length > 60) liste.shift();
        } catch (e) {}
      }
      ['pushState', 'replaceState'].forEach(function (nom) {
        var o = history[nom];
        history[nom] = function () {
          var r = o.apply(this, arguments);
          try { window.webkit.messageHandlers.elara.postMessage({ maj: 1 }); } catch (e) {}
          return r;
        };
      });

      function analyser(t) {
        try {
          if (!t || typeof t !== 'string' || t.indexOf('_url') < 0) return;
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

      var fetchOriginal = window.fetch;
      if (fetchOriginal) {
        window.fetch = function () {
          noter(arguments[0]);
          return fetchOriginal.apply(this, arguments).then(function (r) {
            try { r.clone().text().then(analyser).catch(function () {}); } catch (e) {}
            return r;
          });
        };
      }
      var ouvrir = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (m, u) { noter(u); return ouvrir.apply(this, arguments); };
      var envoi = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function () {
        this.addEventListener('load', function () {
          try { if (this.responseType === '' || this.responseType === 'text') analyser(this.responseText); } catch (e) {}
        });
        return envoi.apply(this, arguments);
      };
      function analyserPage() {
        document.querySelectorAll('script').forEach(function (s) { analyser(s.textContent); });
      }
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
      function decrire(v) {
        return { src: v.currentSrc || v.src || '', page: location.href, lien: lienProche(v) };
      }
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
            if (src && src.indexOf('http') === 0 && !/rsrc\.php|static\.xx\.fbcdn|emoji/.test(src)) window.webkit.messageHandlers.elara.postMessage({ type: 'image', src: src });
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
        try { window.webkit.messageHandlers.elara.postMessage(decrire(v)); } catch (err) {}
      }, true);
    })();
    """#
}
#endif
