import Foundation
import Observation
import SwiftUI
import UIKit

/// Nouvelle version publiée sur GitHub (Releases, étiquette ios-NUMÉRO).
struct VersionDisponible: Identifiable, Equatable {
    let numero: Int
    /// Version affichée, ex. « 2026.2.3 ».
    let version: String
    let lienIPA: URL
    let notes: String
    var id: Int { numero }
}

/// Mises à jour d'Elara (version perso) : chaque compilation GitHub publie l'IPA.
/// Elara compare ce numéro au sien et propose la mise à jour :
/// avec SideStore / AltStore elle s'installe directement, sinon on télécharge l'IPA pour Sideloadly.
@MainActor
@Observable
final class MiseAJour {
    static let partage = MiseAJour()
    static let depot = "Faxelh/elara"
    static let source = "https://github.com/\(depot)/releases/download/ios-source/source.json"

    private(set) var disponible: VersionDisponible?
    private(set) var recherche = false
    private(set) var erreur = false

    var versionActuelle: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    var texteVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// Au plus une fois par jour, sauf si `forcer`.
    @discardableResult
    func verifier(forcer: Bool = false) async -> VersionDisponible? {
        let cle = "maj.derniere"
        let derniere = UserDefaults.standard.double(forKey: cle)
        if !forcer, Date().timeIntervalSince1970 - derniere < 24 * 3600 { return disponible }
        recherche = true
        erreur = false
        defer { recherche = false }
        guard let url = URL(string: "https://api.github.com/repos/\(Self.depot)/releases?per_page=20") else { return nil }
        var requete = URLRequest(url: url, timeoutInterval: 15)
        requete.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (donnees, reponse) = try await URLSession.shared.data(for: requete)
            guard (reponse as? HTTPURLResponse)?.statusCode == 200,
                  let liste = try JSONSerialization.jsonObject(with: donnees) as? [[String: Any]] else {
                erreur = true
                return nil
            }
            var meilleure: VersionDisponible?
            for release in liste {
                guard let tag = release["tag_name"] as? String, tag.hasPrefix("ios-"),
                      let numero = Int(tag.dropFirst(4)),
                      let actifs = release["assets"] as? [[String: Any]],
                      let ipa = actifs.first(where: { ($0["name"] as? String)?.hasSuffix(".ipa") == true }),
                      let lien = (ipa["browser_download_url"] as? String).flatMap(URL.init(string:)) else { continue }
                if numero > (meilleure?.numero ?? 0) {
                    let nom = (release["name"] as? String ?? "").split(separator: " ").last.map(String.init) ?? "\(numero)"
                    meilleure = VersionDisponible(numero: numero, version: nom, lienIPA: lien, notes: release["body"] as? String ?? "")
                }
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cle)
            disponible = meilleure.flatMap { $0.numero > versionActuelle ? $0 : nil }
            return disponible
        } catch {
            erreur = true
            return nil
        }
    }

    /// Vrai si ni SideStore ni AltStore ne sont installés sur l'iPhone.
    var sideStoreAbsent = false

    /// Ouvre SideStore (ou AltStore) sur la source d'Elara : l'app s'y met à jour toute seule ensuite.
    func ouvrirDansSideStore() {
        let encodee = Self.source.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? Self.source
        let sidestore = URL(string: "sidestore://source?url=\(encodee)")!
        let altstore = URL(string: "altstore://source?url=\(encodee)")!
        sideStoreAbsent = false
        UIApplication.shared.open(sidestore) { ok in
            guard !ok else { return }
            UIApplication.shared.open(altstore) { ok2 in
                Task { @MainActor in MiseAJour.partage.sideStoreAbsent = !ok2 }
            }
        }
    }

    // MARK: - Téléchargement de l'IPA (dans Elara : un lien GitHub ouvrirait l'app GitHub)

    private(set) var ipaEnCours = false
    private(set) var ipaProgression: Double = 0
    private(set) var fichierIPA: URL?
    private(set) var erreurIPA = false

    func telechargerIPA(_ version: VersionDisponible) async {
        guard !ipaEnCours else { return }
        ipaEnCours = true
        ipaProgression = 0
        erreurIPA = false
        fichierIPA = nil
        defer { ipaEnCours = false }
        do {
            let (flux, reponse) = try await URLSession.shared.bytes(from: version.lienIPA)
            guard (reponse as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else {
                erreurIPA = true
                return
            }
            let total = max(reponse.expectedContentLength, 1)
            let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("maj", isDirectory: true)
            try? FileManager.default.removeItem(at: dossier)
            try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
            let cible = dossier.appendingPathComponent("Elara-\(version.version).ipa")
            FileManager.default.createFile(atPath: cible.path, contents: nil)
            let sortie = try FileHandle(forWritingTo: cible)
            defer { try? sortie.close() }
            var tampon = Data()
            tampon.reserveCapacity(1 << 20)
            var recus: Int64 = 0
            for try await octet in flux {
                tampon.append(octet)
                if tampon.count >= 1 << 20 {
                    try sortie.write(contentsOf: tampon)
                    recus += Int64(tampon.count)
                    tampon.removeAll(keepingCapacity: true)
                    ipaProgression = min(Double(recus) / Double(total), 1)
                }
            }
            if !tampon.isEmpty { try sortie.write(contentsOf: tampon) }
            ipaProgression = 1
            fichierIPA = cible
        } catch {
            erreurIPA = true
        }
    }
}

#if PERSO
/// Proposition de mise à jour (au démarrage ou depuis Réglages).
struct ModifMiseAJour: ViewModifier {
    @State private var maj = MiseAJour.partage
    @State private var proposee: VersionDisponible?
    @State private var feuille = false
    var auDemarrage = true

    func body(content: Content) -> some View {
        content
            .task {
                guard auDemarrage else { return }
                if let v = await maj.verifier(),
                   UserDefaults.standard.integer(forKey: "maj.ignoree") != v.numero {
                    proposee = v
                }
            }
            .alert(
                "Nouvelle version disponible",
                isPresented: Binding(get: { proposee != nil }, set: { if !$0 { proposee = nil } }),
                presenting: proposee
            ) { v in
                Button("Mettre à jour avec SideStore") { maj.ouvrirDansSideStore() }
                Button("Télécharger l'IPA (Sideloadly)") { feuille = true }
                Button("Plus tard", role: .cancel) {
                    UserDefaults.standard.set(v.numero, forKey: "maj.ignoree")
                }
            } message: { v in
                Text("Elara \(v.version) est disponible (vous avez la \(maj.texteVersion)).\n\n\(String(v.notes.prefix(500)))")
            }
            .sheet(isPresented: $feuille) {
                NavigationStack {
                    MiseAJourView()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { feuille = false } } }
                }
            }
    }
}
#endif
