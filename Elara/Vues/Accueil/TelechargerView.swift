import SwiftUI
import UIKit

/// Téléchargement d'une vidéo ou d'une musique à partir d'un lien direct.
struct TelechargerView: View {
    @Environment(Bibliotheque.self) private var bib
    @Environment(\.dismiss) private var fermer
    @State private var telechargeur = Telechargeur()
    @State private var lien: String
    @State private var prive = false
    @State private var termine: Media?
    private let demarrerSeul: Bool

    /// `lienInitial` : lien déjà rempli (lien copié ou partagé). `demarrerSeul` : lance le téléchargement tout de suite.
    init(lienInitial: String = "", demarrerSeul: Bool = false) {
        _lien = State(initialValue: lienInitial)
        self.demarrerSeul = demarrerSeul && !lienInitial.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://exemple.com/video.mp4", text: $lien, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(telechargeur.enCours)
                    Button("Coller le lien", systemImage: "doc.on.clipboard") {
                        if let texte = UIPasteboard.general.string { lien = texte }
                    }
                    .disabled(telechargeur.enCours)
                    Toggle("Ranger dans le dossier privé", isOn: $prive)
                        .disabled(telechargeur.enCours)
                } header: {
                    Text("Lien du fichier")
                } footer: {
                    if Telechargeur.gereFacebook {
                        Text("Collez un lien direct vers un fichier vidéo ou audio (mp4, mov, mp3, m4a…) ou le lien d'une vidéo Facebook publique.")
                    } else {
                        Text("Collez un lien direct vers un fichier vidéo ou audio (mp4, mov, mp3, m4a…). Les liens YouTube, TikTok, Instagram, Facebook et autres plateformes ne sont pas pris en charge.")
                    }
                }

                #if PERSO
                Section {
                    NavigationLink {
                        ConnexionFacebookView()
                    } label: {
                        Label("Compte Facebook", systemImage: "person.crop.circle")
                    }
                } footer: {
                    Text("Facultatif : connectez-vous pour télécharger les vidéos visibles seulement par vos amis ou dans vos groupes.")
                }
                #endif

                Section {
                    if telechargeur.enCours && telechargeur.recherche {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Recherche de la vidéo…").foregroundStyle(.secondary)
                        }
                        Button("Annuler", role: .destructive) { telechargeur.annuler() }
                    } else if telechargeur.enCours {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: telechargeur.progression)
                            Group {
                                if telechargeur.progression > 0 {
                                    Text("\(Int(telechargeur.progression * 100)) % · \(Format.taille(telechargeur.octetsRecus))")
                                } else {
                                    Text("Téléchargé : \(Format.taille(telechargeur.octetsRecus))")
                                }
                            }
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                        Button("Annuler", role: .destructive) { telechargeur.annuler() }
                    } else {
                        Button {
                            Task { termine = await telechargeur.telecharger(lien, vers: bib, prive: prive) }
                        } label: {
                            Label("Télécharger", systemImage: "arrow.down.circle.fill")
                        }
                        .disabled(lien.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if let erreur = telechargeur.erreur {
                    Section { Text(erreur).foregroundStyle(.red) }
                }
                if let termine {
                    Section {
                        Group {
                            if termine.estPrive {
                                Label("« \(termine.nom) » a été ajouté au dossier privé.", systemImage: "checkmark.circle.fill")
                            } else {
                                Label("« \(termine.nom) » a été ajouté.", systemImage: "checkmark.circle.fill")
                            }
                        }
                        .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Télécharger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(termine == nil ? LocalizedStringKey("Fermer") : LocalizedStringKey("Terminé")) {
                        telechargeur.annuler()
                        fermer()
                    }
                }
            }
            .interactiveDismissDisabled(telechargeur.enCours)
            .task {
                if demarrerSeul && termine == nil && !telechargeur.enCours {
                    termine = await telechargeur.telecharger(lien, vers: bib, prive: prive)
                }
            }
        }
    }
}
