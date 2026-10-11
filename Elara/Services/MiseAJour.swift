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

    /// Ouvre SideStore (ou AltStore) sur la source d'Elara : l'app s'y met à jour toute seule ensuite.
    func ouvrirDansSideStore() {
        let encodee = Self.source.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? Self.source
        let sidestore = URL(string: "sidestore://source?url=\(encodee)")!
        let altstore = URL(string: "altstore://source?url=\(encodee)")!
        UIApplication.shared.open(sidestore) { ok in
            if !ok { UIApplication.shared.open(altstore) }
        }
    }

    func telechargerIPA(_ version: VersionDisponible) {
        UIApplication.shared.open(version.lienIPA)
    }
}

#if PERSO
/// Proposition de mise à jour (au démarrage ou depuis Réglages).
struct ModifMiseAJour: ViewModifier {
    @State private var maj = MiseAJour.partage
    @State private var proposee: VersionDisponible?
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
                Button("Télécharger l'IPA (Sideloadly)") { maj.telechargerIPA(v) }
                Button("Plus tard", role: .cancel) {
                    UserDefaults.standard.set(v.numero, forKey: "maj.ignoree")
                }
            } message: { v in
                Text("Elara \(v.version) est disponible (vous avez la \(maj.texteVersion)).")
            }
    }
}
#endif
