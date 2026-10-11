import Foundation
import Network
import UIKit
import Observation

/// Petit serveur web local : depuis un ordinateur sur le même Wi‑Fi, on ouvre
/// http://<adresse-iphone>:8080 pour envoyer ou récupérer des vidéos et musiques.
@MainActor
@Observable
final class ServeurWifi {
    private(set) var actif = false
    private(set) var adresse: String?
    private(set) var dernierFichier: String?
    var message: String?

    let port: UInt16 = 8080
    @ObservationIgnored private var ecouteur: NWListener?
    @ObservationIgnored weak var bibliotheque: Bibliotheque?

    func demarrer() {
        guard !actif else { return }
        guard let ip = Self.adresseIP() else {
            message = String(localized: "Connectez l'iPhone à un réseau Wi‑Fi pour utiliser le transfert depuis un ordinateur.")
            return
        }
        do {
            let parametres = NWParameters.tcp
            parametres.allowLocalEndpointReuse = true
            let nouvel = try NWListener(using: parametres, on: NWEndpoint.Port(rawValue: port)!)
            nouvel.newConnectionHandler = { [weak self] connexion in
                connexion.start(queue: .global(qos: .userInitiated))
                Task { await self?.traiter(connexion) }
            }
            nouvel.stateUpdateHandler = { [weak self] etat in
                if case .failed = etat {
                    Task { @MainActor in
                        self?.message = String(localized: "Le serveur s'est arrêté. Réessayez.")
                        self?.arreter()
                    }
                }
            }
            nouvel.start(queue: .global(qos: .userInitiated))
            ecouteur = nouvel
            adresse = "http://\(ip):\(port)"
            actif = true
            message = nil
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            message = String(localized: "Impossible de démarrer le transfert Wi‑Fi.")
        }
    }

