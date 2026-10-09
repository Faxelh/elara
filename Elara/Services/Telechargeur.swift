import Foundation
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
            }
            #endif
            if Task.isCancelled || annule { throw URLError(.cancelled) }
            let lienFinal = url
            let recu: URL = try await withCheckedThrowingContinuation { suite in
                let delegue = DelegueTelechargement(
                    surProgres: { [weak self] p, o in
                        Task { @MainActor in
                            self?.progression = p
                            self?.octetsRecus = o
                        }
                    },
                    surFin: { resultat in suite.resume(with: resultat) }
                )
                let session = URLSession(configuration: .default, delegate: delegue, delegateQueue: nil)
                let t = session.downloadTask(with: lienFinal)
                tache = t
                t.resume()
                session.finishTasksAndInvalidate()
            }
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
