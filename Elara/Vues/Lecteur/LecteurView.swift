import SwiftUI
import AVKit

struct LecteurView: View {
    @Environment(LecteurController.self) private var lecteur
    @Environment(\.scenePhase) private var scenePhase

    private var estVideo: Bool { lecteur.mediaActuel?.type == .video }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    lecteur.fermer()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3.bold())
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Fermer le lecteur")

                Spacer()
                Text(lecteur.mediaActuel?.nom ?? "")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()

                if estVideo && lecteur.file.count > 1 {
                    Button { lecteur.suivant() } label: {
                        Image(systemName: "forward.end.fill").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Vidéo suivante")
                }
                SelecteurAirPlay(couleur: estVideo ? .white : .label)
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 8)

            if estVideo {
                VideoAVKit(player: lecteur.player)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                AudioLecteurView()
            }
        }
        .foregroundStyle(estVideo ? Color.white : Color.primary)
        .background((estVideo ? Color.black : Color(.systemBackground)).ignoresSafeArea())
        .overlay {
            // Cache un média privé dans le sélecteur d'apps
            if lecteur.mediaActuel?.estPrive == true && scenePhase != .active {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            }
        }
    }
}

/// Lecteur vidéo natif d'Apple (contrôles, AirPlay, image dans l'image).
struct VideoAVKit: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.updatesNowPlayingInfoCenter = false
        vc.entersFullScreenWhenPlaybackBegins = false
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}

/// Bouton AirPlay pour diffuser vers une TV ou une enceinte.
struct SelecteurAirPlay: UIViewRepresentable {
    var couleur: UIColor

    func makeUIView(context: Context) -> AVRoutePickerView {
        let vue = AVRoutePickerView()
        vue.prioritizesVideoDevices = true
        vue.tintColor = couleur
        return vue
    }

    func updateUIView(_ vue: AVRoutePickerView, context: Context) {
        vue.tintColor = couleur
    }
}
