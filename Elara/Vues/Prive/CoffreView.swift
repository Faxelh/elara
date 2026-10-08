import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Dossier privé : protégé par Face ID, invisible dans l'app Fichiers et absent de l'historique.
struct CoffreView: View {
    @Environment(Bibliotheque.self) private var bib
    @Environment(LecteurController.self) private var lecteur
    @Environment(Coffre.self) private var coffre

    @State private var selectionPhotos: [PhotosPickerItem] = []
    @State private var afficherPhotos = false
    @State private var afficherFichiers = false
    @State private var aSupprimer: Media?

    private let colonnes = [GridItem(.adaptive(minimum: 105), spacing: 12)]

    var body: some View {
        Group {
            if coffre.estDeverrouille {
                contenu
            } else {
                ecranVerrouille
            }
        }
        .navigationTitle("Privé")
        .toolbar {
            if coffre.estDeverrouille {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Ajouter depuis Photos", systemImage: "photo") { afficherPhotos = true }
                        Button("Ajouter depuis Fichiers", systemImage: "folder") { afficherFichiers = true }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        coffre.verrouiller()
                    } label: {
                        Image(systemName: "lock.fill")
                    }
                    .accessibilityLabel("Verrouiller")
                }
            }
        }
        .photosPicker(
            isPresented: $afficherPhotos,
            selection: $selectionPhotos,
            maxSelectionCount: 20,
            matching: .videos,
            preferredItemEncoding: .current
        )
        .onChange(of: selectionPhotos) { _, elements in
            guard !elements.isEmpty else { return }
            Task { await importerPhotos(elements) }
        }
        .fileImporter(
            isPresented: $afficherFichiers,
            allowedContentTypes: [.movie, .audio],
            allowsMultipleSelection: true
        ) { resultat in
            guard case .success(let urls) = resultat else { return }
            Task {
                bib.importEnCours = true
                for url in urls { await bib.importer(depuis: url, prive: true) }
                bib.importEnCours = false
            }
        }
        .confirmationDialog(
            "Supprimer définitivement ce média ?",
            isPresented: Binding(get: { aSupprimer != nil }, set: { if !$0 { aSupprimer = nil } }),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let media = aSupprimer { bib.supprimer(media) }
            }
        }
        .task {
            if !coffre.estDeverrouille { await coffre.deverrouiller() }
        }
    }

    // MARK: - Écrans

    private var ecranVerrouille: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.corail)
            Text("Dossier privé verrouillé")
                .font(.title2.bold())
            Text("Vos médias privés sont cachés : ils n'apparaissent ni dans l'accueil, ni dans l'historique, ni dans l'app Fichiers.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button {
                Task { await coffre.deverrouiller() }
            } label: {
                Label("Déverrouiller avec \(coffre.nomBiometrie)", systemImage: "faceid")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.corail)
            if let erreur = coffre.erreur {
                Text(erreur)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            Spacer()
        }
    }

    private var contenu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if bib.importEnCours {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Importation en cours…").foregroundStyle(.secondary)
                    }
                }
                if bib.mediasPrives.isEmpty {
                    ContentUnavailableView(
                        "Dossier privé vide",
                        systemImage: "lock.shield",
                        description: Text("Ajoutez des médias avec le bouton +, ou appuyez longuement sur un média de l'accueil puis choisissez « Déplacer vers Privé ».")
                    )
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: colonnes, spacing: 14) {
                        ForEach(bib.mediasPrives) { media in
                            Button {
                                lecteur.lire(media, dans: bib.mediasPrives)
                            } label: {
                                VignetteMedia(media: media)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Lire", systemImage: "play.fill") {
                                    lecteur.lire(media, dans: bib.mediasPrives)
                                }
                                Button("Retirer du dossier privé", systemImage: "lock.open") {
                                    bib.definirPrive(media, false)
                                }
                                Button("Supprimer", systemImage: "trash", role: .destructive) {
                                    aSupprimer = media
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func importerPhotos(_ elements: [PhotosPickerItem]) async {
        bib.importEnCours = true
        for element in elements {
            if let video = try? await element.loadTransferable(type: VideoTransferable.self) {
                await bib.importer(depuis: video.url, deplacer: true, prive: true)
            }
        }
        selectionPhotos = []
        bib.importEnCours = false
    }
}
