package com.kounandi.elara.ui.commun

import android.net.Uri

/**
 * Bloque les invitations « Ouvrir l'application » de Facebook, TikTok et YouTube :
 * la fenêtre est fermée (« Pas maintenant ») ou cachée, et les liens vers l'app ou le Play Store restent sans effet.
 */
object AntiApp {
    /** Vrai si la navigation mène hors d'Elara (app, intent://, Play Store, App Store…). */
    fun bloque(uri: Uri): Boolean {
        val schema = uri.scheme?.lowercase() ?: return true
        if (schema != "http" && schema != "https") return true
        val hote = uri.host?.lowercase() ?: return false
        return listOf("play.google.com", "apps.apple.com", "itunes.apple.com").any { hote == it || hote.endsWith(".$it") }
    }

    val SCRIPT = """
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
  var LIEN_APP = /^(intent|snssdk\d*|tiktok|fb|fb-messenger|youtube|vnd\.youtube|itms-apps|itms-appss|market):|apps\.apple\.com|itunes\.apple\.com|play\.google\.com\/store|app\.adjust\.|onelink\.me|app\.link/i;

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

  function nettoyer() {
    ajouterStyle();
    var elements = document.querySelectorAll('button, a, [role="button"], [role="link"]');
    for (var i = 0; i < elements.length; i++) {
      var el = elements[i];
      if (el.__elaraVu || !estPromo(el)) continue;
      el.__elaraVu = true;
      var boite = conteneurFixe(el);
      if (boite) {
        // Fenêtre « Ouvrir l'application » : on touche « Pas maintenant » / la croix si elle existe.
        var refus = null;
        var dedans = boite.querySelectorAll('button, a, [role="button"], div[aria-label], span[aria-label]');
        for (var j = 0; j < dedans.length; j++) { if (estRefus(dedans[j])) { refus = dedans[j]; break; } }
        if (refus) { try { refus.click(); } catch (e) {} setTimeout(debloquerDefilement, 300); continue; }
        // Vraie fenêtre (role="dialog") sans bouton de refus : on la cache, elle seule.
        var dialogue = el.closest('[role="dialog"], [aria-modal="true"]');
        if (dialogue && texte(dialogue).length < 300) { cacher(dialogue); debloquerDefilement(); continue; }
      }
      // Sinon on ne cache que le bouton lui-même : la page (vidéos, menu, recherche) reste intacte.
      // Jamais un élément qui contient une vidéo ou qui couvre une grande partie de l'écran.
      if (el.querySelector('video, img, canvas')) continue;
      var r = el.getBoundingClientRect();
      if (r.width * r.height > innerWidth * innerHeight * 0.15) continue;
      cacher(el);
    }
  }

  // Les liens vers l'app ou le store ne quittent jamais Elara.
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a') : null;
    var lien = a && a.getAttribute('href');
    if (lien && LIEN_APP.test(lien)) { e.preventDefault(); e.stopPropagation(); }
  }, true);

  var prevu = null;
  function planifier() {
    if (prevu) return;
    prevu = setTimeout(function () { prevu = null; try { nettoyer(); } catch (e) {} }, 250);
  }
  new MutationObserver(planifier).observe(document.documentElement, { childList: true, subtree: true });
  document.addEventListener('DOMContentLoaded', planifier);
  planifier();
})();
""".trimIndent()
}
