import SwiftUI
import AVFoundation

/// Retirer un filigrane (logo, texte, @pseudo…) sur une ou plusieurs vidéos :
/// on place une ou plusieurs zones sur l'image, Elara les efface (ou recadre) dans chaque vidéo choisie.
struct FiligraneView: View {
    let medias: [Media]

    @Environment(Bibliotheque.self) private var bib
    @Environment(\.dismiss) private var fermer
    @State private var apercu: UIImage?
    @State private var zones: [CGRect] = [Self.coin(.basDroite)]
    @State private var choisie = 0
    @State private var garderOriginal = false
    @AppStorage("filigrane.mode") private var mode: Filigrane.Mode = .effacer
    @State private var enCours = false
    @State private var progression: Double = 0
    @State private var rang = 0
    @State private var erreur: String?
    @State private var tache: Task<Void, Never>?

    enum Coin: CaseIterable {
        case hautGauche, hautDroite, basGauche, basDroite, centreBas
        var titre: LocalizedStringKey {
            switch self {
            case .hautGauche: "En haut à gauche"
            case .hautDroite: "En haut à droite"
            case .basGauche: "En bas à gauche"
            case .basDroite: "En bas à droite"
            case .centreBas: "En bas au centre"
            }
        }
    }

    static func coin(_ c: Coin) -> CGRect {
        switch c {
        case .hautGauche: CGRect(x: 0.03, y: 0.04, width: 0.36, height: 0.08)
        case .hautDroite: CGRect(x: 0.61, y: 0.04, width: 0.36, height: 0.08)
        case .basGauche: CGRect(x: 0.03, y: 0.86, width: 0.36, height: 0.08)
        case .basDroite: CGRect(x: 0.61, y: 0.86, width: 0.36, height: 0.08)
        case .centreBas: CGRect(x: 0.25, y: 0.86, width: 0.5, height: 0.08)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                editeur
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal)
                Picker("Méthode", selection: $mode) {
                    Text("Effacer").tag(Filigrane.Mode.effacer)
                    Text("Recadrer").tag(Filigrane.Mode.recadrer)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .disabled(enCours)
                Text(mode == .effacer
                     ? "Effacer : la zone est reconstruite avec les couleurs autour, sans flou. Placez le cadre juste sur le filigrane (agrandir avec le rond)."
                     : "Recadrer : la bande qui contient le filigrane est coupée (partie sombre). Aucune trace, l'image devient un peu plus petite.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                outils
                if enCours {
                    VStack(spacing: 6) {
                        ProgressView(value: (Double(rang) + progression) / Double(max(medias.count, 1)))
                        Text("Vidéo \(rang + 1) sur \(medias.count)…").font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
                Toggle("Garder aussi l'original", isOn: $garderOriginal)
                    .padding(.horizontal)
                    .disabled(enCours)
                Button {
                    appliquer()
                } label: {
                    Text(medias.count <= 1 ? "Retirer le filigrane" : "Retirer sur \(medias.count) vidéos")
                        .bold()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .disabled(enCours || zones.isEmpty)
            }
            .navigationTitle("Retirer un filigrane")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        tache?.cancel()
                        fermer()
                    }
                }
            }
            .alert(erreur ?? "", isPresented: Binding(get: { erreur != nil }, set: { if !$0 { erreur = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .interactiveDismissDisabled(enCours)
        }
        .task {
            guard let premier = medias.first else { return }
            apercu = await Self.image(de: bib.url(de: premier))
        }
    }

    // MARK: - Aperçu et zones

    private var editeur: some View {
        GeometryReader { geo in
            let taille = apercu?.size ?? CGSize(width: 9, height: 16)
            let echelle = min(geo.size.width / taille.width, geo.size.height / taille.height)
            let cadre = CGSize(width: taille.width * echelle, height: taille.height * echelle)
            ZStack(alignment: .topLeading) {
                Group {
                    if let apercu {
                        Image(uiImage: apercu).resizable()
                    } else {
                        Color.black.overlay { ProgressView().tint(.white) }
                    }
                }
                .frame(width: cadre.width, height: cadre.height)
                if mode == .recadrer {
                    // Partie coupée, assombrie.
                    let g = Filigrane.partieGardee(zones)
                    Path { p in
                        p.addRect(CGRect(origin: .zero, size: cadre))
                        p.addRect(CGRect(x: g.minX * cadre.width, y: g.minY * cadre.height,
                                         width: g.width * cadre.width, height: g.height * cadre.height))
                    }
                    .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                }
                ForEach(zones.indices, id: \.self) { i in
                    CadreZone(rect: $zones[i], taille: cadre, active: i == choisie) { choisie = i }
                }
            }
            .frame(width: cadre.width, height: cadre.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private var outils: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(Coin.allCases, id: \.self) { c in
                    Button(c.titre) {
                        if zones.isEmpty { zones = [Self.coin(c)]; choisie = 0 } else { zones[min(choisie, zones.count - 1)] = Self.coin(c) }
                    }
                }
            } label: {
                Label("Position", systemImage: "rectangle.dashed")
            }
            Button {
                zones.append(Self.coin(zones.count % 2 == 0 ? .basDroite : .hautGauche))
                choisie = zones.count - 1
            } label: {
                Label("Ajouter une zone", systemImage: "plus.rectangle")
            }
            .disabled(zones.count >= 4)
            Button(role: .destructive) {
                guard zones.indices.contains(choisie) else { return }
                zones.remove(at: choisie)
                choisie = max(0, zones.count - 1)
            } label: {
                Label("Retirer", systemImage: "trash")
            }
            .disabled(zones.isEmpty)
        }
        .labelStyle(.titleAndIcon)
        .font(.footnote.weight(.semibold))
        .buttonStyle(.bordered)
        .tint(Theme.accent)
        .disabled(enCours)
    }

    // MARK: - Traitement

    private func appliquer() {
        let liste = medias
        let zonesFixes = zones
        let garder = garderOriginal
        let methode = mode
        tache = Task {
            enCours = true
            defer { enCours = false }
            var reussis = 0
            for (i, media) in liste.enumerated() {
                rang = i
                progression = 0
                do {
                    let sortie = try await Filigrane.traiter(bib.url(de: media), zones: zonesFixes, mode: methode, nom: media.nom) { p in
                        progression = p
                    }
                    if garder {
                        await bib.importer(depuis: sortie, deplacer: true, prive: media.estPrive, dossier: media.dossier)
                    } else {
                        bib.remplacer(media, par: sortie)
                        await bib.refaireMiniature(media)
                    }
                    reussis += 1
                } catch is CancellationError {
                    return
                } catch {
                    erreur = String(localized: "« \(media.nom) » : \(error.localizedDescription)")
                }
            }
            if reussis == liste.count { fermer() }
        }
    }

    /// Image de la vidéo (à 1 s) pour placer les zones.
    static func image(de url: URL) async -> UIImage? {
        let generateur = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generateur.appliesPreferredTrackTransform = true
        generateur.maximumSize = CGSize(width: 1200, height: 1200)
        let moment = CMTime(seconds: 1, preferredTimescale: 600)
        guard let resultat = try? await generateur.image(at: moment) else { return nil }
        return UIImage(cgImage: resultat.image)
    }
}

/// Un cadre déplaçable (glisser) et redimensionnable (rond en bas à droite).
private struct CadreZone: View {
    @Binding var rect: CGRect
    let taille: CGSize
    let active: Bool
    let choisir: () -> Void
    @State private var depart: CGRect?

    private static let minimum: CGFloat = 0.04

    var body: some View {
        let r = CGRect(x: rect.minX * taille.width, y: rect.minY * taille.height,
                       width: rect.width * taille.width, height: rect.height * taille.height)
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Rectangle().stroke(active ? Theme.accent : .white, style: StrokeStyle(lineWidth: 2, dash: active ? [] : [5, 4])))
            .frame(width: r.width, height: r.height)
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(active ? Theme.accent : .white)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 1))
                    .offset(x: 11, y: 11)
                    .frame(width: 44, height: 44, alignment: .bottomTrailing)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture()
                            .onChanged { v in
                                choisir()
                                let d = depart ?? rect
                                depart = d
                                var n = d
                                n.size.width = min(max(Self.minimum, d.width + v.translation.width / taille.width), 1 - d.minX)
                                n.size.height = min(max(Self.minimum, d.height + v.translation.height / taille.height), 1 - d.minY)
                                rect = n
                            }
                            .onEnded { _ in depart = nil }
                    )
            }
            .contentShape(Rectangle())
            .offset(x: r.minX, y: r.minY)
            .gesture(
                DragGesture()
                    .onChanged { v in
                        choisir()
                        let d = depart ?? rect
                        depart = d
                        var n = d
                        n.origin.x = min(max(0, d.minX + v.translation.width / taille.width), 1 - d.width)
                        n.origin.y = min(max(0, d.minY + v.translation.height / taille.height), 1 - d.height)
                        rect = n
                    }
                    .onEnded { _ in depart = nil }
            )
            .onTapGesture { choisir() }
    }
}
