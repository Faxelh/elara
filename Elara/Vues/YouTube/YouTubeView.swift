#if PERSO
import SwiftUI
import WebKit

/// Onglet YouTube (version perso) : on regarde YouTube dans Elara. Pas de téléchargement.
@MainActor
@Observable
final class NavigateurYouTube: NSObject, WKNavigationDelegate {
    static let partage = NavigateurYouTube()
    static let accueil = URL(string: "https://m.youtube.com/")!
    private static let cleDernierePage = "youtube.dernierePage"

    @ObservationIgnored let vue: WKWebView
    private(set) var peutReculer = false
    private(set) var peutAvancer = false
    private(set) var chargement = false
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        vue = WKWebView(frame: .zero, configuration: configuration)
        vue.allowsBackForwardNavigationGestures = true
        super.init()
        vue.navigationDelegate = self
        observation = vue.observe(\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.majBoutons() }
        }
        var depart = Self.accueil
        if let texte = UserDefaults.standard.string(forKey: Self.cleDernierePage),
           let url = URL(string: texte), url.host?.contains("youtube.com") == true {
            depart = url
        }
        vue.load(URLRequest(url: depart))
    }

    func reculer() { vue.goBack() }
    func avancer() { vue.goForward() }
    func recharger() { vue.reload() }
    func allerAccueil() { vue.load(URLRequest(url: Self.accueil)) }

    private func majBoutons() {
        peutReculer = vue.canGoBack
        peutAvancer = vue.canGoForward
        if let url = vue.url, url.host?.contains("youtube.com") == true {
            UserDefaults.standard.set(url.absoluteString, forKey: Self.cleDernierePage)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        chargement = true
        majBoutons()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        chargement = false
        majBoutons()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        chargement = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        chargement = false
    }
}

struct YouTubeView: View {
    @State private var navigateur = NavigateurYouTube.partage

    var body: some View {
        NavigationStack {
            PageYouTube(vue: navigateur.vue)
                .overlay(alignment: .top) {
                    if navigateur.chargement {
                        ProgressView().progressViewStyle(.linear).tint(.red)
                    }
                }
                .navigationTitle("YouTube")
                .toolbar { ToolbarItem(placement: .principal) { SelecteurReseau() } }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button { navigateur.reculer() } label: { Image(systemName: "chevron.backward") }
                            .disabled(!navigateur.peutReculer)
                            .accessibilityLabel("Page précédente")
                        Button { navigateur.avancer() } label: { Image(systemName: "chevron.forward") }
                            .disabled(!navigateur.peutAvancer)
                            .accessibilityLabel("Page suivante")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { navigateur.allerAccueil() } label: { Image(systemName: "house") }
                            .accessibilityLabel("Accueil YouTube")
                        Button { navigateur.recharger() } label: { Image(systemName: "arrow.clockwise") }
                            .accessibilityLabel("Recharger")
                    }
                }
        }
    }
}

private struct PageYouTube: UIViewRepresentable {
    let vue: WKWebView
    func makeUIView(context: Context) -> WKWebView { vue }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
