import Foundation
import LocalAuthentication
import Observation

/// Verrou du dossier privé (Face ID, Touch ID ou code de l'iPhone).
@MainActor
@Observable
final class Coffre {
    private(set) var estDeverrouille = false
    var erreur: String?

    var nomBiometrie: String {
        let contexte = LAContext()
        _ = contexte.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch contexte.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return String(localized: "le code")
        }
    }

    func deverrouiller(raison: String = String(localized: "Déverrouiller le dossier privé")) async {
        let contexte = LAContext()
        contexte.localizedCancelTitle = String(localized: "Annuler")
        contexte.localizedFallbackTitle = String(localized: "Utiliser le code")

        var probleme: NSError?
        guard contexte.canEvaluatePolicy(.deviceOwnerAuthentication, error: &probleme) else {
            erreur = String(localized: "Activez Face ID ou un code dans les Réglages de l'iPhone pour protéger le dossier privé.")
            return
        }
        do {
            let reussi = try await contexte.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: raison
            )
            estDeverrouille = reussi
            erreur = nil
        } catch let e as LAError where e.code == .userCancel || e.code == .appCancel || e.code == .systemCancel {
            erreur = nil
        } catch {
            erreur = String(localized: "Le déverrouillage a échoué. Réessayez.")
        }
    }

    func verrouiller() {
        estDeverrouille = false
    }
}
