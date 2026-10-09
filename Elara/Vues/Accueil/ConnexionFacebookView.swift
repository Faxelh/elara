#if PERSO
import SwiftUI
import WebKit

/// Connexion à Facebook dans Elara (version perso), pour télécharger
/// les vidéos visibles seulement quand on est connecté.
/// L'utilisateur saisit lui-même ses identifiants sur la page de Facebook.
struct ConnexionFacebookView: View {
    @State private var deconnecte = false

    var body: some View {
        PageFacebook(url: URL(string: "https://m.facebook.com/login")!, recharger: deconnecte)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Facebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Se déconnecter", role: .destructive) {
                        Task {
                            await ExtracteurFacebook.deconnecter()
                            deconnecte.toggle()
                        }
                    }
                }
            }
    }
}

private struct PageFacebook: UIViewRepresentable {
    let url: URL
    let recharger: Bool

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let vue = WKWebView(frame: .zero, configuration: configuration)
        vue.customUserAgent = ExtracteurFacebook.agentMobile
        vue.allowsBackForwardNavigationGestures = true
        vue.load(URLRequest(url: url))
        context.coordinator.dernier = recharger
        return vue
    }

    func updateUIView(_ vue: WKWebView, context: Context) {
        if context.coordinator.dernier != recharger {
            context.coordinator.dernier = recharger
            vue.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinateur { Coordinateur() }

    final class Coordinateur {
        var dernier = false
    }
}
#endif
