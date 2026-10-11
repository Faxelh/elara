#if PERSO
import SwiftUI

/// Onglet « Réseaux » : Facebook, TikTok et YouTube au même endroit.
enum Reseau: String, CaseIterable, Identifiable {
    case facebook, tiktok, youtube
    var id: String { rawValue }
    var titre: String {
        switch self {
        case .facebook: "Facebook"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        }
    }
}

struct ReseauxView: View {
    @AppStorage("reseau") private var reseau: Reseau = .facebook

    var body: some View {
        switch reseau {
        case .facebook: FacebookView()
        case .tiktok: TikTokView()
        case .youtube: YouTubeView()
        }
    }
}

/// Choix Facebook / TikTok / YouTube, affiché en haut de chaque réseau.
struct SelecteurReseau: View {
    @AppStorage("reseau") private var reseau: Reseau = .facebook

    var body: some View {
        Picker("Réseau", selection: $reseau) {
            ForEach(Reseau.allCases) { Text($0.titre).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
    }
}
#endif
