import SwiftUI
import StoreKit

struct ReglagesView: View {
    @Environment(Bibliotheque.self) private var bib
    @Environment(\.requestReview) private var demanderAvis
    @State private var confirmerCache = false
    @State private var tailleCache: Int64 = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ReglagesLecteurView()
                    } label: {
                        Label("Réglages du lecteur", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink {
                        HistoriqueView()
                    } label: {
                        Label("Historique de lecture", systemImage: "clock.arrow.circlepath")
                    }
                    Button {
                        confirmerCache = true
                    } label: {
                        HStack {
                            Label("Vider le cache", systemImage: "trash")
                            Spacer()
                            Text(Format.taille(tailleCache)).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                Section {
                    Button {
                        demanderAvis()
                    } label: {
                        Label("Noter Elara", systemImage: "star")
                    }
                    .foregroundStyle(.primary)
                    NavigationLink {
                        AProposView()
                    } label: {
                        Label("À propos", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Réglages")
            .task { tailleCache = bib.tailleCache() }
            .confirmationDialog("Vider le cache ?", isPresented: $confirmerCache, titleVisibility: .visible) {
                Button("Vider", role: .destructive) {
                    bib.viderCache()
                    tailleCache = bib.tailleCache()
                }
            } message: {
                Text("Les fichiers temporaires seront supprimés. Vos médias ne sont pas touchés.")
            }
        }
    }
}

struct ReglagesLecteurView: View {
    @AppStorage("modeLectureAuto") private var mode: ModeLectureAuto = .arreter
    @AppStorage("reprendreLecture") private var reprendre = true

    var body: some View {
        Form {
            Section {
                Picker("Lecture automatique", selection: $mode) {
                    ForEach(ModeLectureAuto.allCases) { Text($0.titre).tag($0) }
                }
                Toggle("Reprendre là où je m'étais arrêté", isOn: $reprendre)
            } footer: {
                Text("Pour diffuser sur une TV, utilisez le bouton AirPlay en haut du lecteur.")
            }
        }
        .navigationTitle("Lecteur")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HistoriqueView: View {
    @Environment(Bibliotheque.self) private var bib
    @Environment(LecteurController.self) private var lecteur

    var body: some View {
        List {
            ForEach(bib.historique) { media in
                Button {
                    lecteur.lire(media, dans: bib.historique)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: media.type == .audio ? "music.note" : "film")
                            .foregroundStyle(Theme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(media.nom).lineLimit(1)
                            Text(sousTitre(media))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .overlay {
            if bib.historique.isEmpty {
                ContentUnavailableView(
                    "Aucun historique",
                    systemImage: "clock",
                    description: Text("Les médias que vous lisez apparaîtront ici.")
                )
            }
        }
        .navigationTitle("Historique")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !bib.historique.isEmpty {
                Button("Effacer") { bib.effacerHistorique() }
            }
        }
    }

    private func sousTitre(_ media: Media) -> String {
        var texte = media.derniereLecture?.formatted(.relative(presentation: .named)) ?? ""
        if media.position > 1 {
            texte += " · arrêté à \(Format.duree(media.position))"
        }
        return texte
    }
}

struct AProposView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.degrade)
                .frame(width: 110, height: 110)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(.white)
                }
            Text("Elara").font(.largeTitle.bold())
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Votre lecteur vidéo et audio, entièrement en français.")
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .padding(.top, 48)
        .navigationTitle("À propos")
        .navigationBarTitleDisplayMode(.inline)
    }
}
