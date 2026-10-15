import SwiftUI

/// Historique des nouveautés et correctifs (fichier Nouveautes.txt livré avec l'app).
/// Format : « # titre » (date de la mise à jour) puis une ligne « - … » par changement.
enum Nouveautes {
    struct Section: Identifiable {
        let id = UUID()
        let titre: String
        let lignes: [String]
    }

    static let toutes: [Section] = {
        guard let url = Bundle.main.url(forResource: "Nouveautes", withExtension: "txt"),
              let texte = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var sections: [Section] = []
        var titre: String?
        var lignes: [String] = []
        func fermer() { if let titre { sections.append(Section(titre: titre, lignes: lignes)) } }
        for brute in texte.components(separatedBy: .newlines) {
            let l = brute.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("# ") {
                fermer()
                titre = String(l.dropFirst(2))
                lignes = []
            } else if l.hasPrefix("- ") {
                lignes.append(String(l.dropFirst(2)))
            }
        }
        fermer()
        return sections
    }()

    static var derniere: Section? { toutes.first }
}

/// Liste des changements d'une mise à jour.
struct ListeChangements: View {
    let section: Nouveautes.Section
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(section.lignes.enumerated()), id: \.offset) { _, ligne in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.accent)
                    Text(ligne).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Tout l'historique (Réglages › À propos › Nouveautés).
struct NouveautesView: View {
    var body: some View {
        List {
            if Nouveautes.toutes.isEmpty {
                Text("Aucune information.").foregroundStyle(.secondary)
            }
            ForEach(Nouveautes.toutes) { section in
                Section(section.titre) {
                    ListeChangements(section: section).padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Nouveautés")
        .navigationBarTitleDisplayMode(.inline)
    }
}
