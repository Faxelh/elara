import SwiftUI
import AVFoundation

@main
struct ElaraApp: App {
    @State private var bibliotheque: Bibliotheque
    @State private var lecteur: LecteurController
    @State private var coffre = Coffre()

    init() {
        UserDefaults.standard.register(defaults: [
            Cle.reprendreLecture: true,
            Cle.modeLectureAuto: ModeLectureAuto.arreter.rawValue,
            Cle.pauseArrierePlan: false,
            Cle.imageDansImage: true,
            Cle.rotationPaysage: false,
            Cle.airplay: true,
            Cle.gesteLuminosite: true,
            Cle.gesteVolume: true,
            Cle.verrouApp: false
        ])
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        let langue = LangueApp.actuelle
        Langue.activer(langue == .systeme ? nil : langue.rawValue)

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
    @Environment(Bibliotheque.self) private var bib
    @Environment(LecteurController.self) private var lecteur
    @Environment(Coffre.self) private var coffre
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Cle.theme) private var theme: ThemeApp = .systeme
    @AppStorage(Cle.verrouApp) private var verrouApp = false
    /// Change dès qu'une langue est choisie : les onglets sont alors redessinés dans la nouvelle langue.
    @AppStorage("langueChoisie") private var langueChoisie = "systeme"
    @State private var onglet = 0
    @State private var lienPartage: LienPartage?
    @State private var verrouOuverture = Coffre()
    @State private var demandeEnCours = false

    private var schema: ColorScheme? {
        switch theme {
        case .systeme: nil
        case .clair: .light
        case .sombre: .dark
        }
    }

    private var appVerrouillee: Bool { verrouApp && !verrouOuverture.estDeverrouille }

    var body: some View {
        @Bindable var lecteur = lecteur
        TabView(selection: $onglet) {
            AccueilView()
                .tabItem { Label("Accueil", systemImage: "house.fill") }
                .tag(0)
            TransfertView()
                .tabItem { Label("Transfert", systemImage: "arrow.up.arrow.down.circle.fill") }
                .tag(1)
            CompresserView()
                .tabItem { Label("Compresser", systemImage: "rectangle.compress.vertical") }
                .tag(2)
            ReglagesView()
                .tabItem { Label("Réglages", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .id(langueChoisie)
        .environment(\.locale, Langue.locale)
        .onOpenURL { url in
            Task { await ouvrir(url) }
        }
        .sheet(item: $lienPartage) { partage in
            TelechargerView(lienInitial: partage.lien, demarrerSeul: true)
        }
        .fullScreenCover(isPresented: $lecteur.estAffiche) {
            LecteurView()
        }
        .overlay {
            if appVerrouillee {
                EcranVerrouApp(verrou: verrouOuverture) { await deverrouillerApp() }
            } else if coffre.estDeverrouille && scenePhase != .active {
                // Cache le contenu privé dans le sélecteur d'apps
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                }
                .ignoresSafeArea()
            }
        }
        .preferredColorScheme(schema)
        .task { if appVerrouillee { await deverrouillerApp() } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { lecteur.sauverPosition() }
            if phase == .background {
                coffre.verrouiller()
                verrouOuverture.verrouiller()
                if lecteur.mediaActuel?.estPrive == true {
                    lecteur.fermer()
                } else if Cle.booleen(Cle.pauseArrierePlan, defaut: false) {
                    lecteur.player.pause()
                }
            }
            if phase == .active && appVerrouillee {
                Task { await deverrouillerApp() }
            }
        }
    }

    /// Fichier ouvert avec « Ouvrir dans Elara » / « Copier dans Elara »,
    /// ou lien elara://telecharger?lien=… (raccourci « Partager vers Elara »).
    private func ouvrir(_ url: URL) async {
        if url.isFileURL {
            onglet = 0
            // Les fichiers reçus d'une autre app arrivent dans Documents/Inbox : on les déplace.
            let boiteReception = url.path.contains("/Documents/Inbox/")
            bib.importEnCours = true
            _ = await bib.importer(depuis: url, deplacer: boiteReception)
            bib.importEnCours = false
            return
        }
        guard url.scheme?.lowercased() == "elara",
              let composants = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let lien = composants.queryItems?.first { $0.name == "lien" || $0.name == "url" }?.value ?? ""
        guard !lien.isEmpty else { return }
        onglet = 0
        lienPartage = LienPartage(lien: lien)
    }

    private func deverrouillerApp() async {
        guard !demandeEnCours else { return }
        demandeEnCours = true
        await verrouOuverture.deverrouiller(raison: String(localized: "Déverrouiller Elara"))
        demandeEnCours = false
    }
}

struct LienPartage: Identifiable {
    let id = UUID()
    let lien: String
}

/// Écran affiché quand « Verrouiller Elara » est activé dans les Réglages.
struct EcranVerrouApp: View {
    let verrou: Coffre
    let deverrouiller: () async -> Void

    var body: some View {
        ZStack {
            Theme.degrade.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white)
                Text("Elara est verrouillée")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Button {
                    Task { await deverrouiller() }
                } label: {
                    Label("Déverrouiller avec \(verrou.nomBiometrie)", systemImage: "faceid")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Theme.accent)
                if let erreur = verrou.erreur {
                    Text(erreur)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
    }
}
