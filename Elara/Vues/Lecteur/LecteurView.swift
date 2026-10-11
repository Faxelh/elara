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

/// Façon d'afficher l'image dans l'écran.
enum ModeImage: String, CaseIterable {
    case ajuster, remplir, etirer

    var gravite: AVLayerVideoGravity {
        switch self {
        case .ajuster: .resizeAspect
        case .remplir: .resizeAspectFill
        case .etirer: .resize
        }
    }

    var titre: LocalizedStringKey {
        switch self {
        case .ajuster: "Ajuster à l'écran"
        case .remplir: "Remplir l'écran"
        case .etirer: "Étirer"
        }
    }

    var icone: String {
        switch self {
        case .ajuster: "rectangle.arrowtriangle.2.inward"
        case .remplir: "rectangle.arrowtriangle.2.outward"
        case .etirer: "arrow.left.and.right.square"
        }
    }

    var suivant: ModeImage {
        let tous = Self.allCases
        return tous[(tous.firstIndex(of: self)! + 1) % tous.count]
    }
}

/// Réglage partagé entre l'écran et la vue vidéo UIKit.
@MainActor
@Observable
final class PontVideo {
    var mode: ModeImage = .ajuster
}

/// Une piste (langue audio ou sous-titres) proposée par la vidéo.
private struct Piste: Identifiable {
    let id: Int
    let nom: String
    let option: AVMediaSelectionOption
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
    /// Écran verrouillé : les gestes et boutons sont désactivés (pour ne rien toucher par erreur).
    @State private var verrouille = false
    @State private var boutonDeverrouiller = false
    /// Avance / retour en glissant horizontalement : temps visé pendant le geste.
    @State private var defilement: Double?
    @State private var departDefilement: Double = 0
    @State private var tempsRestant = false
    @State private var groupeAudio: AVMediaSelectionGroup?
    @State private var pistesAudio: [Piste] = []
    @State private var groupeSousTitres: AVMediaSelectionGroup?
    @State private var sousTitres: [Piste] = []
    @State private var majPistes = 0

