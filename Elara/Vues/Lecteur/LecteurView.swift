import SwiftUI
import AVKit
import MediaPlayer

/// Indicateur affiché pendant un geste (luminosité ou volume).
struct IndicateurGeste: Equatable {
    var icone: String
    var valeur: Double
}

/// Petit badge « +10 s / −10 s » affiché après un double toucher.
private struct Saut: Equatable, Identifiable {
    let id = UUID()
    let droite: Bool
}

/// Pont entre l'écran et la vue vidéo UIKit (image dans l'image, remplissage).
@MainActor
@Observable
final class PontVideo {
    var remplir = false
    @ObservationIgnored var pip: AVPictureInPictureController?

    func basculerPip() {
        guard let pip else { return }
        if pip.isPictureInPictureActive { pip.stopPictureInPicture() } else { pip.startPictureInPicture() }
    }
}

struct LecteurView: View {
    @Environment(LecteurController.self) private var lecteur
    @Environment(\.scenePhase) private var scenePhase
    @State private var indicateur: IndicateurGeste?
    @State private var pont = PontVideo()
    @State private var visibles = true
    @State private var jeton = 0
    @State private var saut: Saut?
    @State private var positionGlissee: Double?

    private var estVideo: Bool { lecteur.mediaActuel?.type == .video }
    private var duree: Double { max(lecteur.dureeTotale, 1) }
    private let vitesses: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]
    private var pipDisponible: Bool {
        AVPictureInPictureController.isPictureInPictureSupported() && Cle.booleen(Cle.imageDansImage, defaut: true)
    }

    var body: some View {
        Group {
            if estVideo { vueVideo } else { vueAudio }
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
            rearmer()
        }
        .onChange(of: lecteur.mediaActuel?.id) { _, _ in
            if estVideo && Cle.booleen(Cle.rotationPaysage, defaut: false) { Orientation.paysage() }
            rearmer()
        }
        .onChange(of: lecteur.enLecture) { _, _ in rearmer() }
        .onDisappear {
            Orientation.portrait()
        }
    }

    // MARK: - Audio

    private var vueAudio: some View {
        VStack(spacing: 0) {
            entete
            AudioLecteurView()
        }
    }

    // MARK: - Vidéo

    private var vueVideo: some View {
        ZStack {
            VideoElara(
                player: lecteur.player,
                pont: pont,
                remplir: pont.remplir,
                indicateur: $indicateur,
                surTap: { basculerCommandes() },
                surDoubleTap: { droite in sauter(droite ? 10 : -10) }
            )
            .ignoresSafeArea()

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

            if let saut {
                HStack {
                    if saut.droite { Spacer() }
                    VStack(spacing: 4) {
                        Image(systemName: saut.droite ? "goforward.10" : "gobackward.10").font(.system(size: 34, weight: .semibold))
                        Text(saut.droite ? "+10 s" : "−10 s").font(.caption.bold())
                    }
                    .padding(22)
                    .background(Theme.accent.opacity(0.55), in: Circle())
                    .padding(.horizontal, 36)
                    if !saut.droite { Spacer() }
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            if visibles {
                VStack(spacing: 0) {
                    entete
                        .padding(.bottom, 28)
                        .background {
                            LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
                                .ignoresSafeArea(edges: .top)
                                .allowsHitTesting(false)
                        }
                    Spacer(minLength: 0)
                    pied
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                        .padding(.bottom, 8)
                        .background {
                            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                                .ignoresSafeArea(edges: .bottom)
                                .allowsHitTesting(false)
                        }
                }
                .transition(.opacity)
                centre.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: visibles)
        .animation(.easeOut(duration: 0.15), value: saut)
    }

    private var entete: some View {
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
            VStack(spacing: 1) {
                Text("ELARA")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(2.5)
                    .foregroundStyle(Theme.accent)
                Text(lecteur.mediaActuel?.nom ?? "")
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer()

            if Cle.booleen(Cle.airplay, defaut: true) {
                SelecteurAirPlay(couleur: estVideo ? .white : .label)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
    }

    private var centre: some View {
        HStack(spacing: 30) {
            if lecteur.file.count > 1 {
                boutonCommande("backward.end.fill", taille: 24, "Précédent") { lecteur.precedent() }
            }
            boutonCommande("gobackward.10", taille: 30, "Reculer de 10 secondes") { sauter(-10) }
            Button {
                lecteur.basculerLecture()
                rearmer()
            } label: {
                Image(systemName: lecteur.enLecture ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 78, height: 78)
                    .background(Theme.degrade, in: Circle())
                    .shadow(color: Theme.accent.opacity(0.55), radius: 18, y: 6)
            }
            .accessibilityLabel(lecteur.enLecture ? LocalizedStringKey("Pause") : LocalizedStringKey("Lecture"))
            boutonCommande("goforward.10", taille: 30, "Avancer de 10 secondes") { sauter(10) }
            if lecteur.file.count > 1 {
                boutonCommande("forward.end.fill", taille: 24, "Suivant") { lecteur.suivant() }
            }
        }
    }

    private func boutonCommande(_ icone: String, taille: CGFloat, _ titre: LocalizedStringKey,
                                action: @escaping () -> Void) -> some View {
        Button {
            action()
            rearmer()
        } label: {
            Image(systemName: icone)
                .font(.system(size: taille, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
        }
        .accessibilityLabel(titre)
    }

    private var pied: some View {
        VStack(spacing: 8) {
            BarreElara(
                valeur: positionGlissee ?? lecteur.tempsActuel,
                total: duree,
                surChangement: { positionGlissee = $0; rearmer() },
                surFin: { lecteur.chercher($0); positionGlissee = nil; rearmer() }
            )
            HStack {
                Text(Format.duree(positionGlissee ?? lecteur.tempsActuel))
                Spacer()
                Text(Format.duree(lecteur.dureeTotale))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.85))

            HStack(spacing: 10) {
                Menu {
                    ForEach(vitesses, id: \.self) { v in
                        Button {
                            lecteur.definirVitesse(Float(v))
                            rearmer()
                        } label: {
                            if lecteur.vitesse == Float(v) {
                                Label(libelle(v), systemImage: "checkmark")
                            } else {
                                Text(libelle(v))
                            }
                        }
                    }
                } label: {
                    pastille { Text(libelle(Double(lecteur.vitesse))).font(.subheadline.bold().monospacedDigit()) }
                }
                .accessibilityLabel("Vitesse")

                Button {
                    pont.remplir.toggle()
                    rearmer()
                } label: {
                    pastille {
                        Image(systemName: pont.remplir
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                    }
                }
                .accessibilityLabel(pont.remplir ? LocalizedStringKey("Ajuster à l'écran") : LocalizedStringKey("Remplir l'écran"))

                Spacer()

                if pipDisponible {
                    Button {
                        pont.basculerPip()
                    } label: {
                        pastille { Image(systemName: "pip.enter") }
                    }
                    .accessibilityLabel("Image dans l'image")
                }
            }
        }
    }

    private func pastille<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        contenu()
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minWidth: 44, minHeight: 34)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
    }

    private func libelle(_ v: Double) -> String { String(format: "%g×", v) }

    // MARK: - Actions

    private func sauter(_ delta: Double) {
        var cible = max(lecteur.tempsActuel + delta, 0)
        if lecteur.dureeTotale > 0 { cible = min(cible, lecteur.dureeTotale) }
        lecteur.chercher(cible)
        let badge = Saut(droite: delta > 0)
        saut = badge
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            if saut?.id == badge.id { saut = nil }
        }
        rearmer()
    }

    private func basculerCommandes() {
        if visibles {
            jeton += 1
            visibles = false
        } else {
            rearmer()
        }
    }

    /// Montre les commandes puis les cache après quelques secondes de lecture.
    private func rearmer() {
        jeton += 1
        let mien = jeton
        visibles = true
        guard lecteur.enLecture, estVideo else { return }
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            if jeton == mien, lecteur.enLecture, positionGlissee == nil { visibles = false }
        }
    }
}

/// Barre de progression aux couleurs d'Elara.
struct BarreElara: View {
    var valeur: Double
    var total: Double
    var surChangement: (Double) -> Void
    var surFin: (Double) -> Void
    @State private var actif = false

    var body: some View {
        GeometryReader { geo in
            let largeur = max(geo.size.width, 1)
            let part = min(max(valeur / max(total, 1), 0), 1)
            let epaisseur: CGFloat = actif ? 8 : 5
            let bouton: CGFloat = actif ? 22 : 14
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.28)).frame(height: epaisseur)
                Capsule().fill(Theme.degrade).frame(width: largeur * part, height: epaisseur)
                Circle()
                    .fill(.white)
                    .frame(width: bouton, height: bouton)
                    .shadow(color: Theme.accent.opacity(0.7), radius: 6)
                    .offset(x: largeur * part - bouton / 2)
            }
            .frame(height: 30)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        actif = true
                        surChangement(min(max(g.location.x / largeur, 0), 1) * total)
                    }
                    .onEnded { g in
                        actif = false
                        surFin(min(max(g.location.x / largeur, 0), 1) * total)
                    }
            )
            .animation(.easeOut(duration: 0.12), value: actif)
        }
        .frame(height: 30)
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

