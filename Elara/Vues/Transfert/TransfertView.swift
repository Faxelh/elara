import SwiftUI
import MultipeerConnectivity

struct TransfertView: View {
    @Environment(Bibliotheque.self) private var bib
    @State private var mode = 0
    @State private var transfert = Transfert()
    @State private var serveur = ServeurWifi()
    @State private var destinataire: MCPeerID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    Text("iPhone à proximité").tag(0)
                    Text("Ordinateur").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if mode == 0 { radar } else { ordinateur }
            }
            .navigationTitle("Transfert")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                transfert.bibliotheque = bib
                serveur.bibliotheque = bib
                if mode == 0 { transfert.demarrer() }
            }
            .onDisappear {
                transfert.arreter()
            }
            .onChange(of: mode) { _, nouveau in
                if nouveau == 0 { transfert.demarrer() } else { transfert.arreter() }
            }
            .sheet(item: Binding(
                get: { destinataire.map { Destinataire(appareil: $0) } },
                set: { destinataire = $0?.appareil }
            )) { cible in
                ChoixMediasView(appareil: cible.appareil) { selection in
                    Task { await transfert.envoyer(selection, a: cible.appareil) }
                }
            }
            .alert(
                "Demande de connexion",
                isPresented: Binding(get: { transfert.invitation != nil }, set: { if !$0 { transfert.invitation = nil } }),
                presenting: transfert.invitation
            ) { invitation in
                Button("Refuser", role: .cancel) { transfert.accepter(invitation, false) }
                Button("Accepter") { transfert.accepter(invitation, true) }
            } message: { invitation in
                Text("« \(invitation.appareil.displayName) » veut échanger des fichiers avec vous.")
            }
        }
    }

    // MARK: - Radar (iPhone ↔ iPhone)

    private var radar: some View {
        VStack(spacing: 16) {
            GeometryReader { geo in
                ZoneRadar(
                    taille: min(geo.size.width, geo.size.height),
                    centre: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2),
                    transfert: transfert,
                    choisir: { destinataire = $0 }
                )
            }
            .frame(maxHeight: 420)

            if let progression = transfert.progression {
                ProgressView(value: progression).padding(.horizontal, 32)
            }
            if let message = transfert.message {
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Text(consigne)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground), in: Capsule())
                .padding(.horizontal)
                .padding(.bottom, 12)
        }
    }

    private var consigne: LocalizedStringKey {
        if transfert.appareils.isEmpty {
            return "Ouvrez Elara sur l'onglet Transfert de l'autre iPhone. Wi‑Fi et Bluetooth doivent être activés."
        }
        return "Touchez un appareil pour vous connecter, puis touchez-le à nouveau pour envoyer des fichiers."
    }

    // MARK: - Ordinateur (navigateur web)

    private var ordinateur: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: serveur.actif ? "wifi" : "wifi.slash")
                    .font(.system(size: 64))
                    .foregroundStyle(serveur.actif ? Theme.vert : .secondary)
                    .padding(.top, 30)

                if serveur.actif, let adresse = serveur.adresse {
                    Text("Sur votre ordinateur, connecté au même Wi‑Fi, ouvrez le navigateur et tapez :")
                        .multilineTextAlignment(.center)
                    Text(adresse)
                        .font(.title2.monospaced().bold())
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    Text("Vous pourrez y déposer des vidéos et musiques, ou télécharger celles d'Elara. Gardez Elara ouverte pendant le transfert.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if let dernier = serveur.dernierFichier {
                        Label("Reçu : \(dernier)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button("Arrêter", role: .destructive) { serveur.arreter() }
                        .buttonStyle(.bordered)
                } else {
                    Text("Transférez des fichiers entre votre ordinateur et Elara par le Wi‑Fi, sans câble.")
                        .multilineTextAlignment(.center)
                    Button {
                        serveur.demarrer()
                    } label: {
                        Label("Démarrer", systemImage: "play.fill")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let message = serveur.message {
                    Text(message).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
            }
            .padding()
        }
    }
}

/// Cercles du radar, avec cet iPhone au centre et les appareils trouvés autour.
struct ZoneRadar: View {
    let taille: CGFloat
    let centre: CGPoint
    let transfert: Transfert
    let choisir: (MCPeerID) -> Void

    var body: some View {
        ZStack {
            ForEach(1..<4) { i in
                CercleRadar(diametre: taille * CGFloat(i) / 3.2)
            }
            OndeRadar(diametre: taille * 0.9, actif: transfert.actif)
            Avatar(nom: transfert.monAppareil.displayName, icone: "iphone", couleur: Theme.accent, etat: nil)
                .position(centre)
            ForEach(Array(transfert.appareils.enumerated()), id: \.element) { element in
                boutonAppareil(element.element, index: element.offset)
            }
        }
    }

    private func position(index: Int) -> CGPoint {
        let total = Double(max(transfert.appareils.count, 1))
        let angle: Double = Double(index) / total * 2 * Double.pi - Double.pi / 2
        let rayon: Double = Double(taille) * 0.34
        return CGPoint(x: Double(centre.x) + rayon * cos(angle), y: Double(centre.y) + rayon * sin(angle))
    }

    private func etat(_ appareil: MCPeerID) -> String? {
        if transfert.estConnecte(appareil) { return String(localized: "Connecté") }
        if transfert.enConnexion.contains(appareil) { return String(localized: "Connexion…") }
        return nil
    }

    private func boutonAppareil(_ appareil: MCPeerID, index: Int) -> some View {
        let connecte = transfert.estConnecte(appareil)
        let couleur: Color = connecte ? Theme.vert : Theme.bleu
        return Button {
            if connecte { choisir(appareil) } else { transfert.inviter(appareil) }
        } label: {
            Avatar(nom: appareil.displayName, icone: "iphone.gen3", couleur: couleur, etat: etat(appareil))
        }
        .buttonStyle(.plain)
        .position(position(index: index))
    }
}

struct CercleRadar: View {
    let diametre: CGFloat
    var body: some View {
        Circle()
            .stroke(Color.primary.opacity(0.08), lineWidth: 2)
            .frame(width: diametre, height: diametre)
    }
}

struct OndeRadar: View {
    let diametre: CGFloat
    let actif: Bool
    var body: some View {
        Circle()
            .fill(Theme.accent.opacity(0.08))
            .frame(width: diametre, height: diametre)
            .scaleEffect(actif ? 1 : 0.4)
            .opacity(actif ? 0 : 1)
            .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false), value: actif)
    }
}

