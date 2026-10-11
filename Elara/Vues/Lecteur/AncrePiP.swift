import SwiftUI
import AVKit

/// Vue invisible qui reste toujours dans l'app : elle porte l'image dans l'image.
/// Ainsi, la fenêtre flottante continue même quand l'écran du lecteur se ferme,
/// et on retrouve l'accueil (ou n'importe quel onglet) derrière.
struct AncrePiP: UIViewRepresentable {
    @Environment(LecteurController.self) private var lecteur

    func makeCoordinator() -> Coordinateur { Coordinateur(lecteur: lecteur) }

    func makeUIView(context: Context) -> VueVideo {
        let vue = VueVideo()
        vue.alpha = 0.01
        vue.isUserInteractionEnabled = false
        vue.couche.player = lecteur.player
        vue.couche.videoGravity = .resizeAspect
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let pip = AVPictureInPictureController(playerLayer: vue.couche)
            pip?.delegate = context.coordinator
            lecteur.pip = pip
        }
        return vue
    }

    func updateUIView(_ vue: VueVideo, context: Context) {}

    final class Coordinateur: NSObject, AVPictureInPictureControllerDelegate {
        private let lecteur: LecteurController

        @MainActor init(lecteur: LecteurController) {
            self.lecteur = lecteur
        }

        func pictureInPictureControllerWillStartPictureInPicture(_ controleur: AVPictureInPictureController) {
            MainActor.assumeIsolated {
                lecteur.enPip = true
                lecteur.estAffiche = false
            }
        }

        func pictureInPictureControllerDidStopPictureInPicture(_ controleur: AVPictureInPictureController) {
            MainActor.assumeIsolated { lecteur.enPip = false }
        }

        func pictureInPictureController(
            _ controleur: AVPictureInPictureController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler terminer: @escaping (Bool) -> Void
        ) {
            MainActor.assumeIsolated { lecteur.estAffiche = true }
            terminer(true)
        }
    }
}