/// Vue vidéo d'Elara : image, gestes (luminosité à gauche, volume à droite),
/// toucher simple pour les commandes, double toucher pour avancer / reculer de 10 s.
final class VueVideo: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var couche: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct VideoElara: UIViewRepresentable {
    let player: AVPlayer
    let pont: PontVideo
    let remplir: Bool
    @Binding var indicateur: IndicateurGeste?
    var surTap: () -> Void
    var surDoubleTap: (Bool) -> Void

    func makeCoordinator() -> Coordinateur { Coordinateur(indicateur: $indicateur) }

    func makeUIView(context: Context) -> VueVideo {
        let vue = VueVideo()
        vue.backgroundColor = .black
        vue.couche.player = player
        vue.couche.videoGravity = remplir ? .resizeAspectFill : .resizeAspect
        let c = context.coordinator
        c.surTap = surTap
        c.surDoubleTap = surDoubleTap

        let glisser = UIPanGestureRecognizer(target: c, action: #selector(Coordinateur.glisser(_:)))
        glisser.delegate = c
        glisser.maximumNumberOfTouches = 1
        vue.addGestureRecognizer(glisser)

        let double = UITapGestureRecognizer(target: c, action: #selector(Coordinateur.doubleToucher(_:)))
        double.numberOfTapsRequired = 2
        vue.addGestureRecognizer(double)
        let simple = UITapGestureRecognizer(target: c, action: #selector(Coordinateur.toucher(_:)))
        simple.require(toFail: double)
        vue.addGestureRecognizer(simple)

        // Un MPVolumeView caché permet de régler le volume (et masque l'indicateur système).
        let volume = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        volume.alpha = 0.01
        vue.addSubview(volume)
        c.vueVolume = volume

        if AVPictureInPictureController.isPictureInPictureSupported(), Cle.booleen(Cle.imageDansImage, defaut: true) {
            let pip = AVPictureInPictureController(playerLayer: vue.couche)
            pip?.canStartPictureInPictureAutomaticallyFromInline = true
            pont.pip = pip
        }
        return vue
    }

    func updateUIView(_ vue: VueVideo, context: Context) {
        if vue.couche.player !== player { vue.couche.player = player }
        vue.couche.videoGravity = remplir ? .resizeAspectFill : .resizeAspect
        context.coordinator.indicateur = $indicateur
        context.coordinator.surTap = surTap
        context.coordinator.surDoubleTap = surDoubleTap
    }

    @MainActor
    final class Coordinateur: NSObject, UIGestureRecognizerDelegate {
        var indicateur: Binding<IndicateurGeste?>
        var surTap: () -> Void = {}
        var surDoubleTap: (Bool) -> Void = { _ in }
        weak var vueVolume: MPVolumeView?
        private var cote: Cote?
        private var depart: Double = 0
        private var masquage: DispatchWorkItem?

        private enum Cote { case luminosite, volume }

        init(indicateur: Binding<IndicateurGeste?>) {
            self.indicateur = indicateur
        }

        @objc func toucher(_ geste: UITapGestureRecognizer) { surTap() }

        @objc func doubleToucher(_ geste: UITapGestureRecognizer) {
            guard let vue = geste.view else { return }
            surDoubleTap(geste.location(in: vue).x > vue.bounds.width / 2)
        }

        private var curseurVolume: UISlider? {
            vueVolume?.subviews.compactMap { $0 as? UISlider }.first
        }

        func gestureRecognizerShouldBegin(_ geste: UIGestureRecognizer) -> Bool {
            guard let pan = geste as? UIPanGestureRecognizer, let vue = pan.view else { return true }
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