private struct Destinataire: Identifiable {
    let appareil: MCPeerID
    var id: MCPeerID { appareil }
}

struct Avatar: View {
    let nom: String
    let icone: String
    let couleur: Color
    let etat: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icone)
                .font(.system(size: 30))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(couleur.gradient, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(color: couleur.opacity(0.35), radius: 10, y: 4)
            Text(nom).font(.caption.weight(.semibold)).lineLimit(1).frame(maxWidth: 110)
            if let etat {
                Text(etat).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// Choix des médias à envoyer à un autre iPhone.
struct ChoixMediasView: View {
    let appareil: MCPeerID
    let envoyer: ([Media]) -> Void

    @Environment(Bibliotheque.self) private var bib
    @Environment(\.dismiss) private var fermer
    @State private var choisis = Set<UUID>()

    var body: some View {
        NavigationStack {
            List(bib.medias) { media in
                Button {
                    if choisis.contains(media.id) { choisis.remove(media.id) } else { choisis.insert(media.id) }
                } label: {
                    HStack {
                        Image(systemName: choisis.contains(media.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(choisis.contains(media.id) ? Theme.accent : .secondary)
                        LigneMedia(media: media)
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if bib.medias.isEmpty {
                    ContentUnavailableView("Aucun média", systemImage: "shippingbox")
                }
            }
            .navigationTitle("Envoyer à \(appareil.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { fermer() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Envoyer (\(choisis.count))") {
                        envoyer(bib.medias.filter { choisis.contains($0.id) })
                        fermer()
                    }
                    .disabled(choisis.isEmpty)
                }
            }
        }
    }
}
