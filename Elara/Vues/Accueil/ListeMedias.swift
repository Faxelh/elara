import SwiftUI

/// Affiche des médias en grille ou en liste, avec le menu d'actions (appui long).
struct ListeMedias: View {
    let medias: [Media]
    let vue: VueAccueil

    @Environment(Bibliotheque.self) private var bib
    @Environment(LecteurController.self) private var lecteur
    @State private var aRenommer: Media?
    @State private var nouveauNom = ""
    @State private var aSupprimer: Media?

    private let colonnes = [GridItem(.adaptive(minimum: 105), spacing: 12)]

    var body: some View {
        Group {
            if vue == .grille {
                LazyVGrid(columns: colonnes, spacing: 14) {
                    ForEach(medias) { media in
                        Button { lecteur.lire(media, dans: medias) } label: {
                            VignetteMedia(media: media)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { menu(media) }
                    }
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(medias) { media in
                        Button { lecteur.lire(media, dans: medias) } label: {
                            LigneMedia(media: media)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { menu(media) }
                        Divider().padding(.leading, 84)
                    }
                }
            }
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
