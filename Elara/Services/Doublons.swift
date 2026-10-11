import Foundation
import CryptoKit
import Photos
import UIKit

/// Empreinte d'un fichier : sa taille + un SHA-256 du début et de la fin.
/// Deux fichiers identiques ont la même empreinte ; le calcul reste rapide même pour une grosse vidéo.
enum Empreinte {
    static func calculer(_ url: URL) -> String? {
        guard let fichier = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fichier.close() }
        let morceau = 1 << 20
        guard let taille = try? fichier.seekToEnd() else { return nil }
        var hash = SHA256()
        try? fichier.seek(toOffset: 0)
        if let debut = try? fichier.read(upToCount: morceau) { hash.update(data: debut) }
        if taille > UInt64(morceau * 2) {
            try? fichier.seek(toOffset: taille - UInt64(morceau))
            if let fin = try? fichier.read(upToCount: morceau) { hash.update(data: fin) }
        }
        return "\(taille)-" + hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func calculerEnArrierePlan(_ url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) { calculer(url) }.value
    }
}

/// Enregistre des vidéos dans l'app Photos de l'iPhone.
enum Phototheque {
    /// Renvoie le nombre de vidéos enregistrées.
    static func enregistrer(_ urls: [URL]) async -> Int {
        let statut = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard statut == .authorized || statut == .limited else { return 0 }
        var reussis = 0
        for url in urls {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    _ = PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }
                reussis += 1
            } catch {}
        }
        return reussis
    }

    /// Télécharge une image (lien direct) et l'enregistre dans Photos.
    static func enregistrerImage(depuis lien: URL) async -> Bool {
        var requete = URLRequest(url: lien, timeoutInterval: 30)
        requete.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let resultat = try? await URLSession.shared.data(for: requete) else { return false }
        let donnees = resultat.0
        if let http = resultat.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return false }
        guard UIImage(data: donnees) != nil else { return false }
        let statut = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard statut == .authorized || statut == .limited else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: donnees, options: nil)
            }
            return true
        } catch {
            return false
        }
    }
}
