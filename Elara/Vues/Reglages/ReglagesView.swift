import SwiftUI
import StoreKit

struct ReglagesView: View {
    @Environment(Bibliotheque.self) private var bib
    @Environment(\.requestReview) private var demanderAvis
    @State private var confirmerCache = false
    @State private var tailleCache: Int64 = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ReglagesGenerauxView()
                    } label: {
                        Label("Général", systemImage: "gearshape")
                    }
                    NavigationLink {
                        ReglagesLecteurView()
                    } label: {
                        Label("Lecteur", systemImage: "play.rectangle")
                    }
                    NavigationLink {
                        ReglagesGestesView()
                    } label: {
                        Label("Gestes", systemImage: "hand.draw")
                    }
                    NavigationLink {
                        ReglagesSecuriteView()
                    } label: {
                        Label("Code Face ID / Touch ID", systemImage: "faceid")
                    }
                }

                Section {
                    NavigationLink {
                        HistoriqueView()
                    } label: {
                        Label("Historique de lecture", systemImage: "clock.arrow.circlepath")
                    }
                    Button {
                        confirmerCache = true
                    } label: {
                        HStack {
                            Label("Vider le cache", systemImage: "trash")
                            Spacer()
                            Text(Format.taille(tailleCache)).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                Section {
                    Button {
                        demanderAvis()
                    } label: {
                        Label("Noter Elara", systemImage: "star")
                    }
                    .foregroundStyle(.primary)
                    NavigationLink {
                        AideView()
                    } label: {
                        Label("Aide", systemImage: "questionmark.circle")
                    }
                    NavigationLink {
                        AProposView()
                    } label: {
                        Label("À propos", systemImage: "info.circle")
                    }
                } footer: {
                    Text(InfosAppareil.resume())
                        .font(.footnote.monospacedDigit())
                        .padding(.top, 8)
                }
            }
            .navigationTitle("Réglages")
            .task { tailleCache = bib.tailleCache() }
            .confirmationDialog("Vider le cache ?", isPresented: $confirmerCache, titleVisibility: .visible) {
                Button("Vider", role: .destructive) {
                    bib.viderCache()
                    tailleCache = bib.tailleCache()
                }
            } message: {
                Text("Les fichiers temporaires seront supprimés. Vos médias ne sont pas touchés.")
            }
        }
    }
}

// MARK: - Général

enum LangueApp: String, CaseIterable, Identifiable {
    case systeme, fr, en, ru, es
    var id: String { rawValue }

    var titre: String {
        switch self {
        case .systeme: String(localized: "Langue du système")
        case .fr: "Français"
        case .en: "English"
        case .ru: "Русский"
        case .es: "Español"
        }
    }

    static var actuelle: LangueApp {
        guard let choix = UserDefaults.standard.string(forKey: "langueChoisie") else { return .systeme }
        return LangueApp(rawValue: choix) ?? .systeme
    }

    /// Change la langue tout de suite (et pour les prochains lancements).
    func appliquer() {
        let d = UserDefaults.standard
        if self == .systeme {
            d.removeObject(forKey: "AppleLanguages")
        } else {
            d.set([rawValue], forKey: "AppleLanguages")
        }
        Langue.activer(self == .systeme ? nil : rawValue)
        // Modifié en dernier : redessine l'app dans la nouvelle langue.
        if self == .systeme {
            d.removeObject(forKey: "langueChoisie")
        } else {
            d.set(rawValue, forKey: "langueChoisie")
        }
    }
}

struct ReglagesGenerauxView: View {
    @AppStorage(Cle.theme) private var theme: ThemeApp = .systeme
    @AppStorage(Cle.vueAccueil) private var vue: VueAccueil = .grille
    @State private var langue = LangueApp.actuelle

