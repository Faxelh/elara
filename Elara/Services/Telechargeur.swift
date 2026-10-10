import Foundation
import AVFoundation
import Observation

/// Télécharge un fichier vidéo ou audio depuis un lien direct (http/https).
/// Les plateformes de streaming et réseaux sociaux sont volontairement refusées
/// (règles de l'App Store et droits d'auteur).
@MainActor
@Observable
final class Telechargeur {
    private(set) var enCours = false
    private(set) var progression: Double = 0
    private(set) var octetsRecus: Int64 = 0
    /// Vrai pendant la recherche de la vidéo sur la page (liens Facebook, version perso).
    private(set) var recherche = false
    var erreur: String?

    @ObservationIgnored private var tache: URLSessionDownloadTask?
    @ObservationIgnored private var annule = false

    #if PERSO
    static let gereFacebook = true
    #else
    static let gereFacebook = false
    #endif

    static let domainesRefuses = [
        "youtube.com", "youtu.be", "tiktok.com", "instagram.com", "facebook.com", "fb.watch",
        "twitter.com", "x.com", "netflix.com", "dailymotion.com", "vimeo.com", "spotify.com",
        "deezer.com", "snapchat.com"
    ]

    func telecharger(_ texte: String, vers bib: Bibliotheque, prive: Bool) async -> Media? {
        erreur = nil
        annule = false
        let propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: propre),
              let schema = url.scheme?.lowercased(), schema == "http" || schema == "https",
              let hote = url.host?.lowercased() else {
            erreur = String(localized: "Lien invalide : il doit commencer par http:// ou https://")
            return nil
        }
        var nomForce: String?
        #if PERSO
        let estFacebook = ExtracteurFacebook.gere(hote)
        #else
        let estFacebook = false
        #endif
        if !estFacebook, Self.domainesRefuses.contains(where: { hote == $0 || hote.hasSuffix("." + $0) }) {
            erreur = String(localized: "Elara ne télécharge pas depuis les réseaux sociaux ni les plateformes de streaming. Utilisez un lien direct vers un fichier vidéo ou audio.")
            return nil
        }

        enCours = true
        progression = 0
        octetsRecus = 0
        defer {
            enCours = false
            recherche = false
            tache = nil
        }

