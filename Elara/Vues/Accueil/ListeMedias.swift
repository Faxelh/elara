import SwiftUI

/// Affiche des médias en grille ou en liste, avec le menu d'actions (appui long)
/// et un mode « Sélectionner » pour agir sur plusieurs médias à la fois.
struct ListeMedias: View {
    let medias: [Media]
    let vue: VueAccueil

    @Environment(Bibliotheque.self) private var bib
    @Environment(LecteurController.self) private var lecteur
    @State private var aRenommer: Media?
    @State private var nouveauNom = ""
    @State private var aSupprimer: Media?

    @State private var enSelection = false
    @State private var selection: Set<UUID> = []
    @State private var confirmerSuppression = false
    @State private var enregistrement = false
    @State private var message: String?

    private let colonnes = [GridItem(.adaptive(minimum: 105), spacing: 12)]

    private var selectionnes: [Media] { medias.filter { selection.contains($0.id) } }
    private var toutSelectionne: Bool { !medias.isEmpty && selection.count == medias.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            enteteSelection
            Group {
                if vue == .grille {
                    LazyVGrid(columns: colonnes, spacing: 14) {
                        ForEach(medias) { media in
                            Button { toucher(media) } label: {
                                VignetteMedia(media: media)
                                    .overlay(alignment: .topTrailing) { coche(media) }
                                    .opacity(enSelection && !selection.contains(media.id) ? 0.75 : 1)
                                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu { if !enSelection { menu(media) } }
                        }
                    }
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(medias) { media in
                            Button { toucher(media) } label: {
                                HStack(spacing: 10) {
                                    if enSelection { coche(media) }
                                    LigneMedia(media: media)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu { if !enSelection { menu(media) } }
                            Divider().padding(.leading, 84)
                        }
                    }
                }
            }
        }
        .toolbar {
            if enSelection {
                ToolbarItemGroup(placement: .bottomBar) { barreActions }
            }
        }
        .toolbar(enSelection ? .hidden : .automatic, for: .tabBar)
        .onChange(of: medias.map(\.id)) { _, ids in
            selection.formIntersection(ids)
        }
        .alert("Renommer", isPresented: Binding(
            get: { aRenommer != nil },
            set: { if !$0 { aRenommer = nil } }
        )) {
            TextField("Nom", text: $nouveauNom)
            Button("Annuler", role: .cancel) {}
            Button("Valider") {
                if let media = aRenommer { bib.renommer(media, en: nouveauNom) }
            }
        }
        .confirmationDialog(
            "Supprimer « \(aSupprimer?.nom ?? "") » ?",
            isPresented: Binding(get: { aSupprimer != nil }, set: { if !$0 { aSupprimer = nil } }),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let media = aSupprimer { bib.supprimer(media) }
            }
        }
        .confirmationDialog(
            selection.count <= 1 ? Text("Supprimer ce média ?") : Text("Supprimer \(selection.count) médias ?"),
            isPresented: $confirmerSuppression,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                selectionnes.forEach { bib.supprimer($0) }
                quitterSelection()
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Sélection

    private var enteteSelection: some View {
        HStack {
            if enSelection {
                Button(toutSelectionne ? LocalizedStringKey("Tout désélectionner") : LocalizedStringKey("Tout sélectionner")) {
                    selection = toutSelectionne ? [] : Set(medias.map(\.id))
                }
                Spacer()
                Text(selection.count <= 1 ? "\(selection.count) sélectionné" : "\(selection.count) sélectionnés")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Terminé") { quitterSelection() }.bold()
            } else {
                Text(medias.count <= 1 ? "\(medias.count) média" : "\(medias.count) médias")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Sélectionner") {
                    withAnimation { enSelection = true }
                }
            }
        }
        .font(.subheadline)
        .tint(Theme.accent)
    }

    @ViewBuilder
    private func coche(_ media: Media) -> some View {
        if enSelection {
            let choisi = selection.contains(media.id)
            Image(systemName: choisi ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, choisi ? Theme.accent : Color.black.opacity(0.35))
                .padding(6)
                .shadow(radius: 2)
        }
    }

    private func toucher(_ media: Media) {
        if enSelection {
            if selection.contains(media.id) { selection.remove(media.id) } else { selection.insert(media.id) }
        } else {
            lecteur.lire(media, dans: medias)
        }
    }

    private func quitterSelection() {
        withAnimation {
            enSelection = false
            selection = []
        }
    }

    @ViewBuilder
    private var barreActions: some View {
        let aucun = selection.isEmpty
        Button {
            Task { await enregistrerDansPhotos(selectionnes) }
        } label: {
            if enregistrement { ProgressView() } else { Label("Enregistrer dans Photos", systemImage: "square.and.arrow.down") }
        }
        .disabled(aucun || enregistrement)
        Spacer()
        ShareLink(items: selectionnes.map { bib.url(de: $0) }) {
            Label("Partager", systemImage: "square.and.arrow.up")
        }
        .disabled(aucun)
        Spacer()
        Menu {
            Button("Accueil (aucun dossier)", systemImage: "house") {
                selectionnes.forEach { bib.deplacer($0, vers: nil) }
                quitterSelection()
            }
            ForEach(bib.dossiers) { dossier in
                Button(dossier.nom, systemImage: "folder") {
                    selectionnes.forEach { bib.deplacer($0, vers: dossier.id) }
                    quitterSelection()
                }
            }
            Divider()
            Button("Déplacer vers Privé", systemImage: "lock") {
                selectionnes.forEach { bib.definirPrive($0, true) }
                quitterSelection()
            }
        } label: {
            Label("Déplacer", systemImage: "folder")
        }
        .disabled(aucun)
        Spacer()
        Button(role: .destructive) {
            confirmerSuppression = true
        } label: {
            Label("Supprimer", systemImage: "trash")
        }
        .disabled(aucun)
    }

    private func enregistrerDansPhotos(_ choix: [Media]) async {
        let videos = choix.filter { $0.type == .video }
        guard !videos.isEmpty else {
            message = String(localized: "Seules les vidéos peuvent être enregistrées dans Photos.")
            return
        }
        enregistrement = true
        let reussis = await Phototheque.enregistrer(videos.map { bib.url(de: $0) })
        enregistrement = false
        if reussis == 0 {
            message = String(localized: "Enregistrement impossible. Autorisez Elara à ajouter des photos dans Réglages › Elara › Photos.")
        } else {
            message = reussis == 1
                ? String(localized: "1 vidéo enregistrée dans Photos.")
                : String(localized: "\(reussis) vidéos enregistrées dans Photos.")
            if enSelection { quitterSelection() }
        }
    }

    @ViewBuilder
    private func menu(_ media: Media) -> some View {
        Button("Lire", systemImage: "play.fill") { lecteur.lire(media, dans: medias) }
        Button("Renommer", systemImage: "pencil") {
            nouveauNom = media.nom
            aRenommer = media
        }
        Menu {
            Button("Accueil (aucun dossier)", systemImage: "house") { bib.deplacer(media, vers: nil) }
                .disabled(media.dossier == nil)
            ForEach(bib.dossiers) { dossier in
                Button(dossier.nom, systemImage: "folder") { bib.deplacer(media, vers: dossier.id) }
                    .disabled(media.dossier == dossier.id)
            }
        } label: {
            Label("Déplacer vers un dossier", systemImage: "folder.badge.plus")
        }
        Button("Déplacer vers Privé", systemImage: "lock") { bib.definirPrive(media, true) }
        if media.type == .video {
            Button("Enregistrer dans Photos", systemImage: "square.and.arrow.down") {
                Task { await enregistrerDansPhotos([media]) }
            }
        }
        ShareLink(item: bib.url(de: media)) {
            Label("Partager", systemImage: "square.and.arrow.up")
        }
        Button("Supprimer", systemImage: "trash", role: .destructive) { aSupprimer = media }
    }
}

/// Ligne de la vue en liste.
struct LigneMedia: View {
    @Environment(Bibliotheque.self) private var bib
    let media: Media

    var body: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: 72, height: 54)
                .overlay {
                    if media.type == .video,
                       let image = UIImage(contentsOfFile: bib.urlMiniature(de: media).path) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Theme.degrade
                            Image(systemName: media.type == .audio ? "music.note" : "film")
                                .foregroundStyle(.white)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(media.nom)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("\(media.dureeTexte) · \(media.tailleTexte)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if media.progression > 0.01 {
                    ProgressView(value: media.progression).frame(maxWidth: 120)
                }
            }
            Spacer()
            Image(systemName: media.type == .audio ? "music.note" : "play.circle")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// Tuile de dossier sur l'accueil.
struct TuileDossier: View {
    let dossier: Dossier
    let nombre: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(Theme.bleu)
                .frame(width: 44, height: 44)
                .background(Theme.bleu.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(dossier.nom).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Group {
                    if nombre <= 1 { Text("\(nombre) élément") } else { Text("\(nombre) éléments") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