    private var estVideo: Bool { lecteur.mediaActuel?.type == .video }
    private var duree: Double { max(lecteur.dureeTotale, 1) }
    private let vitesses: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 3]
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
        .statusBarHidden(estVideo && !visibles)
        .persistentSystemOverlays(estVideo && !visibles ? .hidden : .automatic)
        .onAppear {
            if estVideo && Cle.booleen(Cle.rotationPaysage, defaut: false) { Orientation.paysage() }
            rearmer()
        }
        .onChange(of: lecteur.mediaActuel?.id) { _, _ in
            if estVideo && Cle.booleen(Cle.rotationPaysage, defaut: false) { Orientation.paysage() }
            rearmer()
        }
        .onChange(of: lecteur.enLecture) { _, _ in rearmer() }
        .task(id: lecteur.mediaActuel?.id) { await chargerPistes() }
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
                mode: pont.mode,
                verrouille: verrouille,
                indicateur: $indicateur,
                surTap: { toucherEcran() },
                surDoubleTap: { droite in sauter(droite ? 10 : -10) },
                surDefilement: { delta in defiler(delta) },
                surPincer: { agrandir in
                    pont.mode = agrandir ? .remplir : .ajuster
                    rearmer()
                }
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

            if let defilement {
                // Bulle pendant l'avance / retour au doigt.
                VStack(spacing: 4) {
                    Text("\(Format.duree(defilement)) / \(Format.duree(lecteur.dureeTotale))")
                        .font(.title2.bold().monospacedDigit())
                    let ecart = defilement - departDefilement
                    Text((ecart >= 0 ? "+" : "−") + Format.duree(abs(ecart)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

            if verrouille {
                if boutonDeverrouiller {
                    VStack(spacing: 10) {
                        Button {
                            withAnimation { verrouille = false; boutonDeverrouiller = false }
                            rearmer()
                        } label: {
                            Image(systemName: "lock.open.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 64, height: 64)
                                .background(Theme.degrade, in: Circle())
                        }
                        .accessibilityLabel("Déverrouiller l'écran")
                        Text("Touchez pour déverrouiller").font(.caption).foregroundStyle(.white.opacity(0.8))
                    }
                    .transition(.opacity)
                }
            } else if visibles {
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
        .animation(.easeInOut(duration: 0.2), value: verrouille)
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
                if lecteur.minuterieActive {
                    Label(texteMinuterie, systemImage: "moon.zzz.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                }
            }
            Spacer()

            if Cle.booleen(Cle.airplay, defaut: true) {
                SelecteurAirPlay(couleur: estVideo ? .white : .label)
                    .frame(width: 44, height: 44)
            }
            if estVideo {
                Button {
                    Orientation.basculer()
                    rearmer()
                } label: {
                    Image(systemName: "rotate.right").font(.title3).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Pivoter l'écran")
            }
            menuPlus
        }
        .padding(.horizontal, 8)
    }

    /// Menu « ⋯ » : pistes audio, sous-titres, minuterie, répétition.
    private var menuPlus: some View {
        Menu {
            Button {
                lecteur.repeterUn.toggle()
            } label: {
                Label(lecteur.repeterUn ? LocalizedStringKey("Ne plus répéter") : LocalizedStringKey("Répéter cette vidéo"),
                      systemImage: lecteur.repeterUn ? "repeat.1.circle.fill" : "repeat.1")
            }

            Menu {
                if lecteur.minuterieActive {
                    Button("Désactiver la minuterie", systemImage: "xmark") { lecteur.annulerMinuterie() }
                }
                ForEach([15, 30, 45, 60, 90], id: \.self) { m in
                    Button("\(m) min") { lecteur.programmerMinuterie(minutes: m) }
                }
                Button("À la fin de la vidéo") { lecteur.programmerMinuterie(minutes: nil) }
            } label: {
                Label("Minuterie de veille", systemImage: "moon.zzz")
            }

            if let groupe = groupeAudio, pistesAudio.count > 1 {
                Menu {
                    let actuelle = lecteur.optionActuelle(dans: groupe)
                    ForEach(pistesAudio) { p in
                        Button {
                            lecteur.choisir(p.option, dans: groupe)
                            majPistes += 1
                        } label: {
                            if actuelle == p.option { Label(p.nom, systemImage: "checkmark") } else { Text(p.nom) }
                        }
                    }
                } label: {
                    Label("Piste audio", systemImage: "waveform")
                }
            }

            if let groupe = groupeSousTitres, !sousTitres.isEmpty {
                Menu {
                    let actuelle = lecteur.optionActuelle(dans: groupe)
                    Button {
                        lecteur.choisir(nil, dans: groupe)
                        majPistes += 1
                    } label: {
                        if actuelle == nil { Label("Désactivés", systemImage: "checkmark") } else { Text("Désactivés") }
                    }
                    ForEach(sousTitres) { p in
                        Button {
                            lecteur.choisir(p.option, dans: groupe)
                            majPistes += 1
                        } label: {
                            if actuelle == p.option { Label(p.nom, systemImage: "checkmark") } else { Text(p.nom) }
                        }
                    }
                } label: {
                    Label("Sous-titres", systemImage: "captions.bubble")
                }
            }

            if estVideo {
                Divider()
                Button {
                    withAnimation { verrouille = true; boutonDeverrouiller = false; visibles = false }
                } label: {
                    Label("Verrouiller l'écran", systemImage: "lock")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44)
        }
        .id(majPistes)
        .accessibilityLabel("Plus d'options")
    }

    private var texteMinuterie: String {
        if lecteur.minuterieFinVideo { return String(localized: "Fin de la vidéo") }
        guard let fin = lecteur.minuterieFin else { return "" }
        return fin.formatted(date: .omitted, time: .shortened)
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
                Image(systemName: lecteur.enLecture ? "pause.fill" : (lecteur.termine ? "arrow.counterclockwise" : "play.fill"))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 78, height: 78)
                    .background(Theme.degrade, in: Circle())
                    .shadow(color: Theme.accent.opacity(0.55), radius: 18, y: 6)
            }
            .accessibilityLabel(lecteur.enLecture ? LocalizedStringKey("Pause") : (lecteur.termine ? LocalizedStringKey("Revoir") : LocalizedStringKey("Lecture")))
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
                // Toucher la durée : affiche le temps restant.
                Button {
                    tempsRestant.toggle()
                    rearmer()
                } label: {
                    Text(tempsRestant
                         ? "−" + Format.duree(max(lecteur.dureeTotale - (positionGlissee ?? lecteur.tempsActuel), 0))
                         : Format.duree(lecteur.dureeTotale))
                }
                .buttonStyle(.plain)
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
                    pont.mode = pont.mode.suivant
                    rearmer()
                } label: {
                    pastille { Image(systemName: pont.mode.icone) }
                }
                .accessibilityLabel(pont.mode.titre)

                if lecteur.repeterUn {
                    Button {
                        lecteur.repeterUn = false
                        rearmer()
                    } label: {
                        pastille { Image(systemName: "repeat.1").foregroundStyle(Theme.accent) }
                    }
                    .accessibilityLabel("Ne plus répéter")
                }

                Spacer()

                Button {
                    withAnimation { verrouille = true; boutonDeverrouiller = false; visibles = false }
                } label: {
                    pastille { Image(systemName: "lock") }
                }
                .accessibilityLabel("Verrouiller l'écran")

                if pipDisponible {
                    Button {
                        lecteur.basculerPip()
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

    private func toucherEcran() {
        if verrouille {
            withAnimation { boutonDeverrouiller.toggle() }
            if boutonDeverrouiller {
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { boutonDeverrouiller = false }
                }
            }
        } else {
            basculerCommandes()
        }
    }

    /// Glisser horizontalement : `delta` en secondes depuis le début du geste, `nil` à la fin.
    private func defiler(_ delta: Double?) {
        guard let delta else {
            if let cible = defilement { lecteur.chercher(cible) }
            defilement = nil
            rearmer()
            return
        }
        if defilement == nil { departDefilement = lecteur.tempsActuel }
        var cible = max(departDefilement + delta, 0)
        if lecteur.dureeTotale > 0 { cible = min(cible, lecteur.dureeTotale) }
        defilement = cible
    }

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
        guard !verrouille else { return }
        visibles = true
        guard lecteur.enLecture, estVideo else { return }
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            if jeton == mien, lecteur.enLecture, positionGlissee == nil, defilement == nil { visibles = false }
        }
    }

    private func chargerPistes() async {
        // Laisse le temps à la vidéo de se charger.
        try? await Task.sleep(for: .milliseconds(400))
        if let audio = await lecteur.pistes(.audible) {
            groupeAudio = audio.groupe
            pistesAudio = audio.options.enumerated().map { Piste(id: $0.offset, nom: $0.element.displayName, option: $0.element) }
        } else {
            groupeAudio = nil
            pistesAudio = []
        }
        if let st = await lecteur.pistes(.legible) {
            groupeSousTitres = st.groupe
            sousTitres = st.options.enumerated().map { Piste(id: $0.offset, nom: $0.element.displayName, option: $0.element) }
        } else {
            groupeSousTitres = nil
            sousTitres = []
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

    /// Bouton « Pivoter » du lecteur : passe en paysage ou revient en portrait.
    static func basculer() {
        let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene
        let paysageActuel = scene?.interfaceOrientation.isLandscape ?? false
        if paysageActuel { portrait() } else { paysage() }
    }

    private static func demander(_ masque: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene
        else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: masque)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

/// Vue vidéo d'Elara : image, gestes (luminosité à gauche, volume à droite, avance en glissant
/// horizontalement, pincer pour zoomer), toucher simple pour les commandes, double toucher ±10 s.
final class VueVideo: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var couche: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct VideoElara: UIViewRepresentable {
    let player: AVPlayer
    let mode: ModeImage
    var verrouille: Bool = false
    @Binding var indicateur: IndicateurGeste?
    var surTap: () -> Void
    var surDoubleTap: (Bool) -> Void
    var surDefilement: (Double?) -> Void = { _ in }
    var surPincer: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinateur { Coordinateur(indicateur: $indicateur) }

    func makeUIView(context: Context) -> VueVideo {
        let vue = VueVideo()
        vue.backgroundColor = .black
        vue.couche.player = player
        vue.couche.videoGravity = mode.gravite
        let c = context.coordinator
        mettreAJour(c)

        let glisser = UIPanGestureRecognizer(target: c, action: #selector(Coordinateur.glisser(_:)))
        glisser.delegate = c
        glisser.maximumNumberOfTouches = 1
        vue.addGestureRecognizer(glisser)

        let pincer = UIPinchGestureRecognizer(target: c, action: #selector(Coordinateur.pincer(_:)))
        pincer.delegate = c
        vue.addGestureRecognizer(pincer)

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
        return vue
    }

    func updateUIView(_ vue: VueVideo, context: Context) {
        if vue.couche.player !== player { vue.couche.player = player }
        if vue.couche.videoGravity != mode.gravite {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            vue.couche.videoGravity = mode.gravite
            CATransaction.commit()
        }
        mettreAJour(context.coordinator)
    }

    private func mettreAJour(_ c: Coordinateur) {
        c.indicateur = $indicateur
        c.surTap = surTap
        c.surDoubleTap = surDoubleTap
        c.surDefilement = surDefilement
        c.surPincer = surPincer
        c.verrouille = verrouille
    }

    @MainActor
    final class Coordinateur: NSObject, UIGestureRecognizerDelegate {
        var indicateur: Binding<IndicateurGeste?>
        var surTap: () -> Void = {}
        var surDoubleTap: (Bool) -> Void = { _ in }
        var surDefilement: (Double?) -> Void = { _ in }
        var surPincer: (Bool) -> Void = { _ in }
        var verrouille = false
        weak var vueVolume: MPVolumeView?
        private var mode: Mode?
        private var depart: Double = 0
        private var masquage: DispatchWorkItem?

        private enum Mode { case luminosite, volume, temps }

        init(indicateur: Binding<IndicateurGeste?>) {
            self.indicateur = indicateur
        }

        @objc func toucher(_ geste: UITapGestureRecognizer) { surTap() }

        @objc func doubleToucher(_ geste: UITapGestureRecognizer) {
            guard !verrouille, let vue = geste.view else { return }
            surDoubleTap(geste.location(in: vue).x > vue.bounds.width / 2)
        }

        @objc func pincer(_ geste: UIPinchGestureRecognizer) {
            guard !verrouille, geste.state == .ended else { return }
            if geste.scale > 1.08 { surPincer(true) } else if geste.scale < 0.92 { surPincer(false) }
        }

        private var curseurVolume: UISlider? {
            vueVolume?.subviews.compactMap { $0 as? UISlider }.first
        }

        func gestureRecognizerShouldBegin(_ geste: UIGestureRecognizer) -> Bool {
            if geste is UITapGestureRecognizer { return true }
            guard !verrouille else { return false }
            guard let pan = geste as? UIPanGestureRecognizer, let vue = pan.view else { return true }
            let vitesse = pan.velocity(in: vue)
            if abs(vitesse.x) > abs(vitesse.y) * 1.2 { return true }           // avance / retour
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
                let v = pan.velocity(in: vue)
                if abs(v.x) > abs(v.y) {
                    mode = .temps
                } else if pan.location(in: vue).x < vue.bounds.width / 2 {
                    mode = .luminosite
                    depart = Double(ecran?.brightness ?? 0.5)
                } else {
                    mode = .volume
                    depart = Double(AVAudioSession.sharedInstance().outputVolume)
                }
            case .changed:
                if mode == .temps {
                    // Toute la largeur de l'écran = 90 secondes (plus précis avec un geste court).
                    let part = Double(pan.translation(in: vue).x) / Double(max(vue.bounds.width, 1))
                    surDefilement(part * 90)
                    return
                }
                let delta = -Double(pan.translation(in: vue).y) / Double(max(vue.bounds.height * 0.7, 1))
                let valeur = min(max(depart + delta, 0), 1)
                switch mode {
                case .luminosite:
                    ecran?.brightness = CGFloat(valeur)
                    indicateur.wrappedValue = IndicateurGeste(icone: "sun.max.fill", valeur: valeur)
                case .volume:
                    curseurVolume?.value = Float(valeur)
                    indicateur.wrappedValue = IndicateurGeste(
                        icone: valeur == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", valeur: valeur)
                default:
                    break
                }
            default:
                if mode == .temps { surDefilement(nil) }
                mode = nil
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
