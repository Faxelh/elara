import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Ajoute l'import depuis Photos et depuis Fichiers à une vue.
struct ImportMedias: ViewModifier {
    @Binding var photos: Bool
    @Binding var fichiers: Bool
    @Binding var ecran: Bool
    var dossier: UUID?

    @Environment(Bibliotheque.self) private var bib
    @State private var selection: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $photos,
                selection: $selection,
                maxSelectionCount: 20,
                matching: .videos,
                preferredItemEncoding: .current
            )
            .photosPicker(
                isPresented: $ecran,
                selection: $selection,
                maxSelectionCount: 20,
                matching: .screenRecordings,
                preferredItemEncoding: .current
            )
            .onChange(of: selection) { _, elements in
                guard !elements.isEmpty else { return }
                Task {
                    bib.importEnCours = true
                    for element in elements {
                        if let video = try? await element.loadTransferable(type: VideoTransferable.self) {
                            await bib.importer(depuis: video.url, deplacer: true, dossier: dossier)
                        }
                    }
                    selection = []
                    bib.importEnCours = false
                }
            }
            .fileImporter(
                isPresented: $fichiers,
                allowedContentTypes: [.movie, .audio],
                allowsMultipleSelection: true
            ) { resultat in
                guard case .success(let urls) = resultat else { return }
                Task {
                    bib.importEnCours = true
                    for url in urls { await bib.importer(depuis: url, dossier: dossier) }
                    bib.importEnCours = false
                }
            }
    }
}

extension View {
    func importMedias(photos: Binding<Bool>, fichiers: Binding<Bool>,
                      ecran: Binding<Bool> = .constant(false), dossier: UUID? = nil) -> some View {
        modifier(ImportMedias(photos: photos, fichiers: fichiers, ecran: ecran, dossier: dossier))
    }
}

/// Menu « ⋮ » : vue grille/liste et tri.
struct MenuAffichage: View {
    @AppStorage(Cle.vueAccueil) private var vue: VueAccueil = .grille
    @AppStorage(Cle.triAccueil) private var tri: TriMedias = .date
    @AppStorage(Cle.triCroissant) private var croissant = false

    var body: some View {
        Menu {
            Section {
                ForEach(VueAccueil.allCases) { option in
                    Button {
                        vue = option
                    } label: {
                        if vue == option {
                            Label(option.titre, systemImage: "checkmark")
                        } else {
                            Label(option.titre, systemImage: option.icone)
                        }
                    }
                }
            }
            Section("Trier par") {
                ForEach(TriMedias.allCases) { option in
                    Button {
                        if tri == option { croissant.toggle() } else { tri = option }
                    } label: {
                        if tri == option {
                            Label("\(option.titre) (\(sens(option)))", systemImage: "checkmark")
                        } else {
                            Text(option.titre)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3)
        }
        .accessibilityLabel("Affichage et tri")
    }

    private func sens(_ option: TriMedias) -> String {
        switch option {
        case .nom: croissant ? "A → Z" : "Z → A"
        case .date: croissant ? String(localized: "plus anciens") : String(localized: "plus récents")
        case .taille: croissant ? String(localized: "plus petits") : String(localized: "plus gros")
        }
    }
}

/// Champ « Nouveau dossier » limité à 20 caractères.
struct AlerteNouveauDossier: ViewModifier {
    @Binding var affichee: Bool
    var titre: LocalizedStringKey = "Nouveau dossier"
    var valeurInitiale = ""
    var valider: (String) -> Void
    @State private var nom = ""

    func body(content: Content) -> some View {
        content
            .alert(titre, isPresented: $affichee) {
                TextField("Nom (20 caractères max)", text: $nom)
                    .onChange(of: nom) { _, valeur in
                        if valeur.count > Dossier.longueurMax { nom = String(valeur.prefix(Dossier.longueurMax)) }
                    }
                Button("Annuler", role: .cancel) {}
                Button("OK") { valider(nom) }
            }
            .onChange(of: affichee) { _, ouverte in
                if ouverte { nom = valeurInitiale }
            }
    }
}

extension View {
    func alerteDossier(_ affichee: Binding<Bool>, titre: LocalizedStringKey = "Nouveau dossier",
                       valeurInitiale: String = "", valider: @escaping (String) -> Void) -> some View {
        modifier(AlerteNouveauDossier(affichee: affichee, titre: titre, valeurInitiale: valeurInitiale, valider: valider))
    }
}