        do {
            var url = url
            #if PERSO
            if estFacebook {
                recherche = true
                url = try await ExtracteurFacebook.lienVideo(depuis: url)
                recherche = false
                let format = DateFormatter()
                format.dateFormat = "yyyy-MM-dd HH'h'mm"
                nomForce = "Facebook " + format.string(from: Date()) + ".mp4"
            } else if hote.hasSuffix("fbcdn.net") {
                // Fichier vidéo trouvé depuis l'onglet Facebook.
                let format = DateFormatter()
                format.dateFormat = "yyyy-MM-dd HH'h'mm"
                nomForce = "Facebook " + format.string(from: Date()) + ".mp4"
            }
            #endif
            if Task.isCancelled || annule { throw URLError(.cancelled) }
            let lienFinal = url
            let recu = try await telechargerBrut(lienFinal)
            var fichier = recu
            if let nomForce {
                let renomme = fichier.deletingLastPathComponent().appendingPathComponent(nomForce)
                if (try? FileManager.default.moveItem(at: fichier, to: renomme)) != nil { fichier = renomme }
            }
            guard Bibliotheque.type(pour: fichier.pathExtension) != nil else {
                try? FileManager.default.removeItem(at: fichier)
                erreur = String(localized: "Ce lien ne pointe pas vers une vidéo ou une musique prise en charge (mp4, mov, mp3, m4a…).")
                return nil
            }
            guard let media = await bib.importer(depuis: fichier, deplacer: true, prive: prive) else {
                erreur = String(localized: "Le fichier téléchargé n'a pas pu être ajouté.")
                return nil
            }
            return media
        } catch let e as URLError where e.code == .cancelled {
            erreur = String(localized: "Téléchargement annulé.")
        } catch let e as ErreurTelechargement {
            erreur = e.message
        } catch {
            erreur = String(localized: "Le téléchargement a échoué : \(error.localizedDescription)")
        }
        return nil
    }

    /// Télécharge un fichier dans un dossier temporaire et renvoie son emplacement.
    private func telechargerBrut(_ lien: URL, base: Double = 0, part: Double = 1) async throws -> URL {
        try await withCheckedThrowingContinuation { suite in
            let delegue = DelegueTelechargement(
                surProgres: { [weak self] p, o in
                    Task { @MainActor in
                        self?.progression = base + p * part
                        self?.octetsRecus = o
                    }
                },
                surFin: { resultat in suite.resume(with: resultat) }
            )
            let session = URLSession(configuration: .default, delegate: delegue, delegateQueue: nil)
            let t = session.downloadTask(with: lien)
            tache = t
            t.resume()
            session.finishTasksAndInvalidate()
        }
    }

    #if PERSO
    /// Reels : l'image et le son sont souvent deux fichiers. On télécharge les derniers fichiers vus,
    /// on repère ceux qui contiennent l'image et le son, puis on les assemble.
    func telechargerFlux(_ candidats: [URL], vers bib: Bibliotheque, prive: Bool) async -> Media? {
        erreur = nil
        annule = false
        enCours = true
        progression = 0
        octetsRecus = 0
        defer { enCours = false; recherche = false; tache = nil }
        var videoSeule: URL?
        var audioSeul: URL?
        var complet: URL?
        do {
            for (rang, lien) in candidats.enumerated() {
                if Task.isCancelled || annule { throw URLError(.cancelled) }
                let part = 1.0 / Double(max(candidats.count, 1))
                let fichier = try await telechargerBrut(lien, base: Double(rang) * part, part: part)
                let (avecImage, avecSon) = await Self.pistes(de: fichier)
                if avecImage && avecSon { complet = fichier; break }
                if avecImage, videoSeule == nil { videoSeule = fichier }
                else if avecSon, audioSeul == nil { audioSeul = fichier }
                if videoSeule != nil && audioSeul != nil { break }
            }
            var final = complet ?? videoSeule
            if complet == nil, let v = videoSeule, let a = audioSeul {
                final = (try? await Self.assembler(video: v, audio: a)) ?? v
            }
            guard var fichier = final else {
                erreur = String(localized: "Le fichier téléchargé n'a pas pu être ajouté.")
                return nil
            }
            let format = DateFormatter()
            format.dateFormat = "yyyy-MM-dd HH'h'mm"
            let renomme = fichier.deletingLastPathComponent()
                .appendingPathComponent("Facebook " + format.string(from: Date()) + ".mp4")
            try? FileManager.default.removeItem(at: renomme)
            if (try? FileManager.default.moveItem(at: fichier, to: renomme)) != nil { fichier = renomme }
            guard let media = await bib.importer(depuis: fichier, deplacer: true, prive: prive) else {
                erreur = String(localized: "Le fichier téléchargé n'a pas pu être ajouté.")
                return nil
            }
            return media
        } catch let e as URLError where e.code == .cancelled {
            erreur = String(localized: "Téléchargement annulé.")
        } catch let e as ErreurTelechargement {
            erreur = e.message
        } catch {
            erreur = String(localized: "Le téléchargement a échoué : \(error.localizedDescription)")
        }
        return nil
    }

    private static func pistes(de fichier: URL) async -> (image: Bool, son: Bool) {
        // Facebook sert des fichiers sans extension reconnue : on travaille sur une copie en .mp4.
        let copie = fichier.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".mp4")
        guard (try? FileManager.default.copyItem(at: fichier, to: copie)) != nil else { return (false, false) }
        defer { try? FileManager.default.removeItem(at: copie) }
        let asset = AVURLAsset(url: copie)
        let image = ((try? await asset.loadTracks(withMediaType: .video)) ?? []).isEmpty == false
        let son = ((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty == false
        return (image, son)
    }

    private static func assembler(video: URL, audio: URL) async throws -> URL {
        let dossier = video.deletingLastPathComponent()
        let v = dossier.appendingPathComponent(UUID().uuidString + "-v.mp4")
        let a = dossier.appendingPathComponent(UUID().uuidString + "-a.mp4")
        try FileManager.default.copyItem(at: video, to: v)
        try FileManager.default.copyItem(at: audio, to: a)
        defer { try? FileManager.default.removeItem(at: v); try? FileManager.default.removeItem(at: a) }
        let assetV = AVURLAsset(url: v), assetA = AVURLAsset(url: a)
        guard let pisteV = try await assetV.loadTracks(withMediaType: .video).first,
              let pisteA = try await assetA.loadTracks(withMediaType: .audio).first else {
            throw ErreurTelechargement(message: "")
        }
        let duree = try await assetV.load(.duration)
        let dureeA = try await assetA.load(.duration)
        let composition = AVMutableComposition()
        let coupe = CMTimeRange(start: .zero, duration: CMTimeMinimum(duree, dureeA.isValid && dureeA > .zero ? dureeA : duree))
        guard let ecritV = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let ecritA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ErreurTelechargement(message: "")
        }
        try ecritV.insertTimeRange(CMTimeRange(start: .zero, duration: duree), of: pisteV, at: .zero)
        try ecritA.insertTimeRange(coupe, of: pisteA, at: .zero)
        ecritV.preferredTransform = try await pisteV.load(.preferredTransform)
        let sortie = dossier.appendingPathComponent(UUID().uuidString + "-fusion.mp4")
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw ErreurTelechargement(message: "")
        }
        export.outputURL = sortie
        export.outputFileType = .mp4
        await withCheckedContinuation { suite in export.exportAsynchronously { suite.resume() } }
        guard export.status == .completed else { throw export.error ?? ErreurTelechargement(message: "") }
        return sortie
    }
    #endif

    func annuler() {
        annule = true
        tache?.cancel()
    }
}

