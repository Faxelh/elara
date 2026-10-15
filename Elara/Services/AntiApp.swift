import Foundation
import WebKit
import UIKit

/// Bloque les invitations « Ouvrir l'application » de Facebook, TikTok et YouTube :
/// la fenêtre est fermée (« Pas maintenant ») ou cachée, et les liens vers l'app ou l'App Store restent sans effet.
enum AntiApp {
    static var userScript: WKUserScript {
        WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    /// Installe le script dans une page : blocage « Ouvrir l'application » + écran allumé pendant les vidéos.
    @MainActor
    static func installer(_ controleur: WKUserContentController) {
        controleur.addUserScript(userScript)
        controleur.removeScriptMessageHandler(forName: "elaraEveil")
        controleur.add(GardeEveil.partage, name: "elaraEveil")
    }

    /// Vrai si la navigation mène hors d'Elara (app TikTok/Facebook/YouTube, App Store, Play Store…).
    static func bloque(_ url: URL?) -> Bool {
        guard let url else { return false }
        let schema = url.scheme?.lowercased() ?? ""
        if !["http", "https", "about", "data", "blob"].contains(schema) { return true }
        let hote = url.host?.lowercased() ?? ""
        return ["apps.apple.com", "itunes.apple.com", "play.google.com"].contains { hote == $0 || hote.hasSuffix("." + $0) }
    }

    static let script = #"""
(function () {
  if (window.__elaraAntiApp) return;
  window.__elaraAntiApp = true;
  var VERBE = '(ouvrir|open|utiliser|use|continuer dans|continue in|voir dans|watch in|regarder dans|obtenir|get|télécharger|download|installer|install|passer à|switch to|essayer|try)';
  var CIBLE = "(l['’] ?app|l['’]appli|l['’]application|the app|app|tiktok|youtube|facebook)";
  var PROMO = new RegExp(VERBE + '\\s+' + CIBLE, 'i');
  var REFUS = ['pas maintenant', 'not now', 'plus tard', 'maybe later', 'non merci', 'no thanks', 'no, thanks',
    'continuer dans le navigateur', 'continue in browser', 'rester sur le navigateur', 'continuer sur le web',
    'continue on web', 'stay on web', 'continuer avec le navigateur', 'fermer', 'close', 'ignorer', 'dismiss',
    'ne pas ouvrir', 'continuer sur le site'];
  var LIEN_APP = /^(intent|snssdk\d*|tiktok|twitter|fb|fb-messenger|youtube|vnd\.youtube|itms-apps|itms-appss|market):|apps\.apple\.com|itunes\.apple\.com|play\.google\.com\/store|app\.adjust\.|onelink\.me|app\.link/i;

  var style = document.createElement('style');
  style.textContent = 'ytm-mealbar-promo-renderer, ytm-app-promo-renderer, ytm-upsell-dialog-renderer { display: none !important; }';
  function ajouterStyle() {
    var cible = document.head || document.documentElement;
    if (cible && !style.parentNode) cible.appendChild(style);
  }

  function texte(el) {
    var t = (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim();
    if (!t) t = (el.getAttribute('aria-label') || el.getAttribute('title') || '').trim();
    return t;
  }
  function estRefus(el) {
    var t = texte(el).toLowerCase();
    return t.length > 0 && t.length < 40 && REFUS.indexOf(t) !== -1;
  }
  function estPromo(el) {
    var lien = el.getAttribute && el.getAttribute('href');
    if (lien && LIEN_APP.test(lien)) return true;
    var t = texte(el);
    return t.length > 0 && t.length < 60 && PROMO.test(t);
  }
  function conteneurFixe(el) {
    var n = el.parentElement;
    while (n && n !== document.body && n !== document.documentElement) {
      var p = getComputedStyle(n).position;
      if (p === 'fixed' || p === 'sticky') return n;
      n = n.parentElement;
    }
    return null;
  }
  function cacher(el) {
    el.style.setProperty('display', 'none', 'important');
    el.setAttribute('data-elara-cache', '1');
  }
  function debloquerDefilement() {
    [document.documentElement, document.body].forEach(function (n) {
      if (n && getComputedStyle(n).overflow === 'hidden') n.style.setProperty('overflow', 'auto', 'important');
    });
  }

  // Les sites utilisent souvent des <div> cliquables : on cherche donc les TEXTES, pas seulement les boutons.
  function textesCourts(racine, test) {
    var res = [];
    if (!racine) return res;
    var w = document.createTreeWalker(racine, NodeFilter.SHOW_TEXT);
    var n;
    while ((n = w.nextNode())) {
      var t = n.nodeValue;
      if (!t || t.length > 80) continue;
      t = t.replace(/\s+/g, ' ').trim();
      if (t && n.parentElement && test(t)) res.push(n.parentElement);
    }
    return res;
  }
  function cliquable(el) {
    return (el.closest && el.closest('button, a, [role="button"], [role="link"]')) || el;
  }
  function boutonRefus(el) {
    // On remonte depuis « Ouvrir l'application » jusqu'à la fenêtre qui contient « Pas maintenant » / la croix.
    var n = el.parentElement;
    for (var niveau = 0; n && niveau < 10 && n !== document.body; niveau++, n = n.parentElement) {
      if (texte(n).length > 500 || n.querySelector('video')) return null;
      var refus = textesCourts(n, function (t) { return REFUS.indexOf(t.toLowerCase()) !== -1; });
      if (refus.length) return { bouton: cliquable(refus[0]), boite: n };
      var croix = n.querySelector('[aria-label="Fermer"], [aria-label="Close"], [aria-label="fermer"], [aria-label="close"], [data-e2e*="close"], [class*="close" i]');
      if (croix) return { bouton: cliquable(croix), boite: n };
    }
    return null;
  }

  // Pour rester fluide : on n'analyse que les morceaux de page qui viennent d'apparaître,
  // en petites tranches pendant les temps morts du navigateur (pas de gel pendant le défilement).
  var aAnalyser = [];
  var toutAnalyser = true;

  function nettoyer() {
    ajouterStyle();
    var racines = toutAnalyser ? [document.body] : aAnalyser.splice(0, 40);
    toutAnalyser = false;
    var promos = [];
    for (var r0 = 0; r0 < racines.length; r0++) {
      var racine = racines[r0];
      if (!racine || !racine.isConnected) continue;
      if (racine.nodeType === 3) racine = racine.parentElement;
      if (!racine || racine.nodeType !== 1) continue;
      promos = promos.concat(textesCourts(racine, function (t) { return t.length < 60 && PROMO.test(t); }));
      if (racine.matches && racine.matches('a[href]') && LIEN_APP.test(racine.getAttribute('href'))) promos.push(racine);
      var liens = racine.querySelectorAll ? racine.querySelectorAll('a[href]') : [];
      for (var k = 0; k < liens.length; k++) { if (LIEN_APP.test(liens[k].getAttribute('href'))) promos.push(liens[k]); }
    }
    for (var i = 0; i < promos.length; i++) {
      var el = cliquable(promos[i]);
      if (el.__elaraVu || el.getAttribute('data-elara-cache')) continue;
      el.__elaraVu = true;
      var refus = boutonRefus(el);
      if (refus) {
        // Fenêtre « Ouvrir l'application » : on touche « Pas maintenant » (ou la croix).
        try { refus.bouton.click(); } catch (e) {}
        (function (boite, bouton) {
          setTimeout(function () {
            // Si la fenêtre est toujours là, on la cache.
            if (boite.isConnected && boite.getBoundingClientRect().height > 0 && !boite.querySelector('video')) cacher(boite);
            debloquerDefilement();
          }, 700);
        })(refus.boite, el);
        continue;
      }
      var dialogue = el.closest('[role="dialog"], [aria-modal="true"]');
      if (dialogue && texte(dialogue).length < 300 && !dialogue.querySelector('video')) { cacher(dialogue); debloquerDefilement(); continue; }
      // Sinon on ne cache que le bouton lui-même : la page (vidéos, menu, recherche) reste intacte.
      // Jamais un élément qui contient une vidéo ou qui couvre une grande partie de l'écran.
      if (el.querySelector('video, img, canvas')) continue;
      var r = el.getBoundingClientRect();
      if (r.width * r.height > innerWidth * innerHeight * 0.15) continue;
      cacher(el);
    }
  }

  // Écran allumé tant qu'une vidéo (Reel, post…) est en lecture.
  var eveil = null;
  function majEveil() {
    var lecture = false;
    document.querySelectorAll('video').forEach(function (v) { if (!v.paused && !v.ended) lecture = true; });
    if (lecture === eveil) return;
    eveil = lecture;
    try { window.webkit.messageHandlers.elaraEveil.postMessage(lecture); } catch (e) {}
    try { ElaraEveil.etat(lecture); } catch (e) {}
  }
  ['play', 'playing', 'pause', 'ended', 'emptied'].forEach(function (t) {
    document.addEventListener(t, function () { setTimeout(majEveil, 50); }, true);
  });
  window.addEventListener('pagehide', function () { eveil = null; try { window.webkit.messageHandlers.elaraEveil.postMessage(false); } catch (e) {} try { ElaraEveil.etat(false); } catch (e) {} });

  // Les liens vers l'app ou le store ne quittent jamais Elara.
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a') : null;
    var lien = a && a.getAttribute('href');
    if (lien && LIEN_APP.test(lien)) { e.preventDefault(); e.stopPropagation(); }
  }, true);

  var prevu = null;
  var attente = window.requestIdleCallback || function (f) { return setTimeout(f, 1); };
  function planifier() {
    if (prevu) return;
    prevu = setTimeout(function () {
      attente(function () {
        prevu = null;
        try { nettoyer(); } catch (e) {}
        if (aAnalyser.length) planifier();
      });
    }, 400);
  }
  new MutationObserver(function (liste) {
    for (var i = 0; i < liste.length; i++) {
      var ajoutes = liste[i].addedNodes;
      for (var j = 0; j < ajoutes.length; j++) {
        var n = ajoutes[j];
        if (n.nodeType === 1 || n.nodeType === 3) aAnalyser.push(n);
      }
    }
    if (aAnalyser.length > 400) { aAnalyser = []; toutAnalyser = true; }
    if (aAnalyser.length || toutAnalyser) planifier();
  }).observe(document.documentElement, { childList: true, subtree: true });
  document.addEventListener('DOMContentLoaded', function () { toutAnalyser = true; planifier(); });
  planifier();
})();
"""#
}

/// Garde l'écran allumé tant qu'une vidéo joue dans Facebook, X ou YouTube.
@MainActor
final class GardeEveil: NSObject, WKScriptMessageHandler {
    static let partage = GardeEveil()

    func userContentController(_ controleur: WKUserContentController, didReceive message: WKScriptMessage) {
        UIApplication.shared.isIdleTimerDisabled = (message.body as? Bool) ?? false
    }
}
