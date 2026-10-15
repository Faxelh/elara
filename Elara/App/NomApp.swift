import SwiftUI

/// Nom de l'application.
/// - Dans Elara : modifiable à tout moment (Réglages › À propos), appliqué tout de suite.
/// - Sous l'icône : fixé à la compilation (fichier NOM du dépôt GitHub), appliqué à la mise à jour suivante.
enum NomApp {
    static let cle = "nomApp"
    static let depot = "Faxelh/elara"

    /// Nom sous l'icône pour cette version installée.
    static var nomIcone: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Elara"
    }

    /// Page GitHub pour modifier le fichier NOM (le nom sous l'icône change à la compilation suivante).
    static let lienModifier = URL(string: "https://github.com/\(depot)/edit/main/NOM")!

    static func propre(_ texte: String) -> String {
        String(texte.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
    }
}

/// Champ « Nom de l'application » (À propos, et proposé après chaque mise à jour).
struct ChampNomApp: View {
    @AppStorage(NomApp.cle) private var nom = ""
    @State private var brouillon = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(NomApp.nomIcone, text: $brouillon)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit { enregistrer() }
            HStack {
                Button("Enregistrer") { enregistrer() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(NomApp.propre(brouillon) == nom)
                #if PERSO
                Spacer()
                Link(destination: NomApp.lienModifier) {
                    Label("Nom sous l'icône (GitHub)", systemImage: "square.and.pencil")
                        .font(.footnote)
                }
                #endif
            }
            #if PERSO
            Text("Le nom change tout de suite dans Elara. Pour l'icône de l'écran d'accueil (actuellement « \(NomApp.nomIcone) »), écrivez le même nom dans le fichier NOM sur GitHub : il s'appliquera à la prochaine mise à jour.")
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif
        }
        .onAppear { brouillon = nom.isEmpty ? NomApp.nomIcone : nom }
    }

    private func enregistrer() {
        let propre = NomApp.propre(brouillon)
        nom = propre.isEmpty || propre == NomApp.nomIcone ? "" : propre
        brouillon = propre.isEmpty ? NomApp.nomIcone : propre
    }
}

#if PERSO
/// Après une mise à jour : « Elara a été mise à jour » + proposition de changer le nom.
struct ModifNomApresMiseAJour: ViewModifier {
    @AppStorage("nomApp.versionVue") private var versionVue = ""
    @State private var afficher = false

    private var versionActuelle: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Première installation : rien à proposer. Nouvelle version : on propose.
                if versionVue.isEmpty { versionVue = versionActuelle }
                else if versionVue != versionActuelle { afficher = true }
            }
            .sheet(isPresented: $afficher, onDismiss: { versionVue = versionActuelle }) {
                NavigationStack {
                    Form {
                        Section {
                            Label("Mise à jour installée", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .font(.headline)
                        }
                        Section("Nom de l'application") {
                            ChampNomApp()
                        }
                    }
                    .navigationTitle("Nouvelle version")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("OK") { afficher = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
    }
}
#endif