struct ErreurTelechargement: Error {
    let message: String
}

/// Délégué URLSession : suit la progression et range le fichier dès la fin du téléchargement.
final class DelegueTelechargement: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let surProgres: @Sendable (Double, Int64) -> Void
    private let surFin: @Sendable (Result<URL, Error>) -> Void
    private var termine = false
    private let verrou = NSLock()

    init(surProgres: @escaping @Sendable (Double, Int64) -> Void,
         surFin: @escaping @Sendable (Result<URL, Error>) -> Void) {
        self.surProgres = surProgres
        self.surFin = surFin
    }

    private func finir(_ resultat: Result<URL, Error>) {
        verrou.lock()
        defer { verrou.unlock() }
        guard !termine else { return }
        termine = true
        surFin(resultat)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let p = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        surProgres(p, totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finir(.failure(ErreurTelechargement(message: String(localized: "Le serveur a répondu avec l'erreur \(http.statusCode)."))))
            return
        }
        // Le fichier temporaire est supprimé dès le retour de cette méthode : on le déplace tout de suite.
        let dossier = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nom = Self.nomFichier(reponse: downloadTask.response, url: downloadTask.originalRequest?.url)
        do {
            try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
            let destination = dossier.appendingPathComponent(nom)
            try FileManager.default.moveItem(at: location, to: destination)
            finir(.success(destination))
        } catch {
            finir(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finir(.failure(error)) }
    }

    static func nomFichier(reponse: URLResponse?, url: URL?) -> String {
        var nom = reponse?.suggestedFilename ?? url?.lastPathComponent ?? "telechargement"
        if nom.isEmpty || nom == "/" { nom = "telechargement" }
        let connues: Set<String> = ["mp4", "mov", "m4v", "3gp", "mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac"]
        if !connues.contains((nom as NSString).pathExtension.lowercased()),
           let mime = reponse?.mimeType?.lowercased() {
            let extensions: [String: String] = [
                "video/mp4": "mp4", "video/quicktime": "mov", "video/x-m4v": "m4v", "video/3gpp": "3gp",
                "audio/mpeg": "mp3", "audio/mp3": "mp3", "audio/mp4": "m4a", "audio/x-m4a": "m4a",
                "audio/aac": "aac", "audio/wav": "wav", "audio/x-wav": "wav", "audio/flac": "flac"
            ]
            if let ext = extensions[mime] {
                nom = (nom as NSString).deletingPathExtension + "." + ext
            }
        }
        return nom
    }
}
