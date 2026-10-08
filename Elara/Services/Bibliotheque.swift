import Foundation
import AVFoundation
import UIKit
import Observation

/// Gère les médias stockés dans l'app (dossier Documents, visible aussi depuis l'app Fichiers).
@MainActor
@Observable
final class Bibliotheque {
    private(set) var medias: [Media] = []
    var importEnCours = false

    static let extensionsVideo: Set<String> = ["mp4", "mov", "m4v", "3gp"]
    static let extensionsAudio: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac"]

    let dossierMedias: URL
    @ObservationIgnored private let fichierIndex: URL
    @ObservationIgnored private let dossierMiniatures: URL
    @ObservationIgnored private var enTraitement = Set<String>()
    @ObservationIgnored private var synchroEnCours = false

    init() {
        let fm = FileManager.default
        dossierMedias = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]

        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        fichierIndex = support.appendingPathComponent("bibliotheque.json")

        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dossierMiniatures = caches.appendingPathComponent("miniatures", isDirectory: true)
        try? fm.createDirectory(at: dossierMiniatures, withIntermediateDirectories: true)

        charger()
    }

    // MARK: - Chemins

    func url(de media: Media) -> URL {
        dossierMedias.appendingPathComponent(media.fichier)
    }

    func urlMiniature(de media: Media) -> URL {
        dossierMiniatures.appendingPathComponent(media.id.uuidString + ".jpg")
    }

    static func type(pour ext: String) -> TypeMedia? {
        let e = ext.lowercased()
        if extensionsVideo.contains(e) { return .video }
        if extensionsAudio.contains(e) { return .audio }
        return nil
    }

    // MARK: - Import

    /// Copie (ou déplace) un fichier dans la bibliothèque.
    @discardableResult
    func importer(depuis source: URL, deplacer: Bool = false) async -> Media? {
        guard let type = Self.type(pour: source.pathExtension) else { return nil }
        let acces = source.startAccessingSecurityScopedResource()
        defer { if acces { source.stopAccessingSecurityScopedResource() } }

        let destination = urlLibre(pour: source.lastPathComponent)
        enTraitement.insert(destination.lastPathComponent)
        do {
            if deplacer {
                try FileManager.default.moveItem(at: source, to: destination)
            } else {
                try FileManager.default.copyItem(at: source, to: destination)
            }
        } catch {
            enTraitement.remove(destination.lastPathComponent)
            return nil
        }
        return await ajouter(fichier: destination, type: type)
    }

    @discardableResult
    private func ajouter(fichier: URL, type: TypeMedia) async -> Media {
        let nomFichier = fichier.lastPathComponent
        enTraitement.insert(nomFichier)
        defer { enTraitement.remove(nomFichier) }

        let asset = AVURLAsset(url: fichier)
        let duree = (try? await asset.load(.duration))?.seconds ?? 0
        let attributs = try? FileManager.default.attributesOfItem(atPath: fichier.path)
        let taille = (attributs?[.size] as? NSNumber)?.int64Value ?? 0

        let media = Media(
            nom: fichier.deletingPathExtension().lastPathComponent,
            fichier: nomFichier,
            type: type,
            taille: taille,
            duree: duree.isFinite ? duree : 0
        )
        if type == .video {
            await genererMiniature(media, asset: asset)
        }
        medias.insert(media, at: 0)
        enregistrer()
        return media
    }

    private func genererMiniature(_ media: Media, asset: AVURLAsset) async {
        let generateur = AVAssetImageGenerator(asset: asset)
        generateur.appliesPreferredTrackTransform = true
        generateur.maximumSize = CGSize(width: 400, height: 400)
        let instant = CMTime(seconds: min(1, media.duree / 2), preferredTimescale: 600)
        guard let resultat = try? await generateur.image(at: instant) else { return }
        let image = UIImage(cgImage: resultat.image)
        if let data = image.jpegData(compressionQuality: 0.7) {
            try? data.write(to: urlMiniature(de: media))
        }
    }

    /// Ajoute les fichiers déposés via l'app Fichiers et retire ceux qui ont disparu.
    func synchroniserDossier() async {
        guard !synchroEnCours else { return }
        synchroEnCours = true
        defer { synchroEnCours = false }

        let contenu = (try? FileManager.default.contentsOfDirectory(
            at: dossierMedias, includingPropertiesForKeys: nil)) ?? []
        for fichier in contenu {
            let nom = fichier.lastPathComponent
            guard !enTraitement.contains(nom),
                  !medias.contains(where: { $0.fichier == nom }),
                  let type = Self.type(pour: fichier.pathExtension) else { continue }
            await ajouter(fichier: fichier, type: type)
        }

        let avant = medias.count
        medias.removeAll { !FileManager.default.fileExists(atPath: url(de: $0).path) }
        if medias.count != avant { enregistrer() }
    }

    // MARK: - Modifications

    func supprimer(_ media: Media) {
        try? FileManager.default.removeItem(at: url(de: media))
        try? FileManager.default.removeItem(at: urlMiniature(de: media))
        medias.removeAll { $0.id == media.id }
        enregistrer()
    }

    func renommer(_ media: Media, en nom: String) {
        let propre = nom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty, let i = medias.firstIndex(where: { $0.id == media.id }) else { return }
        medias[i].nom = propre
        enregistrer()
    }

    func memoriserPosition(_ id: UUID, _ position: Double) {
        guard let i = medias.firstIndex(where: { $0.id == id }) else { return }
        medias[i].position = position.isFinite ? max(0, position) : 0
        medias[i].derniereLecture = Date()
        enregistrer()
    }

    func media(id: UUID) -> Media? {
        medias.first { $0.id == id }
    }

    // MARK: - Historique

    var historique: [Media] {
        medias
            .filter { $0.derniereLecture != nil }
            .sorted { ($0.derniereLecture ?? .distantPast) > ($1.derniereLecture ?? .distantPast) }
    }

    func effacerHistorique() {
        for i in medias.indices {
            medias[i].derniereLecture = nil
            medias[i].position = 0
        }
        enregistrer()
    }

    // MARK: - Cache

    func tailleCache() -> Int64 {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: fm.temporaryDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    func viderCache() {
        let fm = FileManager.default
        let elements = (try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in elements { try? fm.removeItem(at: url) }
    }

    // MARK: - Persistance

    private func charger() {
        guard let data = try? Data(contentsOf: fichierIndex),
              let liste = try? JSONDecoder().decode([Media].self, from: data) else { return }
        medias = liste.filter { FileManager.default.fileExists(atPath: url(de: $0).path) }
    }

    private func enregistrer() {
        if let data = try? JSONEncoder().encode(medias) {
            try? data.write(to: fichierIndex, options: .atomic)
        }
    }

    private func urlLibre(pour nom: String) -> URL {
        var url = dossierMedias.appendingPathComponent(nom)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dossierMedias.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return url
    }
}
