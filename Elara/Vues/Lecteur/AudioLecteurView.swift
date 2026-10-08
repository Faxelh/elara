import SwiftUI

struct AudioLecteurView: View {
    @Environment(LecteurController.self) private var lecteur
    @State private var positionGlissee: Double?

    private var duree: Double { max(lecteur.dureeTotale, 1) }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Theme.degrade)
                .frame(width: 260, height: 260)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 96, weight: .light))
                        .foregroundStyle(.white)
                }
                .shadow(color: Theme.accent.opacity(0.35), radius: 24, y: 12)
                .scaleEffect(lecteur.enLecture ? 1 : 0.92)
                .animation(.spring(duration: 0.4), value: lecteur.enLecture)

            VStack(spacing: 6) {
                Text(lecteur.mediaActuel?.nom ?? "")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if lecteur.file.count > 1 {
                    Text("\(lecteur.index + 1) sur \(lecteur.file.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { min(positionGlissee ?? lecteur.tempsActuel, duree) },
                        set: { positionGlissee = $0 }
                    ),
                    in: 0...duree
                ) { enCours in
                    if !enCours, let p = positionGlissee {
                        lecteur.chercher(p)
                        positionGlissee = nil
                    }
                }
                HStack {
                    Text(Format.duree(positionGlissee ?? lecteur.tempsActuel))
                    Spacer()
                    Text(Format.duree(lecteur.dureeTotale))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)

            HStack(spacing: 48) {
                Button { lecteur.precedent() } label: {
                    Image(systemName: "backward.fill").font(.title)
                }
                .accessibilityLabel("Précédent")

                Button { lecteur.basculerLecture() } label: {
                    Image(systemName: lecteur.enLecture ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 76))
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel(lecteur.enLecture ? "Pause" : "Lecture")

                Button { lecteur.suivant() } label: {
                    Image(systemName: "forward.fill").font(.title)
                }
                .accessibilityLabel("Suivant")
            }

            Spacer()
        }
    }
}