    var body: some View {
        Form {
            Section {
                Picker("Langue", selection: $langue) {
                    ForEach(LangueApp.allCases) { Text($0.titre).tag($0) }
                }
                .onChange(of: langue) { _, nouvelle in
                    nouvelle.appliquer()
                }
            }
            Section("Affichage") {
                Picker("Thème", selection: $theme) {
                    ForEach(ThemeApp.allCases) { Text($0.titre).tag($0) }
                }
                Picker("Vue de l'accueil", selection: $vue) {
                    ForEach(VueAccueil.allCases) { Text($0.titre).tag($0) }
                }
            }
        }
        .navigationTitle("Général")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Lecteur

struct ReglagesLecteurView: View {
    @AppStorage(Cle.modeLectureAuto) private var mode: ModeLectureAuto = .arreter
    @AppStorage(Cle.reprendreLecture) private var reprendre = true
    @AppStorage(Cle.pauseArrierePlan) private var pauseArrierePlan = false
    @AppStorage(Cle.imageDansImage) private var imageDansImage = true
    @AppStorage(Cle.rotationPaysage) private var rotationPaysage = false
    @AppStorage(Cle.airplay) private var airplay = true

    var body: some View {
        Form {
            Section {
                Picker("Lecture automatique", selection: $mode) {
                    ForEach(ModeLectureAuto.allCases) { Text($0.titre).tag($0) }
                }
                Toggle("Reprendre la dernière lecture", isOn: $reprendre)
            }
            Section {
                Toggle("Pause en arrière-plan", isOn: $pauseArrierePlan)
                Toggle("Image dans l'image", isOn: $imageDansImage)
                Toggle("Rotation en mode paysage", isOn: $rotationPaysage)
            } footer: {
                Text("Pause en arrière-plan : la lecture s'arrête quand vous quittez Elara. Désactivé, la musique continue. Rotation en mode paysage : les vidéos s'ouvrent directement en paysage.")
            }
            Section {
                Toggle("Diffusion AirPlay", isOn: $airplay)
            } footer: {
                Text("Pour diffuser sur une TV ou une enceinte, touchez le bouton AirPlay en haut du lecteur.")
            }
        }
        .navigationTitle("Lecteur")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Gestes

struct ReglagesGestesView: View {
    @AppStorage(Cle.gesteLuminosite) private var luminosite = true
    @AppStorage(Cle.gesteVolume) private var volume = true

    var body: some View {
        Form {
            Section {
                Toggle("Glisser à gauche pour régler la luminosité", isOn: $luminosite)
                Toggle("Glisser à droite pour régler le volume", isOn: $volume)
            } footer: {
                Text("Pendant une vidéo, faites glisser votre doigt vers le haut ou le bas sur la moitié gauche ou droite de l'écran.")
            }
        }
        .navigationTitle("Gestes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sécurité

struct ReglagesSecuriteView: View {
    @Environment(Coffre.self) private var coffre
    @AppStorage(Cle.verrouApp) private var verrouApp = false

    var body: some View {
        Form {
            Section {
                Toggle("Verrouiller Elara à l'ouverture", isOn: $verrouApp)
            } footer: {
                Text("Elara demandera \(coffre.nomBiometrie) à chaque ouverture. Le dossier Privé est toujours protégé, même si cette option est désactivée.")
            }
        }
        .navigationTitle("Code Face ID / Touch ID")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Historique

struct HistoriqueView: View {
    @Environment(Bibliotheque.self) private var bib
    @Environment(LecteurController.self) private var lecteur

    var body: some View {
        List {
            ForEach(bib.historique) { media in
                Button {
                    lecteur.lire(media, dans: bib.historique)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: media.type == .audio ? "music.note" : "film")
                            .foregroundStyle(Theme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(media.nom).lineLimit(1)
                            Text(sousTitre(media))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .overlay {
            if bib.historique.isEmpty {
                ContentUnavailableView(
                    "Aucun historique",
                    systemImage: "clock",
                    description: Text("Les médias que vous lisez apparaîtront ici.")
                )
            }
        }
        .navigationTitle("Historique")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !bib.historique.isEmpty {
                Button("Effacer") { bib.effacerHistorique() }
            }
        }
    }

    private func sousTitre(_ media: Media) -> String {
        var texte = media.derniereLecture?.formatted(.relative(presentation: .named)) ?? ""
        if media.position > 1 {
            texte += " · " + String(localized: "arrêté à \(Format.duree(media.position))")
        }
        return texte
    }
}

// MARK: - Aide

struct AideView: View {
    private let questions: [(LocalizedStringKey, LocalizedStringKey)] = [
        ("Comment ajouter des vidéos ?",
         "Sur l'accueil, touchez + puis « Importer depuis Photos » ou « Importer depuis Fichiers ». Vous pouvez aussi déposer des fichiers dans le dossier Elara de l'app Fichiers."),
        ("Comment transférer depuis mon ordinateur ?",
         "Ouvrez l'onglet Transfert, choisissez « Ordinateur » puis touchez « Démarrer ». Tapez l'adresse affichée dans le navigateur de votre ordinateur, connecté au même Wi‑Fi."),
        ("Comment envoyer à un autre iPhone ?",
         "Ouvrez l'onglet Transfert sur les deux iPhone, choisissez « iPhone à proximité », puis touchez l'autre appareil sur le radar."),
        ("Comment cacher une vidéo ?",
         "Appuyez longuement sur un média puis choisissez « Déplacer vers Privé ». Le dossier Privé est protégé par Face ID."),
        ("Comment réduire la taille d'une vidéo ?",
         "Ouvrez l'onglet Compresser, choisissez une vidéo, une qualité, puis touchez « Compresser »."),
        ("Quels liens puis-je télécharger ?",
         "Uniquement des liens directs vers un fichier vidéo ou audio (mp4, mov, mp3, m4a…). Les réseaux sociaux et plateformes de streaming ne sont pas pris en charge.")
    ]

    var body: some View {
        List {
            ForEach(questions.indices, id: \.self) { i in
                DisclosureGroup {
                    Text(questions[i].1)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } label: {
                    Text(questions[i].0).font(.subheadline.weight(.semibold))
                }
            }
        }
        .navigationTitle("Aide")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - À propos

struct AProposView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.degrade)
                .frame(width: 110, height: 110)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(.white)
                }
            Text("Elara").font(.largeTitle.bold())
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Votre lecteur vidéo et audio.")
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .padding(.top, 48)
        .navigationTitle("À propos")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Infos de l'appareil (bas des réglages)

@MainActor
enum InfosAppareil {
    static func resume() -> String {
        let ios = "iOS " + UIDevice.current.systemVersion
        let valeurs = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ])
        guard let total = valeurs?.volumeTotalCapacity,
              let libre = valeurs?.volumeAvailableCapacityForImportantUsage else { return ios }
        let t = ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
        let l = ByteCountFormatter.string(fromByteCount: libre, countStyle: .file)
        return ios + "   " + String(localized: "Total : \(t)") + "   " + String(localized: "Libre : \(l)")
    }
}
