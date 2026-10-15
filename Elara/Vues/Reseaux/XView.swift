#if PERSO
import SwiftUI
import WebKit

/// Vidéo repérée dans X : le numéro du post (le plus fiable) et le fichier vu passer pendant la lecture.
struct LectureX: Equatable {
    var numero: String?
    var fichier: String?
    var cle: String { numero ?? fichier ?? "" }
}

/// Navigateur X (Twitter) intégré (version perso) : quand une vidéo joue, Elara propose de la télécharger.
@MainActor
@Observable
final class NavigateurX: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let partage = NavigateurX()
    static let accueil = URL(string: "https://x.com/home")!

    @ObservationIgnored let vue: WKWebView
    private(set) var peutReculer = false
    private(set) var chargement = false
    /// Vidéo en cours de lecture.
    var video: LectureX?
    @ObservationIgnored private var ignorees: Set<String> = []

    private override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let controleur = WKUserContentController()
        controleur.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        AntiApp.installer(controleur)
        configuration.userContentController = controleur
        vue = WKWebView(frame: .zero, configuration: configuration)
        vue.customUserAgent = ExtracteurFacebook.agentMobile
        vue.allowsBackForwardNavigationGestures = true
        super.init()
        controleur.add(self, name: "elaraX")
        vue.navigationDelegate = self
        vue.load(URLRequest(url: Self.accueil))
    }

    func reculer() { vue.goBack() }
    func recharger() { vue.reload() }
    func allerAccueil() { vue.load(URLRequest(url: Self.accueil)) }

    func fermerBandeau() {
        if let video { ignorees.insert(video.cle) }
        video = nil
    }

    func marquerTelechargee(_ lecture: LectureX) { ignorees.insert(lecture.cle) }

    /// Vidéo affichée (celle qui joue, sinon la plus visible), ou le post ouvert.
    func lectureVisible() async -> LectureX? {
        let js = "JSON.stringify(window.__elaraX ? window.__elaraX() : {})"
        let texte = await withCheckedContinuation { (suite: CheckedContinuation<String?, Never>) in
            vue.evaluateJavaScript(js) { r, _ in suite.resume(returning: r as? String) }
        }
        var lecture = Self.decoder(texte)
        if lecture?.numero == nil, let page = vue.url?.absoluteString, let n = Telechargeur.numeroX(page) {
            lecture = LectureX(numero: n, fichier: lecture?.fichier)
        }
        return lecture
    }

    private static func decoder(_ texte: String?) -> LectureX? {
        guard let texte, let objet = try? JSONSerialization.jsonObject(with: Data(texte.utf8)) as? [String: Any] else { return nil }
        let numero = (objet["numero"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let fichier = (objet["fichier"] as? String).flatMap { $0.hasPrefix("https://") ? $0 : nil }
        return numero == nil && fichier == nil ? nil : LectureX(numero: numero, fichier: fichier)
    }

    func userContentController(_ controleur: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let texte = message.body as? String, let lecture = Self.decoder(texte), !ignorees.contains(lecture.cle) else { return }
        video = lecture
    }

    /// Liens « Ouvrir l'application » / App Store : on reste dans Elara.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        AntiApp.bloque(navigationAction.request.url) ? .cancel : .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { chargement = true }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { chargement = false; peutReculer = vue.canGoBack }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { peutReculer = vue.canGoBack }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { chargement = false }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { chargement = false }

    /// Repère la vidéo qui joue, le numéro de son post, et les fichiers mp4 reçus par la page.
    static let script = #"""
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
    setTimeout(function () { try { window.webkit.messageHandlers.elaraX.postMessage(decrire(v)); } catch (err) {} }, 300);
  }, true);
})();
"""#
}

struct XView: View {
    @Environment(Bibliotheque.self) private var bib
    @State private var navigateur = NavigateurX.partage
    @State private var telechargeur = Telechargeur()
    @State private var ajoute: Media?
    @State private var erreur: String?

    var body: some View {
        NavigationStack {
            PageX(vue: navigateur.vue)
                .background(Color.black)
                .overlay(alignment: .top) {
                    if navigateur.chargement { ProgressView().progressViewStyle(.linear).tint(.blue) }
                }
                .overlay(alignment: .bottom) { bandeau }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { navigateur.reculer() } label: { Image(systemName: "chevron.backward") }
                            .disabled(!navigateur.peutReculer)
                            .accessibilityLabel("Page précédente")
                    }
                    ToolbarItem(placement: .principal) { SelecteurReseau() }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Télécharger la vidéo affichée", systemImage: "arrow.down.circle") {
                                Task { await telecharger(nil) }
                            }
                            Button("Recharger", systemImage: "arrow.clockwise") { navigateur.recharger() }
                            Button("Accueil X", systemImage: "house") { navigateur.allerAccueil() }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .onChange(of: navigateur.video) { _, nouvelle in
                    if nouvelle != nil, !telechargeur.enCours { withAnimation { ajoute = nil; erreur = nil } }
                }
        }
    }

    @ViewBuilder
    private var bandeau: some View {
        if telechargeur.enCours {
            carte {
                ProgressView(value: telechargeur.progression).frame(width: 28)
                Text("Téléchargement…").font(.subheadline.bold())
                Spacer(minLength: 4)
                Button("Annuler", role: .destructive) { telechargeur.annuler() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        } else if let erreur {
            carte {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(erreur).font(.footnote)
                Spacer(minLength: 4)
                fermer { self.erreur = nil }
            }
        } else if let ajoute {
            carte {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bib.estDoublonSignale(ajoute) ? LocalizedStringKey("Déjà dans Elara") : LocalizedStringKey("Vidéo ajoutée à Elara"))
                        .font(.subheadline.bold())
                    Text(ajoute.nom).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                fermer { self.ajoute = nil }
            }
        } else if let video = navigateur.video {
            carte {
                Image(systemName: "play.rectangle.fill").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vidéo en cours de lecture").font(.subheadline.bold())
                    Text("La télécharger dans Elara ?").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button("Télécharger") { Task { await telecharger(video) } }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                fermer { navigateur.fermerBandeau() }
            }
        }
    }

    private func carte<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        HStack(spacing: 12) { contenu() }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func fermer(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.subheadline.bold())
                .frame(width: 30, height: 30)
                .background(Color.secondary.opacity(0.18), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Fermer")
    }

    private func telecharger(_ lecture: LectureX?) async {
        erreur = nil
        ajoute = nil
        navigateur.video = nil
        var cible = lecture
        if cible == nil { cible = await navigateur.lectureVisible() }
        guard let cible else {
            withAnimation { erreur = String(localized: "Ouvrez le post et lancez la vidéo, puis touchez Télécharger.") }
            return
        }
        if let media = await telechargeur.telechargerX(numero: cible.numero, secours: cible.fichier.flatMap(URL.init(string:)),
                                                       vers: bib, prive: false) {
            navigateur.marquerTelechargee(cible)
            withAnimation { ajoute = media }
            try? await Task.sleep(for: .seconds(2.5))
            if ajoute?.id == media.id { withAnimation { ajoute = nil } }
        } else if let message = telechargeur.erreur {
            withAnimation { erreur = message }
        }
    }
}

private struct PageX: UIViewRepresentable {
    let vue: WKWebView
    func makeUIView(context: Context) -> WKWebView { vue }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
