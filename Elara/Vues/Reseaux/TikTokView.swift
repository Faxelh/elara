#if PERSO
import SwiftUI
import WebKit

/// Navigateur TikTok intégré (version perso) : quand une vidéo joue, Elara propose de la télécharger.
@MainActor
@Observable
final class NavigateurTikTok: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let partage = NavigateurTikTok()
    static let accueil = URL(string: "https://www.tiktok.com/foryou")!
    private static let cleDernierePage = "tiktok.dernierePage"

    @ObservationIgnored let vue: WKWebView
    private(set) var peutReculer = false
    private(set) var chargement = false
    /// Lien du fichier de la vidéo en cours de lecture.
    var video: String?
    /// Vidéo ouverte depuis un lien collé : son fichier, à télécharger tout de suite.
    var aTelecharger: String?
    @ObservationIgnored private var attenteLien = false
    @ObservationIgnored private var ignorees: Set<String> = []
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        // Lecture automatique AVEC le son (sinon iOS impose des vidéos muettes).
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let controleur = WKUserContentController()
        controleur.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controleur.addUserScript(AntiApp.userScript)
        configuration.userContentController = controleur
        vue = WKWebView(frame: .zero, configuration: configuration)
        vue.customUserAgent = ExtracteurFacebook.agentMobile
        vue.scrollView.bounces = false
        super.init()
        controleur.add(self, name: "elaraTikTok")
        vue.navigationDelegate = self
        observation = vue.observe(\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.majBoutons() }
        }
        // Toujours sur « Pour toi » : une page vidéo seule (lien /video/) bloque le défilement
        // et ramène sans cesse à la même vidéo.
        let depart = Self.accueil
        vue.load(URLRequest(url: depart))
    }

    func reculer() { vue.goBack() }
    func recharger() { vue.reload() }
    func allerAccueil() { vue.load(URLRequest(url: Self.accueil)) }

    /// Premier lien TikTok trouvé dans un texte (lien copié depuis l'app TikTok : « Partager → Copier le lien »).
    static func lienTikTok(dans texte: String) -> URL? {
        let detecteur = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let plage = NSRange(texte.startIndex..., in: texte)
        for r in detecteur?.matches(in: texte, range: plage) ?? [] {
            if let url = r.url, let hote = url.host?.lowercased(), hote == "tiktok.com" || hote.hasSuffix(".tiktok.com") {
                return url
            }
        }
        return nil
    }

    /// Ouvre la vidéo du lien ; dès qu'elle joue, elle est téléchargée.
    func ouvrirLien(_ url: URL) {
        video = nil
        aTelecharger = nil
        attenteLien = true
        vue.load(URLRequest(url: url))
    }

    func fermerBandeau() {
        if let video { ignorees.insert(video) }
        video = nil
    }

    func marquerTelechargee(_ lien: String) { ignorees.insert(lien) }

    /// Cookies TikTok du navigateur (nécessaires pour télécharger le fichier).
    func cookies() async -> String {
        let tous = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        return tous.filter { $0.domain.contains("tiktok") }.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    /// Fichier de la vidéo affichée (celle qui joue, sinon la plus visible).
    func lienVideoVisible() async -> String? {
        let js = "window.__elaraTikTok ? window.__elaraTikTok() : ''"
        let resultat = await withCheckedContinuation { (suite: CheckedContinuation<String?, Never>) in
            vue.evaluateJavaScript(js) { r, _ in suite.resume(returning: r as? String) }
        }
        return (resultat?.isEmpty == false) ? resultat : nil
    }

    private func majBoutons() {
        peutReculer = vue.canGoBack
        if let url = vue.url, url.host?.contains("tiktok.com") == true {
            UserDefaults.standard.set(url.absoluteString, forKey: Self.cleDernierePage)
        }
    }

    func userContentController(_ controleur: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let src = message.body as? String, src.hasPrefix("https://"), !ignorees.contains(src) else { return }
        if attenteLien {
            attenteLien = false
            aTelecharger = src
            return
        }
        video = src
    }

    /// Liens « Ouvrir l'application » / App Store : on reste dans Elara.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        AntiApp.bloque(navigationAction.request.url) ? .cancel : .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { chargement = true }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { chargement = false; majBoutons() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { chargement = false }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { chargement = false }

    /// Repère la vidéo qui joue et retient les adresses des fichiers vidéo reçus par la page.
    static let script = #"""
    (function () {
      if (window.__elaraTT) return;
      window.__elaraTT = true;
      var vus = [];
      function noter(u) {
        try {
          if (u && typeof u === 'object' && u.url) u = u.url;
          if (typeof u !== 'string' || u.indexOf('http') !== 0) return;
          if (u.indexOf('/video/tos/') < 0 && u.indexOf('mime_type=video') < 0) return;
          vus.push(u); if (vus.length > 20) vus.shift();
        } catch (e) {}
      }
      var f = window.fetch;
      if (f) window.fetch = function () { noter(arguments[0]); return f.apply(this, arguments); };
      var ouvrir = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (m, u) { noter(u); return ouvrir.apply(this, arguments); };
      function source(v) {
        var s = v.currentSrc || v.src || '';
        if (s.indexOf('https://') !== 0) {
          var el = v.querySelector('source');
          if (el && el.src && el.src.indexOf('https://') === 0) s = el.src;
        }
        if (s.indexOf('https://') !== 0) s = vus.length ? vus[vus.length - 1] : '';
        return s;
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
      // Au premier toucher (geste de l'utilisateur), on remet aussi le son de la vidéo affichée.
      document.addEventListener('touchend', function () {
        document.querySelectorAll('video').forEach(function (v) {
          if (!v.paused && v.muted) { v.muted = false; v.volume = 1; }
        });
      }, true);
      document.addEventListener('play', function (e) {
        var v = e.target;
        if (!v || v.tagName !== 'VIDEO') return;
        // TikTok coupe le son des vidéos lues automatiquement : on le remet.
        if (v.muted) { v.muted = false; v.volume = 1; }
        setTimeout(function () {
          try { window.webkit.messageHandlers.elaraTikTok.postMessage(source(v)); } catch (err) {}
        }, 300);
      }, true);
    })();
    """#
}

struct TikTokView: View {
    @Environment(Bibliotheque.self) private var bib
    @State private var navigateur = NavigateurTikTok.partage
    @State private var telechargeur = Telechargeur()
    @State private var ajoute: Media?
    @State private var erreur: String?
    @State private var lienCopie = false
    @Environment(\.scenePhase) private var phase
    @AppStorage("tiktok.pressePapiersVu") private var pressePapiersVu = 0

    var body: some View {
        NavigationStack {
            PageTikTok(vue: navigateur.vue)
                .background(Color.black)
                .overlay(alignment: .top) {
                    if navigateur.chargement { ProgressView().progressViewStyle(.linear).tint(.pink) }
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
                        // Coller un lien TikTok (copié dans l'app TikTok : Partager → Copier le lien).
                        PasteButton(payloadType: String.self) { textes in
                            Task { @MainActor in coller(textes) }
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.circle)
                        .tint(Theme.accent)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Télécharger la vidéo affichée", systemImage: "arrow.down.circle") {
                                Task { await telecharger(nil) }
                            }
                            Button("Recharger", systemImage: "arrow.clockwise") { navigateur.recharger() }
                            Button("Pour toi", systemImage: "house") { navigateur.allerAccueil() }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .onChange(of: navigateur.video) { _, nouvelle in
                    if nouvelle != nil, !telechargeur.enCours { withAnimation { ajoute = nil; erreur = nil } }
                }
                .onChange(of: navigateur.aTelecharger) { _, lien in
                    guard let lien else { return }
                    navigateur.aTelecharger = nil
                    Task { await telecharger(lien) }
                }
                .onAppear { verifierPressePapiers() }
                .onChange(of: phase) { _, p in if p == .active { verifierPressePapiers() } }
        }
    }

    /// Un lien vient d'être copié ? (sans lire son contenu : pas de demande d'autorisation iOS)
    private func verifierPressePapiers() {
        let pp = UIPasteboard.general
        guard pp.changeCount != pressePapiersVu, pp.hasURLs || pp.hasStrings else { return }
        withAnimation { lienCopie = true }
    }

    private func coller(_ textes: [String]) {
        pressePapiersVu = UIPasteboard.general.changeCount
        withAnimation { lienCopie = false }
        guard let url = textes.lazy.compactMap({ NavigateurTikTok.lienTikTok(dans: $0) }).first else {
            withAnimation { erreur = String(localized: "Ce n'est pas un lien TikTok. Dans TikTok : Partager → Copier le lien.") }
            return
        }
        erreur = nil
        ajoute = nil
        navigateur.ouvrirLien(url)
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
        } else if lienCopie {
            carte {
                Image(systemName: "link").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lien copié").font(.subheadline.bold())
                    Text("Coller pour télécharger la vidéo TikTok").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                PasteButton(payloadType: String.self) { textes in
                    Task { @MainActor in coller(textes) }
                }
                .labelStyle(.titleOnly)
                .buttonBorderShape(.capsule)
                .tint(Theme.accent)
                fermer {
                    pressePapiersVu = UIPasteboard.general.changeCount
                    lienCopie = false
                }
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

    private func telecharger(_ lien: String?) async {
        erreur = nil
        ajoute = nil
        navigateur.video = nil
        var cible = lien
        if cible == nil { cible = await navigateur.lienVideoVisible() }
        guard let texte = cible, let url = URL(string: texte) else {
            withAnimation { erreur = String(localized: "Lancez d'abord la lecture de la vidéo, puis touchez Télécharger.") }
            return
        }
        let cookies = await navigateur.cookies()
        if let media = await telechargeur.telechargerTikTok(url, cookies: cookies, vers: bib, prive: false) {
            navigateur.marquerTelechargee(texte)
            withAnimation { ajoute = media }
            try? await Task.sleep(for: .seconds(2.5))
            if ajoute?.id == media.id { withAnimation { ajoute = nil } }
        } else if let message = telechargeur.erreur {
            withAnimation { erreur = message }
        }
    }
}

private struct PageTikTok: UIViewRepresentable {
    let vue: WKWebView
    func makeUIView(context: Context) -> WKWebView { vue }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
