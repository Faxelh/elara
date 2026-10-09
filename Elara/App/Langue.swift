import Foundation
import ObjectiveC

/// Change la langue d'Elara immédiatement, sans redémarrer l'app.
/// Les textes sont lus dans le dossier .lproj de la langue choisie.
enum Langue {
    /// Code de la langue affichée (fr, en, ru, es).
    private(set) static var code = "fr"

    static var locale: Locale { Locale(identifier: code) }

    /// `choix` : code de langue, ou nil pour suivre la langue de l'iPhone.
    static func activer(_ choix: String?) {
        if object_getClass(Bundle.main) != BundleLangue.self {
            object_setClass(Bundle.main, BundleLangue.self)
        }
        let disponibles = Bundle.main.localizations.filter { $0 != "Base" }
        let voulu = choix ?? Bundle.preferredLocalizations(
            from: disponibles,
            forPreferences: Locale.preferredLanguages
        ).first ?? "fr"
        code = disponibles.contains(voulu) ? voulu : "fr"
        if let chemin = Bundle.main.path(forResource: code, ofType: "lproj") {
            BundleLangue.textes = Bundle(path: chemin)
        } else {
            BundleLangue.textes = nil
        }
    }
}

/// Remplace Bundle.main pour renvoyer les textes de la langue choisie.
final class BundleLangue: Bundle, @unchecked Sendable {
    static var textes: Bundle?

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let textes = Self.textes {
            return textes.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