    func arreter() {
        ecouteur?.cancel()
        ecouteur = nil
        actif = false
        adresse = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Accès à la bibliothèque (fil principal)

    private func listeJSON() -> Data {
        let liste: [[String: Any]] = (bibliotheque?.medias ?? []).map { m in
            [
                "id": m.id.uuidString,
                "nom": m.nom,
                "taille": Format.taille(m.taille),
                "duree": m.dureeTexte,
                "type": m.type.rawValue
            ]
        }
        return (try? JSONSerialization.data(withJSONObject: liste)) ?? Data("[]".utf8)
    }

    private func fichier(_ id: UUID) -> (URL, String)? {
        guard let bib = bibliotheque,
              let media = bib.medias.first(where: { $0.id == id }) else { return nil }
        let url = bib.url(de: media)
        return (url, media.nom + "." + url.pathExtension)
    }

    private func importer(_ url: URL) async -> Bool {
        let ok = await bibliotheque?.importer(depuis: url, deplacer: true) != nil
        if ok { dernierFichier = (url.lastPathComponent as NSString).deletingPathExtension }
        return ok
    }

    // MARK: - HTTP

    nonisolated private func traiter(_ c: NWConnection) async {
        defer { c.cancel() }
        let separateur = Data("\r\n\r\n".utf8)
        var tampon = Data()
        while tampon.range(of: separateur) == nil {
            guard tampon.count < 65_536, let morceau = await c.recevoir(max: 65_536) else { return }
            tampon.append(morceau)
        }
        guard let fin = tampon.range(of: separateur),
              let entete = String(data: tampon[..<fin.lowerBound], encoding: .utf8) else { return }
        let corps = tampon[fin.upperBound...]

        let lignes = entete.components(separatedBy: "\r\n")
        let premiere = lignes.first?.split(separator: " ").map(String.init) ?? []
        guard premiere.count >= 2 else { return }
        let methode = premiere[0]
        let chemin = premiere[1]
        var champs: [String: String] = [:]
        for ligne in lignes.dropFirst() {
            if let deuxPoints = ligne.firstIndex(of: ":") {
                let cle = ligne[..<deuxPoints].trimmingCharacters(in: .whitespaces).lowercased()
                let valeur = ligne[ligne.index(after: deuxPoints)...].trimmingCharacters(in: .whitespaces)
                champs[cle] = valeur
            }
        }
        let composants = URLComponents(string: chemin)
        let route = composants?.path ?? chemin

        switch (methode, route) {
        case ("GET", "/"):
            await repondre(c, type: "text/html; charset=utf-8", corps: Data(PageWifi.html.utf8))
        case ("GET", "/liste"):
            let json = await listeJSON()
            await repondre(c, type: "application/json; charset=utf-8", corps: json)
        case ("PUT", "/envoi"), ("POST", "/envoi"):
            let nom = composants?.queryItems?.first(where: { $0.name == "nom" })?.value ?? "fichier"
            let longueur = Int(champs["content-length"] ?? "") ?? 0
            await recevoirFichier(c, nom: nom, longueur: longueur, debut: Data(corps))
        case ("GET", _) where route.hasPrefix("/fichier/"):
            let texteID = String(route.dropFirst("/fichier/".count))
            if let id = UUID(uuidString: texteID), let trouve = await fichier(id) {
                await envoyerFichier(c, url: trouve.0, nom: trouve.1)
            } else {
                await repondre(c, statut: "404 Not Found", type: "text/plain", corps: Data("Introuvable".utf8))
            }
        default:
            await repondre(c, statut: "404 Not Found", type: "text/plain", corps: Data("Introuvable".utf8))
        }
    }

    nonisolated private func recevoirFichier(_ c: NWConnection, nom: String, longueur: Int, debut: Data) async {
        let extensions: Set<String> = ["mp4", "mov", "m4v", "3gp", "mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac"]
        let propre = (nom as NSString).lastPathComponent.replacingOccurrences(of: "/", with: "_")
        guard extensions.contains((propre as NSString).pathExtension.lowercased()), longueur > 0 else {
            await repondre(c, statut: "415 Unsupported Media Type", type: "text/plain",
                           corps: Data("Format non pris en charge".utf8))
            return
        }
        let dossier = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = dossier.appendingPathComponent(propre)
        do {
            try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            let sortie = try FileHandle(forWritingTo: destination)
            var recu = 0
            if !debut.isEmpty {
                try sortie.write(contentsOf: debut)
                recu += debut.count
            }
            while recu < longueur {
                guard let morceau = await c.recevoir(max: 1 << 20) else { break }
                try sortie.write(contentsOf: morceau)
                recu += morceau.count
            }
            try sortie.close()
            guard recu >= longueur else {
                try? FileManager.default.removeItem(at: dossier)
                return
            }
        } catch {
            await repondre(c, statut: "500 Internal Server Error", type: "text/plain", corps: Data("Erreur".utf8))
            return
        }
        let ok = await importer(destination)
        await repondre(c, statut: ok ? "200 OK" : "500 Internal Server Error",
                       type: "application/json", corps: Data(ok ? "{\"ok\":true}".utf8 : "{\"ok\":false}".utf8))
    }

    nonisolated private func envoyerFichier(_ c: NWConnection, url: URL, nom: String) async {
        guard let entree = try? FileHandle(forReadingFrom: url) else {
            await repondre(c, statut: "404 Not Found", type: "text/plain", corps: Data())
            return
        }
        defer { try? entree.close() }
        let taille = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        let nomEncode = nom.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "fichier"
        let entete = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: application/octet-stream\r\n"
            + "Content-Length: \(taille)\r\n"
            + "Content-Disposition: attachment; filename*=UTF-8''\(nomEncode)\r\n"
            + "Connection: close\r\n\r\n"
        guard await c.envoyer(Data(entete.utf8)) else { return }
        while true {
            guard let morceau = try? entree.read(upToCount: 1 << 20), !morceau.isEmpty else { break }
            guard await c.envoyer(morceau) else { return }
        }
        _ = await c.envoyer(Data(), fin: true)
    }

    nonisolated private func repondre(_ c: NWConnection, statut: String = "200 OK", type: String, corps: Data) async {
        let entete = "HTTP/1.1 \(statut)\r\nContent-Type: \(type)\r\nContent-Length: \(corps.count)\r\n"
            + "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        var donnees = Data(entete.utf8)
        donnees.append(corps)
        _ = await c.envoyer(donnees, fin: true)
    }

    // MARK: - Adresse IP Wi‑Fi

    nonisolated static func adresseIP() -> String? {
        var adresse: String?
        var liste: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&liste) == 0, let premier = liste else { return nil }
        defer { freeifaddrs(liste) }
        for pointeur in sequence(first: premier, next: { $0.pointee.ifa_next }) {
            let interface = pointeur.pointee
            guard let sa = interface.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  String(cString: interface.ifa_name) == "en0" else { continue }
            var hote = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &hote, socklen_t(hote.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                adresse = String(cString: hote)
            }
        }
        return adresse
    }
}

// MARK: - Aides NWConnection

extension NWConnection {
    /// Renvoie nil quand la connexion est terminée ou en erreur.
    func recevoir(max: Int) async -> Data? {
        await withCheckedContinuation { suite in
            receive(minimumIncompleteLength: 1, maximumLength: max) { donnees, _, termine, erreur in
                if let donnees, !donnees.isEmpty {
                    suite.resume(returning: donnees)
                } else if termine || erreur != nil {
                    suite.resume(returning: nil)
                } else {
                    suite.resume(returning: Data())
                }
            }
        }
    }

    func envoyer(_ donnees: Data, fin: Bool = false) async -> Bool {
        await withCheckedContinuation { suite in
            send(content: donnees.isEmpty ? nil : donnees, isComplete: fin, completion: .contentProcessed { erreur in
                suite.resume(returning: erreur == nil)
            })
        }
    }
}
