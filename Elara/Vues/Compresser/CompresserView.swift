import SwiftUI
import Photos
import AVFoundation

/// Source d'une vidéo à compresser : la photothèque ou la bibliothèque d'Elara.
enum SourceCompression: Identifiable {
    case photo(PHAsset)
    case app(Media)

    var id: String {
        switch self {
        case .photo(let asset): "photo-" + asset.localIdentifier
        case .app(let media): "app-" + media.id.uuidString
        }
    }
}

struct CompresserView: View {
    @Environment(Bibliotheque.self) private var bib
    @AppStorage("compresser.onglet") private var onglet = 0
    @State private var photos = VideosPhotos()
    @State private var aCompresser: SourceCompression?

    private let colonnes = [GridItem(.adaptive(minimum: 105), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Source", selection: $onglet) {
                    Text("Photos").tag(0)
                    Text("Vidéos de l'app").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                if onglet == 0 { ongletPhotos } else { ongletApp }
            }
            .navigationTitle("Compresser")
            .sheet(item: $aCompresser) { source in
                CompressionSheet(source: source)
            }
        }
    }

    // MARK: - Photos

    @ViewBuilder
    private var ongletPhotos: some View {
        switch photos.autorisation {
        case .authorized, .limited:
            if photos.videos.isEmpty {
                ContentUnavailableView("Aucune vidéo", systemImage: "video.slash",
                                       description: Text("Votre photothèque ne contient pas de vidéo."))
            } else {
                ScrollView {
                    LazyVGrid(columns: colonnes, spacing: 12) {
                        ForEach(photos.videos, id: \.localIdentifier) { asset in
                            Button { aCompresser = .photo(asset) } label: {
                                VignettePhoto(asset: asset)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .refreshable { photos.charger() }
            }
        case .notDetermined:
            ProgressView().task { await photos.demanderAcces() }
        default:
            ContentUnavailableView {
                Label("Accès aux Photos refusé", systemImage: "lock.circle")
            } description: {
                Text("Autorisez Elara à accéder à vos photos dans les Réglages pour compresser vos vidéos.")
            } actions: {
                Button("Ouvrir les Réglages") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Vidéos de l'app

    @ViewBuilder
    private var ongletApp: some View {
        let videos = bib.medias.filter { $0.type == .video }
        if videos.isEmpty {
            ContentUnavailableView("Aucune vidéo", systemImage: "shippingbox",
                                   description: Text("Importez des vidéos dans Elara depuis l'accueil."))
        } else {
            ScrollView {
                LazyVGrid(columns: colonnes, spacing: 14) {
                    ForEach(videos) { media in
                        Button { aCompresser = .app(media) } label: {
                            VignetteMedia(media: media)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - Photothèque

@MainActor
@Observable
final class VideosPhotos {
    private(set) var autorisation = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var videos: [PHAsset] = []

    init() {
        if autorisation == .authorized || autorisation == .limited { charger() }
    }

    func demanderAcces() async {
        autorisation = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if autorisation == .authorized || autorisation == .limited { charger() }
    }

    func charger() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let resultat = PHAsset.fetchAssets(with: .video, options: options)
        var liste: [PHAsset] = []
        resultat.enumerateObjects { asset, _, _ in liste.append(asset) }
        videos = liste
    }

    static func taille(de asset: PHAsset) -> Int64 {
        let ressources = PHAssetResource.assetResources(for: asset)
        let video = ressources.first { $0.type == .video || $0.type == .fullSizeVideo } ?? ressources.first
        return (video?.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
    }

    static func chargerAsset(_ asset: PHAsset) async -> AVAsset? {
        await withCheckedContinuation { suite in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.version = .current
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                suite.resume(returning: avAsset)
            }
        }
    }
}

struct VignettePhoto: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var taille: Int64 = 0

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Theme.degrade
                }
            }
            .overlay(alignment: .bottom) {
                HStack {
                    Pastille(texte: Format.duree(asset.duration))
                    Spacer(minLength: 2)
                    if taille > 0 { Pastille(texte: Format.taille(taille)) }
                }
                .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .task(id: asset.localIdentifier) {
                taille = VideosPhotos.taille(de: asset)
                let options = PHImageRequestOptions()
                options.isNetworkAccessAllowed = true
                options.deliveryMode = .opportunistic
                PHImageManager.default().requestImage(
                    for: asset, targetSize: CGSize(width: 300, height: 300),
                    contentMode: .aspectFill, options: options
                ) { resultat, _ in
                    if let resultat { image = resultat }
                }
            }
    }
}

// MARK: - Feuille de compression

struct CompressionSheet: View {
    let source: SourceCompression

    @Environment(Bibliotheque.self) private var bib
    @Environment(\.dismiss) private var fermer
    @State private var compresseur = Compresseur()
    @State private var qualite: QualiteCompression = .moyenne
    @State private var resultat: URL?
    @State private var tailleResultat: Int64 = 0
    @State private var message: String?

    private var nom: String {
        switch source {
        case .photo(let asset):
            PHAssetResource.assetResources(for: asset).first.map {
                ($0.originalFilename as NSString).deletingPathExtension
            } ?? "Vidéo"
        case .app(let media): media.nom
        }
    }

    private var tailleOriginale: Int64 {
        switch source {
        case .photo(let asset): VideosPhotos.taille(de: asset)
        case .app(let media): media.taille
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vidéo") {
                    LabeledContent("Nom", value: nom)
                    LabeledContent("Taille actuelle", value: Format.taille(tailleOriginale))
                }

                if resultat == nil {
                    Section {
                        Picker("Qualité", selection: $qualite) {
                            ForEach(QualiteCompression.allCases) { Text($0.titre).tag($0) }
                        }
                        LabeledContent("Taille estimée",
                                       value: "≈ " + Format.taille(Int64(Double(tailleOriginale) * qualite.facteurEstime)))
                    } footer: {
                        Text("L'estimation dépend de la vidéo. Une vidéo déjà légère peut peu diminuer.")
                    }

                    Section {
                        if compresseur.enCours {
                            VStack(alignment: .leading, spacing: 8) {
                                ProgressView(value: compresseur.progression)
                                Text("Compression… \(Int(compresseur.progression * 100)) %")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Button("Annuler", role: .destructive) { compresseur.annuler() }
                        } else {
                            Button {
                                Task { await lancer() }
                            } label: {
                                Label("Compresser", systemImage: "rectangle.compress.vertical")
                            }
                        }
                    }
                } else {
                    sectionResultat
                }

                if let erreur = compresseur.erreur {
                    Section { Text(erreur).foregroundStyle(.red) }
                }
                if let message {
                    Section { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
            .navigationTitle("Compression")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        compresseur.annuler()
                        fermer()
                    }
                }
            }
            .interactiveDismissDisabled(compresseur.enCours)
        }
    }

    @ViewBuilder
    private var sectionResultat: some View {
        let gain = tailleOriginale > 0 ? 100 - Int(Double(tailleResultat) / Double(tailleOriginale) * 100) : 0
        Section("Résultat") {
            LabeledContent("Nouvelle taille", value: Format.taille(tailleResultat))
            LabeledContent("Gain", value: gain > 0 ? "\(gain) %" : String(localized: "aucun"))
        }
        if let resultat {
            Section {
                switch source {
                case .photo(let asset):
                    Button("Enregistrer dans Photos", systemImage: "square.and.arrow.down") {
                        Task { await enregistrerDansPhotos(resultat) }
                    }
                    Button("Ajouter à Elara", systemImage: "plus.square.on.square") {
                        Task {
                            await bib.importer(depuis: resultat)
                            message = String(localized: "Ajoutée à Elara.")
                        }
                    }
                    Button("Supprimer l'original de Photos", systemImage: "trash", role: .destructive) {
                        Task { await supprimerOriginal(asset) }
                    }
                case .app(let media):
                    Button("Remplacer l'original", systemImage: "arrow.triangle.2.circlepath") {
                        bib.remplacer(media, par: resultat)
                        fermer()
                    }
                    Button("Garder les deux", systemImage: "plus.square.on.square") {
                        Task {
                            await bib.importer(depuis: resultat)
                            fermer()
                        }
                    }
                }
            }
        }
    }

    private func lancer() async {
        let asset: AVAsset?
        switch source {
        case .photo(let photo): asset = await VideosPhotos.chargerAsset(photo)
        case .app(let media): asset = AVURLAsset(url: bib.url(de: media))
        }
        guard let asset else {
            compresseur.erreur = String(localized: "Impossible d'ouvrir cette vidéo.")
            return
        }
        if let url = await compresseur.compresser(asset, nom: nom, qualite: qualite) {
            let attributs = try? FileManager.default.attributesOfItem(atPath: url.path)
            tailleResultat = (attributs?[.size] as? NSNumber)?.int64Value ?? 0
            resultat = url
        }
    }

    private func enregistrerDansPhotos(_ url: URL) async {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            message = String(localized: "Enregistrée dans Photos.")
        } catch {
            compresseur.erreur = String(localized: "Impossible d'enregistrer dans Photos.")
        }
    }

    private func supprimerOriginal(_ asset: PHAsset) async {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            }
            message = String(localized: "Original supprimé (il reste 30 jours dans « Supprimés récemment »).")
        } catch {
            // L'utilisateur a refusé la suppression : rien à faire.
        }
    }
}
