import Foundation
import AVFoundation
import Observation

enum QualiteCompression: String, CaseIterable, Identifiable {
    case haute, moyenne, basse

    var id: String { rawValue }

    var titre: String {
        switch self {
        case .haute: String(localized: "Haute (1080p)")
        case .moyenne: String(localized: "Moyenne (720p)")
        case .basse: String(localized: "Basse (480p)")
        }
    }

    var preset: String {
        switch self {
        case .haute: AVAssetExportPreset1920x1080
        case .moyenne: AVAssetExportPreset1280x720
        case .basse: AVAssetExportPreset640x480
        }
    }

    /// Estimation grossière de la taille finale par rapport à l'original
    var facteurEstime: Double {
        switch self {
        case .haute: 0.6
        case .moyenne: 0.35
        case .basse: 0.15
        }
    }
}

/// Compresse une vidéo avec AVFoundation (réencodage H.264 en .mp4).
@MainActor
@Observable
final class Compresseur {
    private(set) var progression: Double = 0
    private(set) var enCours = false
    var erreur: String?

    @ObservationIgnored private var session: AVAssetExportSession?

    func compresser(_ asset: AVAsset, nom: String, qualite: QualiteCompression) async -> URL? {
        erreur = nil
        guard let export = AVAssetExportSession(asset: asset, presetName: qualite.preset) else {
            erreur = String(localized: "Cette vidéo ne peut pas être compressée.")
            return nil
        }
        let dossier = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let sortie = dossier.appendingPathComponent("\(nom) (compressée).mp4")

        export.outputURL = sortie
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        session = export
        enCours = true
        progression = 0

        let suivi = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.progression = Double(export.progress)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        await withCheckedContinuation { (suite: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { suite.resume() }
        }
        suivi.cancel()
        enCours = false
        session = nil

        switch export.status {
        case .completed:
            progression = 1
            return sortie
        case .cancelled:
            erreur = String(localized: "Compression annulée.")
        default:
            erreur = export.error?.localizedDescription ?? String(localized: "La compression a échoué.")
        }
        return nil
    }

    func annuler() {
        session?.cancelExport()
    }
}
