import Foundation
import AVFoundation
import CoreImage

/// Retire des filigranes (logo, texte, @pseudo…) d'une vidéo : en effaçant la zone ou en recadrant l'image.
/// Les zones sont exprimées en proportions de l'image (0…1), origine en haut à gauche.
enum Filigrane {
    struct Erreur: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    enum Mode: String, CaseIterable, Identifiable {
        /// Remplit la zone avec les couleurs qui l'entourent (pas de flou).
        case effacer
        /// Coupe la bande de l'image qui contient le filigrane (aucune trace).
        case recadrer
        var id: String { rawValue }
    }

    /// Partie de l'image gardée quand on recadre (proportions, origine en haut à gauche) :
    /// pour chaque zone, on coupe la bande du bord le plus proche.
    static func partieGardee(_ zones: [CGRect]) -> CGRect {
        var garde = CGRect(x: 0, y: 0, width: 1, height: 1)
        for z in zones {
            let distances: [(CGFloat, Int)] = [(z.minY, 0), (1 - z.maxY, 1), (z.minX, 2), (1 - z.maxX, 3)]
            switch distances.min(by: { $0.0 < $1.0 })!.1 {
            case 0: let haut = max(garde.minY, z.maxY); garde = CGRect(x: garde.minX, y: haut, width: garde.width, height: garde.maxY - haut)
            case 1: garde.size.height = min(garde.maxY, z.minY) - garde.minY
            case 2: let gauche = max(garde.minX, z.maxX); garde = CGRect(x: gauche, y: garde.minY, width: garde.maxX - gauche, height: garde.height)
            default: garde.size.width = min(garde.maxX, z.minX) - garde.minX
            }
        }
        return garde.width > 0.2 && garde.height > 0.2 ? garde : CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    /// Reconstruit une zone à partir des pixels qui l'entourent (comme « delogo ») :
    /// mélange des bords gauche/droite et haut/bas, sans flou du contenu.
    private static func effacer(_ r: CGRect, dans image: CIImage) -> CIImage {
        let e = image.extent
        let g = max(e.minX, r.minX - 2), d = min(e.maxX - 1, r.maxX + 1)
        let b = max(e.minY, r.minY - 2), h = min(e.maxY - 1, r.maxY + 1)
        func colonne(_ x: CGFloat) -> CIImage { image.cropped(to: CGRect(x: x, y: r.minY, width: 1, height: r.height)).clampedToExtent() }
        func ligne(_ y: CGFloat) -> CIImage { image.cropped(to: CGRect(x: r.minX, y: y, width: r.width, height: 1)).clampedToExtent() }
        func degrade(_ p0: CGPoint, _ p1: CGPoint) -> CIImage {
            CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(cgPoint: p0), "inputPoint1": CIVector(cgPoint: p1),
                "inputColor0": CIColor.white, "inputColor1": CIColor.black,
            ])!.outputImage!
        }
        func melanger(_ a: CIImage, _ b: CIImage, masque: CIImage) -> CIImage {
            a.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: b, kCIInputMaskImageKey: masque])
        }
        let horizontal = melanger(colonne(g), colonne(d), masque: degrade(CGPoint(x: r.minX, y: 0), CGPoint(x: r.maxX, y: 0)))
        let vertical = melanger(ligne(b), ligne(h), masque: degrade(CGPoint(x: 0, y: r.minY), CGPoint(x: 0, y: r.maxY)))
        let moitie = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: r)
        return melanger(horizontal, vertical, masque: moitie).cropped(to: r)
    }

    /// Crée une copie de la vidéo sans les filigranes. Le son est conservé.
    static func traiter(_ source: URL, zones: [CGRect], mode: Mode, nom: String,
                        progression: @escaping @MainActor (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let zonesFixes = zones
        let garde = partieGardee(zones)
        let composition = try await AVMutableVideoComposition.videoComposition(with: asset) { requete in
            let image = requete.sourceImage
            let e = image.extent
            // Core Image compte depuis le bas : on retourne l'axe vertical.
            func pixels(_ z: CGRect) -> CGRect {
                CGRect(x: e.minX + z.minX * e.width, y: e.minY + (1 - z.maxY) * e.height,
                       width: z.width * e.width, height: z.height * e.height).integral.intersection(e)
            }
            switch mode {
            case .effacer:
                var sortie = image
                for z in zonesFixes {
                    let r = pixels(z)
                    guard r.width > 2, r.height > 2 else { continue }
                    sortie = effacer(r, dans: image).composited(over: sortie)
                }
                requete.finish(with: sortie, context: nil)
            case .recadrer:
                let r = pixels(garde)
                requete.finish(with: image.cropped(to: r).transformed(by: CGAffineTransform(translationX: -r.minX, y: -r.minY)), context: nil)
            }
        }
        if mode == .recadrer {
            // Taille paire (exigée par l'encodeur vidéo).
            let total = composition.renderSize
            let l = (total.width * garde.width / 2).rounded(.down) * 2
            let h = (total.height * garde.height / 2).rounded(.down) * 2
            composition.renderSize = CGSize(width: max(l, 16), height: max(h, 16))
        }

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw Erreur(message: String(localized: "Cette vidéo ne peut pas être modifiée."))
        }
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let fichierSortie = dossier.appendingPathComponent("\(nom) (sans filigrane).mp4")
        export.videoComposition = composition
        export.outputURL = fichierSortie
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true

        let suivi = Task { @MainActor in
            while !Task.isCancelled {
                progression(Double(export.progress))
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (suite: CheckedContinuation<Void, Never>) in
                export.exportAsynchronously { suite.resume() }
            }
        } onCancel: {
            export.cancelExport()
        }
        suivi.cancel()

        switch export.status {
        case .completed:
            return fichierSortie
        case .cancelled:
            throw CancellationError()
        default:
            throw Erreur(message: export.error?.localizedDescription ?? String(localized: "Le traitement a échoué."))
        }
    }
}
