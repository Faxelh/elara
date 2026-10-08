import SwiftUI

struct TransfertView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Transfert Wi‑Fi",
                systemImage: "wifi",
                description: Text("Envoyez vos vidéos et musiques vers un autre appareil sur le même réseau Wi‑Fi. Disponible dans une prochaine version.")
            )
            .navigationTitle("Transfert")
        }
    }
}
