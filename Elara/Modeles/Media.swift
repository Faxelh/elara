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

    var dureeTexte: String { Format.duree(duree) }
    var tailleTexte: String { Format.taille(taille) }
    var progression: Double { duree > 0 ? min(position / duree, 1) : 0 }
}

enum ModeLectureAuto: String, CaseIterable, Identifiable {
    case arreter, repeterUn, enchainer, boucle, retourListe

    var id: String { rawValue }

    var titre: String {
        switch self {
        case .arreter: "Arrêter après le média"
        case .repeterUn: "Répéter le média"
        case .enchainer: "Lire le suivant"
        case .boucle: "Lire la liste en boucle"
        case .retourListe: "Revenir à la liste"
        }
    }
}
