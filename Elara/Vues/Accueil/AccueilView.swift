import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AccueilView: View {
    @Environment(Bibliotheque.self) private var bib
    @Environment(LecteurController.self) private var lecteur

    @State private var selectionPhotos: [PhotosPickerItem] = []
    @State private var afficherPhotos = false
    @State private var afficherFichiers = false
    @State private var filtre: Filtre = .tout
    @State private var aRenommer: Media?
    @State private var nouveauNom = ""
    @State private var alertePrive = false

    enum Filtre: String, CaseIterable, Identifiable {
        case tout = "Tout", videos = "Vidéos", audio = "Audio"
        var id: String { rawValue }
    }

    private var mediasFiltres: [Media] {
        switch filtre {
        case .tout: bib.medias
        case .videos: bib.medias.filter { $0.type == .video }
        case .audio: bib.medias.filter { $0.type == .audio }
        }
    }

    private let colonnes = [GridItem(.adaptive(minimum: 105), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        CarteRaccourci(titre: "Photos", icone: "photo.on.rectangle.angled", couleur: Theme.bleu) {
                            afficherPhotos = true
                        }
                        CarteRaccourci(titre: "Fichiers", icone: "folder.fill", couleur: Theme.vert) {
                            afficherFichiers = true
                        }
                        CarteRaccourci(titre: "Privé", icone: "lock.fill", couleur: Theme.corail) {
                            alertePrive = true
                        }
                    }

                    Picker("Filtre", selection: $filtre) {
                        ForEach(Filtre.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if bib.importEnCours {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Importation en cours…").foregroundStyle(.secondary)
                        }
                    }

                    if mediasFiltres.isEmpty {
                        ContentUnavailableView(
                            "Aucun média",
                            systemImage: "shippingbox",
                            description: Text("Importez des vidéos ou de la musique depuis Photos ou Fichiers.")
                        )
                        .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: colonnes, spacing: 14) {
                            ForEach(mediasFiltres) { media in
                                Button {
                                    lecteur.lire(media, dans: mediasFiltres)
                                } label: {
                                    VignetteMedia(media: media)
                                }
                                .buttonStyle(.plain)
                                .contextMenu { menuContextuel(media) }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Elara")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Importer depuis Photos", systemImage: "photo") { afficherPhotos = true }
                        Button("Importer depuis Fichiers", systemImage: "folder") { afficherFichiers = true }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
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
                    for url in urls { await bib.importer(depuis: url) }
                    bib.importEnCours = false
                }
            }
            .alert("Renommer", isPresented: Binding(
                get: { aRenommer != nil },
                set: { if !$0 { aRenommer = nil } }
            )) {
                TextField("Nom", text: $nouveauNom)
                Button("Annuler", role: .cancel) {}
                Button("Valider") {
                    if let media = aRenommer { bib.renommer(media, en: nouveauNom) }
                }
            }
            .alert("Dossier privé", isPresented: $alertePrive) {
                Button("OK") {}
            } message: {
                Text("Le dossier privé protégé par Face ID arrive dans la prochaine version.")
            }
            .refreshable { await bib.synchroniserDossier() }
            .task { await bib.synchroniserDossier() }
        }
    }

    @ViewBuilder
    private func menuContextuel(_ media: Media) -> some View {
        Button("Lire", systemImage: "play.fill") { lecteur.lire(media, dans: mediasFiltres) }
        Button("Renommer", systemImage: "pencil") {
            nouveauNom = media.nom
            aRenommer = media
        }
        ShareLink(item: bib.url(de: media)) {
            Label("Partager", systemImage: "square.and.arrow.up")
        }
        Button("Supprimer", systemImage: "trash", role: .destructive) { bib.supprimer(media) }
    }

    private func importerPhotos(_ elements: [PhotosPickerItem]) async {
        bib.importEnCours = true
        for element in elements {
            if let video = try? await element.loadTransferable(type: VideoTransferable.self) {
                await bib.importer(depuis: video.url, deplacer: true)
            }
        }
        selectionPhotos = []
        bib.importEnCours = false
    }
}

// MARK: - Composants

struct CarteRaccourci: View {
    let titre: String
    let icone: String
    let couleur: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icone)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(couleur)
                HStack(spacing: 4) {
                    Text(titre).font(.subheadline.bold())
                    Image(systemName: "chevron.right").font(.caption2.bold())
                }
                .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(couleur.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct VignetteMedia: View {
    @Environment(Bibliotheque.self) private var bib
    let media: Media

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { apercu }
                .overlay(alignment: .bottom) {
                    VStack(spacing: 4) {
                        HStack {
                            Pastille(texte: media.dureeTexte)
                            Spacer(minLength: 2)
                            Pastille(texte: media.tailleTexte)
                        }
                        if media.progression > 0.01 {
                            ProgressView(value: media.progression)
                                .tint(.white)
                        }
                    }
                    .padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(media.nom)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var apercu: some View {
        if media.type == .video,
           let image = UIImage(contentsOfFile: bib.urlMiniature(de: media).path) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Theme.degrade
                Image(systemName: media.type == .audio ? "music.note" : "film")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

struct Pastille: View {
    let texte: String
    var body: some View {
        Text(texte)
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
    }
}
