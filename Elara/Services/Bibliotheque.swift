import Foundation
import AVFoundation
import UIKit
import Observation

/// Gère les médias de l'app.
/// - Médias normaux : dossier Documents (visible aussi depuis l'app Fichiers).
/// - Médias privés : dossier caché « Coffre », invisible dans l'app Fichiers.
@MainActor
@Observable
final class Bibliotheque {
    private(set) var tous: [Media] = []
    var importEnCours = false

    var medias: [Media] { tous.filter { !$0.estPrive } }
    var mediasPrives: [Media] { tous.filter { $0.estPrive } }

    static let extensionsVideo: Set<String> = ["mp4", "mov", "m4v", "3gp"]
    static let extensionsAudio: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac"]

    let dossierMedias: URL
    @ObservationIgnored private let dossierCoffre: URL
    @ObservationIgnored private let fichierIndex: URL
    @ObservationIgnored private let dossierMiniatures: URL
    @ObservationIgnored private let dossierMiniaturesPrivees: URL
    @ObservationIgnored private var enTraitement = Set<String>()
    @ObservationIgnored private var synchroEnCours = false

    init() {
        let fm = FileManager.default
        dossierMedias = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]

        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        fichierIndex = support.appendingPathComponent("bibliotheque.json")

        dossierCoffre = support.appendingPathComponent("Coffre", isDirectory: true)
        dossierMiniaturesPrivees = dossierCoffre.appendingPathComponent(".miniatures", isDirectory: true)
        try? fm.createDirectory(at: dossierMiniaturesPrivees, withIntermediateDirectories: true)

        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dossierMiniatures = caches.appendingPathComponent("miniatures", isDirectory: true)
        try? fm.createDirectory(at: dossierMiniatures, withIntermediateDirectories: true)

        charger()
    }

    // MARK: - Chemins

    func url(de media: Media) -> URL {
        (media.estPrive ? dossierCoffre : dossierMedias).appendingPathComponent(media.fichier)
    }

    func urlMiniature(de media: Media) -> URL {
        (media.estPrive ? dossierMiniaturesPrivees : dossierMiniatures)
            .appendingPathComponent(media.id.uuidString + ".jpg")
    }

    static func type(pour ext: String) -> TypeMedia? {
        let e = ext.lowercased()
        if extensionsVideo.contains(e) { return .video }
        if extensionsAudio.contains(e) { return .audio }
        return nil
    }

    // MARK: - Import

    /// Copie (ou déplace) un fichier dans la bibliothèque, ou directement dans le dossier privé.
    @discardableResult
    func importer(depuis source: URL, deplacer: Bool = false, prive: Bool = false) async -> Media? {
        guard let type = Self.type(pour: source.pathExtension) else { return nil }
        let acces = source.startAccessingSecurityScopedResource()
        defer { if acces { source.stopAccessingSecurityScopedResource() } }

        let destination = urlLibre(pour: source.lastPathComponent, dans: prive ? dossierCoffre : dossierMedias)
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
        if prive { proteger(destination) }
        return await ajouter(fichier: destination, type: type, prive: prive)
    }

    @discardableResult
    private func ajouter(fichier: URL, type: TypeMedia, prive: Bool = false) async -> Media {
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
            duree: duree.isFinite ? duree : 0,
            prive: prive ? true : nil
        )
        if type == .video {
            await genererMiniature(media, asset: asset)
        }
        tous.insert(media, at: 0)
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
            let cible = urlMiniature(de: media)
            try? data.write(to: cible)
            if media.estPrive { proteger(cible) }
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
                  !tous.contains(where: { !$0.estPrive && $0.fichier == nom }),
                  let type = Self.type(pour: fichier.pathExtension) else { continue }
            await ajouter(fichier: fichier, type: type)
        }

        let avant = tous.count
        tous.removeAll { !FileManager.default.fileExists(atPath: url(de: $0).path) }
        if tous.count != avant { enregistrer() }
    }

    // MARK: - Dossier privé

    /// Range un média dans le dossier privé (ou l'en sort).
    func definirPrive(_ media: Media, _ prive: Bool) {
        guard let i = tous.firstIndex(where: { $0.id == media.id }), tous[i].estPrive != prive else { return }
        let ancien = tous[i]
        var nouveau = ancien
        nouveau.prive = prive ? true : nil
        let destination = urlLibre(pour: ancien.fichier, dans: prive ? dossierCoffre : dossierMedias)
        nouveau.fichier = destination.lastPathComponent

        do {
            try FileManager.default.moveItem(at: url(de: ancien), to: destination)
        } catch {
            return
        }
        try? FileManager.default.moveItem(at: urlMiniature(de: ancien), to: urlMiniature(de: nouveau))
        if prive {
            proteger(destination)
            nouveau.derniereLecture = nil
        }
        tous[i] = nouveau
        enregistrer()
    }

    /// Le fichier reste lisible pendant la lecture, mais est chiffré quand l'iPhone est verrouillé.
    private func proteger(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen],
            ofItemAtPath: url.path
        )
    }

    // MARK: - Modifications

    func supprimer(_ media: Media) {
        try? FileManager.default.removeItem(at: url(de: media))
        try? FileManager.default.removeItem(at: urlMiniature(de: media))
        tous.removeAll { $0.id == media.id }
        enregistrer()
    }

    func renommer(_ media: Media, en nom: String) {
        let propre = nom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty, let i = tous.firstIndex(where: { $0.id == media.id }) else { return }
        tous[i].nom = propre
        enregistrer()
    }

    func memoriserPosition(_ id: UUID, _ position: Double) {
        guard let i = tous.firstIndex(where: { $0.id == id }) else { return }
        tous[i].position = position.isFinite ? max(0, position) : 0
        if !tous[i].estPrive { tous[i].derniereLecture = Date() }
        enregistrer()
    }

    func media(id: UUID) -> Media? {
        tous.first { $0.id == id }
    }

    // MARK: - Historique (sans les médias privés)

    var historique: [Media] {
        medias
            .filter { $0.derniereLecture != nil }
            .sorted { ($0.derniereLecture ?? .distantPast) > ($1.derniereLecture ?? .distantPast) }
    }

    func effacerHistorique() {
        for i in tous.indices where !tous[i].estPrive {
            tous[i].derniereLecture = nil
            tous[i].position = 0
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
        tous = liste.filter { FileManager.default.fileExists(atPath: url(de: $0).path) }
    }

    private func enregistrer() {
        if let data = try? JSONEncoder().encode(tous) {
            try? data.write(to: fichierIndex, options: .atomic)
        }
    }

    private func urlLibre(pour nom: String, dans dossier: URL) -> URL {
        var url = dossier.appendingPathComponent(nom)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dossier.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return url
    }
}
