import Foundation

enum TypeMedia: String, Codable {
    case video, audio
}

struct Media: Identifiable, Codable, Hashable {
    var id = UUID()
    var nom: String
    /// Nom du fichier dans le dossier Documents de l'app
    var fichier: String
    var type: TypeMedia
    var taille: Int64
    var duree: Double
    var dateAjout = Date()
    var derniereLecture: Date?
    var position: Double = 0
    /// true si le média est rangé dans le dossier privé
    var prive: Bool? = nil
    /// Dossier (groupe) de l'accueil, nil = racine
    var dossier: UUID? = nil

    var estPrive: Bool { prive == true }
    var dureeTexte: String { Format.duree(duree) }
    var tailleTexte: String { Format.taille(taille) }
    var progression: Double { duree > 0 ? min(position / duree, 1) : 0 }
}

/// Dossier créé par l'utilisateur sur l'accueil (« Nouveau dossier »).
struct Dossier: Identifiable, Codable, Hashable {
    var id = UUID()
    var nom: String
    var dateCreation = Date()

    static let longueurMax = 20
}

enum ModeLectureAuto: String, CaseIterable, Identifiable {
    case arreter, repeterUn, enchainer, boucle, retourListe

    var id: String { rawValue }

    var titre: String {
        switch self {
        case .arreter: String(localized: "Arrêter après le média")
        case .repeterUn: String(localized: "Répéter le média")
        case .enchainer: String(localized: "Lire le suivant")
        case .boucle: String(localized: "Lire la liste en boucle")
        case .retourListe: String(localized: "Revenir à la liste")
        }
    }
}

enum VueAccueil: String, CaseIterable, Identifiable {
    case grille, liste
    var id: String { rawValue }
    var titre: String { self == .grille ? String(localized: "Vue en grille") : String(localized: "Vue en liste") }
    var icone: String { self == .grille ? "square.grid.2x2" : "list.bullet" }
}

enum TriMedias: String, CaseIterable, Identifiable {
    case nom, date, taille
    var id: String { rawValue }

    var titre: String {
        switch self {
        case .nom: String(localized: "Nom")
        case .date: String(localized: "Date d'ajout")
        case .taille: String(localized: "Taille du fichier")
        }
    }

    func trier(_ liste: [Media], croissant: Bool) -> [Media] {
        let triee: [Media]
        switch self {
        case .nom:
            triee = liste.sorted { $0.nom.localizedStandardCompare($1.nom) == .orderedAscending }
        case .date:
            triee = liste.sorted { $0.dateAjout < $1.dateAjout }
        case .taille:
            triee = liste.sorted { $0.taille < $1.taille }
        }
        return croissant ? triee : triee.reversed()
    }
}

enum ThemeApp: String, CaseIterable, Identifiable {
    case systeme, clair, sombre
    var id: String { rawValue }

    var titre: String {
        switch self {
        case .systeme: String(localized: "Automatique (système)")
        case .clair: String(localized: "Clair")
        case .sombre: String(localized: "Sombre")
        }
    }
}

/// Clés des réglages (UserDefaults / @AppStorage)
enum Cle {
    static let modeLectureAuto = "modeLectureAuto"
    static let reprendreLecture = "reprendreLecture"
    static let pauseArrierePlan = "pauseArrierePlan"
    static let imageDansImage = "imageDansImage"
    static let rotationPaysage = "rotationPaysage"
    static let airplay = "airplay"
    static let gesteLuminosite = "gesteLuminosite"
    static let gesteVolume = "gesteVolume"
    static let verrouApp = "verrouApp"
    static let theme = "theme"
    static let vueAccueil = "vueAccueil"
    static let triAccueil = "triAccueil"
    static let triCroissant = "triCroissant"

    static func booleen(_ cle: String, defaut: Bool) -> Bool {
        UserDefaults.standard.object(forKey: cle) as? Bool ?? defaut
    }
}
