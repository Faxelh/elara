import Foundation
import MultipeerConnectivity
import UIKit
import Observation

/// Échange de fichiers entre iPhone à proximité (Wi‑Fi / Bluetooth) avec MultipeerConnectivity.
/// Les deux appareils doivent avoir Elara ouvert sur l'onglet Transfert.
@MainActor
@Observable
final class Transfert: NSObject {
    private(set) var appareils: [MCPeerID] = []
    private(set) var connectes: [MCPeerID] = []
    private(set) var enConnexion: Set<MCPeerID> = []
    private(set) var actif = false
    private(set) var progression: Double?
    var message: String?
    var invitation: Invitation?

    struct Invitation: Identifiable {
        let id = UUID()
        let appareil: MCPeerID
        let repondre: (Bool, MCSession?) -> Void
    }

    static let service = "elara-tr"

    @ObservationIgnored let monAppareil: MCPeerID
    @ObservationIgnored private var session: MCSession!
    @ObservationIgnored private var annonceur: MCNearbyServiceAdvertiser!
    @ObservationIgnored private var explorateur: MCNearbyServiceBrowser!
    @ObservationIgnored weak var bibliotheque: Bibliotheque?

    override init() {
        monAppareil = MCPeerID(displayName: UIDevice.current.name)
        super.init()
        session = MCSession(peer: monAppareil, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        annonceur = MCNearbyServiceAdvertiser(peer: monAppareil, discoveryInfo: nil, serviceType: Self.service)
        annonceur.delegate = self
        explorateur = MCNearbyServiceBrowser(peer: monAppareil, serviceType: Self.service)
        explorateur.delegate = self
    }

    func demarrer() {
        guard !actif else { return }
        actif = true
        annonceur.startAdvertisingPeer()
        explorateur.startBrowsingForPeers()
    }

    func arreter() {
        guard actif else { return }
        actif = false
        annonceur.stopAdvertisingPeer()
        explorateur.stopBrowsingForPeers()
        appareils.removeAll { !connectes.contains($0) }
    }

    func estConnecte(_ appareil: MCPeerID) -> Bool { connectes.contains(appareil) }

    func inviter(_ appareil: MCPeerID) {
        guard !estConnecte(appareil) else { return }
        enConnexion.insert(appareil)
        explorateur.invitePeer(appareil, to: session, withContext: nil, timeout: 30)
    }

    func accepter(_ invitation: Invitation, _ accepte: Bool) {
        invitation.repondre(accepte, accepte ? session : nil)
        if accepte { enConnexion.insert(invitation.appareil) }
        self.invitation = nil
    }

    /// Envoie les médias un par un à l'appareil choisi.
    func envoyer(_ medias: [Media], a appareil: MCPeerID) async {
        guard let bib = bibliotheque, estConnecte(appareil) else { return }
        for (i, media) in medias.enumerated() {
            let url = bib.url(de: media)
            let nom = media.nom + "." + url.pathExtension
            message = String(localized: "Envoi de « \(media.nom) » (\(i + 1)/\(medias.count))…")
            progression = 0
            let reussi: Bool = await withCheckedContinuation { suite in
                let suivi = session.sendResource(at: url, withName: nom, toPeer: appareil) { erreur in
                    suite.resume(returning: erreur == nil)
                }
                if let suivi { surveiller(suivi) }
            }
            if !reussi {
                message = String(localized: "L'envoi de « \(media.nom) » a échoué.")
                progression = nil
                return
            }
        }
        progression = nil
        message = medias.count > 1 ? String(localized: "\(medias.count) fichiers envoyés.") : String(localized: "Fichier envoyé.")
    }

    private func surveiller(_ suivi: Progress) {
        Task { [weak self] in
            while !suivi.isFinished && !suivi.isCancelled {
                self?.progression = suivi.fractionCompleted
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    // Appelés depuis les délégués (hors du fil principal)

    fileprivate func changement(_ appareil: MCPeerID, _ etat: MCSessionState) {
        switch etat {
        case .connected:
            enConnexion.remove(appareil)
            if !connectes.contains(appareil) { connectes.append(appareil) }
            if !appareils.contains(appareil) { appareils.append(appareil) }
        case .connecting:
            enConnexion.insert(appareil)
        case .notConnected:
            enConnexion.remove(appareil)
            connectes.removeAll { $0 == appareil }
        @unknown default:
            break
        }
    }

    fileprivate func trouve(_ appareil: MCPeerID) {
        if appareil != monAppareil && !appareils.contains(appareil) { appareils.append(appareil) }
    }

    fileprivate func perdu(_ appareil: MCPeerID) {
        if !connectes.contains(appareil) { appareils.removeAll { $0 == appareil } }
    }

    fileprivate func recu(_ fichier: URL, de appareil: MCPeerID) async {
        message = String(localized: "Réception de « \((fichier.lastPathComponent as NSString).deletingPathExtension) »…")
        if await bibliotheque?.importer(depuis: fichier, deplacer: true) != nil {
            message = String(localized: "Fichier reçu de \(appareil.displayName) et ajouté à l'accueil.")
        } else {
            message = String(localized: "Le fichier reçu n'est pas une vidéo ou une musique prise en charge.")
        }
        progression = nil
    }
}

// MARK: - Délégués

extension Transfert: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in self.changement(peerID, state) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream,
                             withName streamName: String, fromPeer peerID: MCPeerID) {}

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, with progress: Progress) {
        Task { @MainActor in
            self.message = String(localized: "Réception de « \((resourceName as NSString).deletingPathExtension) »…")
            self.progression = 0
            self.surveiller(progress)
        }
    }

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        guard error == nil, let localURL else {
            Task { @MainActor in
                self.message = String(localized: "La réception a échoué.")
                self.progression = nil
            }
            return
        }
        // Le fichier temporaire disparaît au retour de cette méthode : on le déplace tout de suite.
        let dossier = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = dossier.appendingPathComponent((resourceName as NSString).lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: localURL, to: destination)
        } catch {
            return
        }
        Task { @MainActor in await self.recu(destination, de: peerID) }
    }
}

extension Transfert: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            self.invitation = Invitation(appareil: peerID, repondre: invitationHandler)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            self.message = String(localized: "Impossible d'être visible. Vérifiez le Wi‑Fi, le Bluetooth et l'autorisation « Réseau local ».")
        }
    }
}

extension Transfert: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in self.trouve(peerID) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in self.perdu(peerID) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            self.message = String(localized: "Recherche impossible. Vérifiez le Wi‑Fi, le Bluetooth et l'autorisation « Réseau local ».")
        }
    }
}
