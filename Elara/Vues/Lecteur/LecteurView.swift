import SwiftUI
import AVKit
import MediaPlayer

/// Indicateur affiché pendant un geste (luminosité ou volume).
struct IndicateurGeste: Equatable {
    var icone: String
    var valeur: Double
}

struct LecteurView: View {
    @Environment(LecteurController.self) private var lecteur
    @Environment(\.scenePhase) private var scenePhase
    @State private var indicateur: IndicateurGeste?

    private var estVideo: Bool { lecteur.mediaActuel?.type == .video }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    Orientation.portrait()
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
                if Cle.booleen(Cle.airplay, defaut: true) {
                    SelecteurAirPlay(couleur: estVideo ? .white : .label)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 8)

            if estVideo {
                VideoAVKit(player: lecteur.player, indicateur: $indicateur)
                    .ignoresSafeArea(edges: .bottom)
                    .overlay {
                        if let indicateur {
                            HStack(spacing: 10) {
                                Image(systemName: indicateur.icone)
                                ProgressView(value: indicateur.valeur).frame(width: 120).tint(.white)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                            .environment(\.colorScheme, .dark)
                            .allowsHitTesting(false)
                        }
                    }
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
        .onAppear {
            if estVideo && Cle.booleen(Cle.rotationPaysage, defaut: false) { Orientation.paysage() }
        }
        .onChange(of: lecteur.mediaActuel?.id) { _, _ in
            if estVideo && Cle.booleen(Cle.rotationPaysage, defaut: false) { Orientation.paysage() }
        }
        .onDisappear {
            Orientation.portrait()
        }
    }
}

/// Rotation de l'écran demandée par l'app.
@MainActor
enum Orientation {
    static func paysage() { demander(.landscape) }
    static func portrait() { demander(.portrait) }

    private static func demander(_ masque: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene
        else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: masque)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

/// Lecteur vidéo natif d'Apple (contrôles, AirPlay, image dans l'image)
/// avec les gestes luminosité (moitié gauche) et volume (moitié droite).
struct VideoAVKit: UIViewControllerRepresentable {
    let player: AVPlayer
    @Binding var indicateur: IndicateurGeste?

    func makeCoordinator() -> Coordinateur { Coordinateur(indicateur: $indicateur) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        let pip = Cle.booleen(Cle.imageDansImage, defaut: true)
        vc.allowsPictureInPicturePlayback = pip
        vc.canStartPictureInPictureAutomaticallyFromInline = pip
        vc.updatesNowPlayingInfoCenter = false
        vc.entersFullScreenWhenPlaybackBegins = false

        let glisser = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinateur.glisser(_:)))
        glisser.delegate = context.coordinator
        glisser.maximumNumberOfTouches = 1
        vc.view.addGestureRecognizer(glisser)

        // Un MPVolumeView caché permet de régler le volume (et masque l'indicateur système).
        let volume = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        volume.alpha = 0.01
        vc.view.addSubview(volume)
        context.coordinator.vueVolume = volume
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
        context.coordinator.indicateur = $indicateur
    }

    @MainActor
    final class Coordinateur: NSObject, UIGestureRecognizerDelegate {
        var indicateur: Binding<IndicateurGeste?>
        weak var vueVolume: MPVolumeView?
        private var cote: Cote?
        private var depart: Double = 0
        private var masquage: DispatchWorkItem?

        private enum Cote { case luminosite, volume }

        init(indicateur: Binding<IndicateurGeste?>) {
            self.indicateur = indicateur
        }

        private var curseurVolume: UISlider? {
            vueVolume?.subviews.compactMap { $0 as? UISlider }.first
        }

        func gestureRecognizerShouldBegin(_ geste: UIGestureRecognizer) -> Bool {
            guard let pan = geste as? UIPanGestureRecognizer, let vue = pan.view else { return false }
            let vitesse = pan.velocity(in: vue)
            guard abs(vitesse.y) > abs(vitesse.x) * 1.5 else { return false }
            let gauche = pan.location(in: vue).x < vue.bounds.width / 2
            if gauche { return Cle.booleen(Cle.gesteLuminosite, defaut: true) }
            return Cle.booleen(Cle.gesteVolume, defaut: true)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith autre: UIGestureRecognizer) -> Bool { false }

        @objc func glisser(_ pan: UIPanGestureRecognizer) {
            guard let vue = pan.view else { return }
            let ecran = vue.window?.windowScene?.screen
            switch pan.state {
            case .began:
                masquage?.cancel()
                if pan.location(in: vue).x < vue.bounds.width / 2 {
                    cote = .luminosite
                    depart = Double(ecran?.brightness ?? 0.5)
                } else {
                    cote = .volume
                    depart = Double(AVAudioSession.sharedInstance().outputVolume)
                }
            case .changed:
                let delta = -Double(pan.translation(in: vue).y) / Double(max(vue.bounds.height * 0.7, 1))
                let valeur = min(max(depart + delta, 0), 1)
                switch cote {
                case .luminosite:
                    ecran?.brightness = CGFloat(valeur)
                    indicateur.wrappedValue = IndicateurGeste(icone: "sun.max.fill", valeur: valeur)
                case .volume:
                    curseurVolume?.value = Float(valeur)
                    indicateur.wrappedValue = IndicateurGeste(
                        icone: valeur == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", valeur: valeur)
                case nil:
                    break
                }
            default:
                cote = nil
                let tache = DispatchWorkItem { [weak self] in self?.indicateur.wrappedValue = nil }
                masquage = tache
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: tache)
            }
        }
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
