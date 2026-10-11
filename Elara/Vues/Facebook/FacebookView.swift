#if PERSO
import SwiftUI
import WebKit

/// Onglet Facebook (version perso) : on navigue connecté, et dès qu'une vidéo
/// est lancée, un bandeau propose de la télécharger dans Elara.
struct FacebookView: View {
    @Environment(Bibliotheque.self) private var bib
    @State private var navigateur = NavigateurFacebook.partage
    @State private var telechargeur = Telechargeur()
    @State private var ajoute: Media?
    @State private var succesImage = false
    /// Pendant un téléchargement, le bandeau se range sur le côté (petite pastille) pour libérer la vidéo.
    @State private var bandeauDeploye = false
    @State private var enregistrementImage = false
    @State private var erreur: String?
    @State private var confirmerDeconnexion = false
    /// Masque les barres pour profiter des Reels (automatique sur les pages Reels).
    @State private var pleinEcran = false

    var body: some View {
        NavigationStack {
            PageWeb(vue: navigateur.vue)
                .background(Color.black)
                .overlay(alignment: .top) {
                    if navigateur.chargement {
                        ProgressView().progressViewStyle(.linear).tint(Theme.accent)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if pleinEcran { boutonsFlottants }
                }
                .overlay(alignment: .bottom) { bandeau }
                .toolbar(pleinEcran ? .hidden : .visible, for: .navigationBar, .tabBar)
                .animation(.easeInOut(duration: 0.25), value: pleinEcran)
                .onChange(of: navigateur.surReel) { _, reel in pleinEcran = reel }
                // Une nouvelle vidéo démarre : on remplace « Vidéo ajoutée » / l'erreur par la proposition de télécharger.
                .onChange(of: navigateur.video) { _, nouvelle in
                    if nouvelle != nil, !telechargeur.enCours {
                        withAnimation { ajoute = nil; erreur = nil }
                    }
                }
                .onAppear { pleinEcran = navigateur.surReel }
                .navigationTitle("Facebook")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button { navigateur.reculer() } label: { Image(systemName: "chevron.backward") }
                            .disabled(!navigateur.peutReculer)
                            .accessibilityLabel("Page précédente")
                        Button { navigateur.avancer() } label: { Image(systemName: "chevron.forward") }
                            .disabled(!navigateur.peutAvancer)
                            .accessibilityLabel("Page suivante")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { Task { await telecharger(nil) } } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                        .disabled(telechargeur.enCours)
                        .accessibilityLabel("Télécharger la vidéo affichée")
                        Menu {
                            Button("Plein écran", systemImage: "arrow.up.left.and.arrow.down.right") { pleinEcran = true }
                            Button("Recharger", systemImage: "arrow.clockwise") { navigateur.recharger() }
                            Button("Fil d'actualité", systemImage: "house") { navigateur.allerAccueil() }
                            Divider()
                            Button("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                confirmerDeconnexion = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .confirmationDialog("Se déconnecter de Facebook dans Elara ?",
                                    isPresented: $confirmerDeconnexion, titleVisibility: .visible) {
                    Button("Se déconnecter", role: .destructive) {
                        Task {
                            await ExtracteurFacebook.deconnecter()
                            navigateur.allerAccueil()
                        }
                    }
                }
        }
    }

    // MARK: - Plein écran

    private var boutonsFlottants: some View {
        HStack(spacing: 10) {
            boutonRond("chevron.backward", "Page précédente") { navigateur.reculer() }
                .disabled(!navigateur.peutReculer)
            boutonRond("arrow.down", "Télécharger la vidéo affichée") { Task { await telecharger(nil) } }
                .disabled(telechargeur.enCours)
            boutonRond("arrow.down.right.and.arrow.up.left", "Quitter le plein écran") { pleinEcran = false }
        }
        .padding(.top, 8)
        .padding(.trailing, 12)
    }

    private func boutonRond(_ icone: String, _ titre: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icone)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.45), in: Circle())
        }
        .accessibilityLabel(titre)
    }

    // MARK: - Bandeau

    @ViewBuilder
    private var bandeau: some View {
        if telechargeur.enCours && !bandeauDeploye {
            pastilleTelechargement
        } else if telechargeur.enCours {
            carte {
                ProgressView(value: telechargeur.recherche ? nil : telechargeur.progression)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(telechargeur.recherche ? "Recherche de la vidéo…" : "Téléchargement…")
                        .font(.subheadline.bold())
                    if !telechargeur.recherche {
                        Text("\(Int(telechargeur.progression * 100)) % · \(Format.taille(telechargeur.octetsRecus))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Button("Annuler", role: .destructive) { telechargeur.annuler() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button {
                    withAnimation(.spring(duration: 0.35)) { bandeauDeploye = false }
                } label: {
                    Image(systemName: "chevron.right.2").font(.subheadline.bold()).frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Réduire")
            }
            // Glisser vers la droite : range le bandeau sur le côté.
            .gesture(DragGesture(minimumDistance: 20).onEnded { g in
                if g.translation.width > 50 { withAnimation(.spring(duration: 0.35)) { bandeauDeploye = false } }
            })
        } else if let erreur {
            carte {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(erreur).font(.footnote)
                Spacer(minLength: 4)
                boutonFermer { self.erreur = nil }
            }
        } else if let ajoute {
            carte {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bib.estDoublonSignale(ajoute) ? LocalizedStringKey("Déjà dans Elara") : LocalizedStringKey("Vidéo ajoutée à Elara")).font(.subheadline.bold())
                    Text(ajoute.nom).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                boutonFermer { self.ajoute = nil }
            }
        } else if succesImage {
            carte {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                Text("Image enregistrée dans Photos").font(.subheadline.bold())
                Spacer(minLength: 4)
                boutonFermer { succesImage = false }
            }
        } else if let image = navigateur.imageDetectee {
            carte {
                Image(systemName: "photo.fill").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Image").font(.subheadline.bold())
                    Text("L'enregistrer dans Photos ?").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if enregistrementImage {
                    ProgressView()
                } else {
                    Button("Enregistrer") { Task { await enregistrerImage(image) } }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                boutonFermer { navigateur.imageDetectee = nil }
            }
        } else if let video = navigateur.video {
            carte {
                Image(systemName: "play.rectangle.fill").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vidéo en cours de lecture").font(.subheadline.bold())
                    Text("La télécharger dans Elara ?").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button("Télécharger") { Task { await telecharger(video) } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                boutonFermer { navigateur.fermerBandeau() }
            }
        }
    }

    /// Petite pastille ronde sur le côté pendant le téléchargement (toucher pour voir le détail).
    private var pastilleTelechargement: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.spring(duration: 0.35)) { bandeauDeploye = true }
            } label: {
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 4)
                    if telechargeur.recherche {
                        ProgressView().tint(.white)
                    } else {
                        Circle()
                            .trim(from: 0, to: max(0.02, telechargeur.progression))
                            .stroke(Theme.degrade, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(telechargeur.progression * 100))%")
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 46, height: 46)
                .padding(6)
                .background(.black.opacity(0.55), in: Circle())
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Téléchargement en cours")
        }
        .padding(.trailing, 12)
        .padding(.bottom, 90)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func carte<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        HStack(spacing: 12) { contenu() }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func boutonFermer(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.subheadline.bold())
                .frame(width: 30, height: 30)
                .background(Color.secondary.opacity(0.18), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Fermer")
    }

    // MARK: - Téléchargement

    private func telecharger(_ video: VideoDetectee?) async {
        bandeauDeploye = false
        erreur = nil
        ajoute = nil
        navigateur.video = nil
        do {
            let source = try await navigateur.lienFichier(pour: video)
            let resultat: Media?
            switch source {
            case .direct(let lien):
                resultat = await telechargeur.telecharger(lien.absoluteString, vers: bib, prive: false)
            case .flux(let liens):
                resultat = await telechargeur.telechargerFlux(liens, vers: bib, prive: false)
            }
            if let media = resultat {
                navigateur.marquerTelechargee(video)
                withAnimation { ajoute = media }
                // Le bandeau « Vidéo ajoutée » se ferme tout seul après quelques secondes.
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    if ajoute?.id == media.id { withAnimation { ajoute = nil } }
                }
            } else if let message = telechargeur.erreur {
                montrerErreur(message)
            }
        } catch let e as ErreurTelechargement {
            montrerErreur(e.message)
        } catch {
            montrerErreur(error.localizedDescription)
        }
    }

    private func enregistrerImage(_ lien: String) async {
        guard let url = URL(string: lien) else { return }
        enregistrementImage = true
        let ok = await Phototheque.enregistrerImage(depuis: url)
        enregistrementImage = false
        navigateur.imageDetectee = nil
        if ok {
            withAnimation { succesImage = true }
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { succesImage = false }
        } else {
            montrerErreur(String(localized: "Impossible d'enregistrer l'image. Autorisez Elara à ajouter des photos dans Réglages › Elara › Photos."))
        }
    }

    private func montrerErreur(_ message: String) {
        withAnimation { erreur = message }
        Task {
            try? await Task.sleep(for: .seconds(6))
            if erreur == message { withAnimation { erreur = nil } }
        }
    }
}

/// Affiche la vue web partagée (elle n'est pas recréée en changeant d'onglet).
private struct PageWeb: UIViewRepresentable {
    let vue: WKWebView
    func makeUIView(context: Context) -> WKWebView { vue }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
