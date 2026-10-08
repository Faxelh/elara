import SwiftUI
import AVFoundation

@main
struct ElaraApp: App {
    @State private var bibliotheque: Bibliotheque
    @State private var lecteur: LecteurController
    @State private var coffre = Coffre()

    init() {
        UserDefaults.standard.register(defaults: [
            "reprendreLecture": true,
            "modeLectureAuto": ModeLectureAuto.arreter.rawValue
        ])
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)

        let bib = Bibliotheque()
        _bibliotheque = State(initialValue: bib)
        _lecteur = State(initialValue: LecteurController(bibliotheque: bib))
    }

    var body: some Scene {
        WindowGroup {
            RacineView()
                .environment(bibliotheque)
                .environment(lecteur)
                .environment(coffre)
                .tint(Theme.accent)
        }
    }
}

struct RacineView: View {
    @Environment(LecteurController.self) private var lecteur
    @Environment(Coffre.self) private var coffre
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var lecteur = lecteur
        TabView {
            AccueilView()
                .tabItem { Label("Accueil", systemImage: "house.fill") }
            TransfertView()
                .tabItem { Label("Transfert", systemImage: "arrow.up.arrow.down.circle.fill") }
            CompresserView()
                .tabItem { Label("Compresser", systemImage: "rectangle.compress.vertical") }
            ReglagesView()
                .tabItem { Label("Réglages", systemImage: "gearshape.fill") }
        }
        .fullScreenCover(isPresented: $lecteur.estAffiche) {
            LecteurView()
        }
        .overlay {
            // Cache le contenu privé dans le sélecteur d'apps
            if coffre.estDeverrouille && scenePhase != .active {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                }
                .ignoresSafeArea()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { lecteur.sauverPosition() }
            if phase == .background {
                coffre.verrouiller()
                if lecteur.mediaActuel?.estPrive == true { lecteur.fermer() }
            }
        }
    }
}
