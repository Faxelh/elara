import SwiftUI

struct CompresserView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Compression vidéo",
                systemImage: "rectangle.compress.vertical",
                description: Text("Réduisez la taille de vos vidéos pour libérer de l'espace. Disponible dans une prochaine version.")
            )
            .navigationTitle("Compresser")
        }
    }
}
