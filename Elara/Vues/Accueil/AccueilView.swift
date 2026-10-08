import SwiftUI

struct AccueilView: View {
    @Environment(Bibliotheque.self) private var bib
    @AppStorage(Cle.vueAccueil) private var vue: VueAccueil = .grille
    @AppStorage(Cle.triAccueil) private var tri: TriMedias = .date
    @AppStorage(Cle.triCroissant) private var croissant = false

    @State private var afficherPhotos = false
    @State private var afficherFichiers = false
    @State private var afficherPrive = false
    @State private var afficherTelechargement = false
    @State private var nouveauDossier = false
    @State private var filtre: Filtre = .tout

    enum Filtre: String, CaseIterable, Identifiable {
        case tout = "Tout", videos = "Vidéos", audio = "Audio"
        var id: String { rawValue }
    }

    private var mediasAffiches: [Media] {
        let racine = bib.mediasDans(nil)
        let filtres: [Media]
        switch filtre {
        case .tout: filtres = racine
        case .videos: filtres = racine.filter { $0.type == .video }
        case .audio: filtres = racine.filter { $0.type == .audio }
        }
        return tri.trier(filtres, croissant: croissant)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        CarteRaccourci(titre: "Photos", icone: "photo.on.rectangle.angled", couleur: Theme.bleu) {
                            afficherPhotos = true
                        }
                        CarteRaccourci(titre: "Fichiers", icone: "folder.fill", couleur: Theme.vert) {
                            afficherFichiers = true
                        }
                        CarteRaccourci(titre: "Privé", icone: "lock.fill", couleur: Theme.corail) {
                            afficherPrive = true
                        }
                    }

                    if !bib.dossiers.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(bib.dossiers) { dossier in
                                NavigationLink(value: dossier) {
                                    TuileDossier(dossier: dossier, nombre: bib.nombre(dans: dossier))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Picker("Filtre", selection: $filtre) {
                        ForEach(Filtre.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if bib.importEnCours {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Importation en cours…").foregroundStyle(.secondary)
                        }
                    }

                    if mediasAffiches.isEmpty {
                        ContentUnavailableView(
                            "Aucun média",
                            systemImage: "shippingbox",
                            description: Text("Touchez + pour importer des vidéos ou de la musique, télécharger un lien ou créer un dossier.")
                        )
                        .padding(.top, 30)
                    } else {
                        ListeMedias(medias: mediasAffiches, vue: vue)
                    }
                }
                .padding()
            }
            .navigationTitle("Elara")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Importer depuis Photos", systemImage: "photo") { afficherPhotos = true }
                        Button("Importer depuis Fichiers", systemImage: "folder") { afficherFichiers = true }
                        Button("Télécharger depuis un lien", systemImage: "arrow.down.circle") {
                            afficherTelechargement = true
                        }
                        Divider()
                        Button("Nouveau dossier", systemImage: "folder.badge.plus") { nouveauDossier = true }
                    } label: {
                        Image(systemName: "plus.circle").font(.title3)
                    }
                    .accessibilityLabel("Ajouter")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    MenuAffichage()
                }
            }
            .navigationDestination(for: Dossier.self) { dossier in
                DossierView(dossierID: dossier.id)
            }
            .navigationDestination(isPresented: $afficherPrive) {
                CoffreView()
            }
            .importMedias(photos: $afficherPhotos, fichiers: $afficherFichiers)
            .sheet(isPresented: $afficherTelechargement) {
                TelechargerView()
            }
            .alerteDossier($nouveauDossier) { nom in
                bib.creerDossier(nom)
            }
            .refreshable { await bib.synchroniserDossier() }
            .task { await bib.synchroniserDossier() }
        }
    }
}

/// Contenu d'un dossier créé par l'utilisateur.
struct DossierView: View {
    let dossierID: UUID

    @Environment(Bibliotheque.self) private var bib
    @Environment(\.dismiss) private var retour
    @AppStorage(Cle.vueAccueil) private var vue: VueAccueil = .grille
    @AppStorage(Cle.triAccueil) private var tri: TriMedias = .date
    @AppStorage(Cle.triCroissant) private var croissant = false
    @State private var afficherPhotos = false
    @State private var afficherFichiers = false
    @State private var renommer = false
    @State private var confirmerSuppression = false

    private var dossier: Dossier? { bib.dossiers.first { $0.id == dossierID } }

    var body: some View {
        let medias = tri.trier(bib.mediasDans(dossierID), croissant: croissant)
        ScrollView {
            if medias.isEmpty {
                ContentUnavailableView(
                    "Dossier vide",
                    systemImage: "folder",
                    description: Text("Touchez + pour importer ici, ou appuyez longuement sur un média de l'accueil puis « Déplacer vers un dossier ».")
                )
                .padding(.top, 60)
            } else {
                ListeMedias(medias: medias, vue: vue).padding()
            }
        }
        .navigationTitle(dossier?.nom ?? "Dossier")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Importer depuis Photos", systemImage: "photo") { afficherPhotos = true }
                    Button("Importer depuis Fichiers", systemImage: "folder") { afficherFichiers = true }
                } label: {
                    Image(systemName: "plus.circle").font(.title3)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Renommer le dossier", systemImage: "pencil") { renommer = true }
                    Button("Supprimer le dossier", systemImage: "trash", role: .destructive) {
                        confirmerSuppression = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
            }
        }
        .importMedias(photos: $afficherPhotos, fichiers: $afficherFichiers, dossier: dossierID)
        .alerteDossier($renommer, titre: "Renommer le dossier", valeurInitiale: dossier?.nom ?? "") { nom in
            if let dossier { bib.renommerDossier(dossier, en: nom) }
        }
        .confirmationDialog("Supprimer ce dossier ?", isPresented: $confirmerSuppression, titleVisibility: .visible) {
            Button("Supprimer le dossier", role: .destructive) {
                if let dossier { bib.supprimerDossier(dossier) }
                retour()
            }
        } message: {
            Text("Les médias qu'il contient ne sont pas supprimés : ils reviennent sur l'accueil.")
        }
    }
}

// MARK: - Composants

struct CarteRaccourci: View {
    let titre: LocalizedStringKey
    let icone: String
    let couleur: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icone)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(couleur)
                HStack(spacing: 4) {
                    Text(titre).font(.subheadline.bold())
                    Image(systemName: "chevron.right").font(.caption2.bold())
                }
                .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(couleur.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct VignetteMedia: View {
    @Environment(Bibliotheque.self) private var bib
    let media: Media

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { apercu }
                .overlay(alignment: .bottom) {
                    VStack(spacing: 4) {
                        HStack {
                            Pastille(texte: media.dureeTexte)
                            Spacer(minLength: 2)
                            Pastille(texte: media.tailleTexte)
                        }
                        if media.progression > 0.01 {
                            ProgressView(value: media.progression)
                                .tint(.white)
                        }
                    }
                    .padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(media.nom)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var apercu: some View {
        if media.type == .video,
           let image = UIImage(contentsOfFile: bib.urlMiniature(de: media).path) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Theme.degrade
                Image(systemName: media.type == .audio ? "music.note" : "film")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

struct Pastille: View {
    let texte: String
    var body: some View {
        Text(texte)
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
    }
}
