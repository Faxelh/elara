import Foundation
import AVFoundation
import MediaPlayer
import Observation

/// Lecteur unique de l'app (vidéo et audio), avec file de lecture et commandes de l'écran verrouillé.
@MainActor
@Observable
final class LecteurController {
    var estAffiche = false
    private(set) var file: [Media] = []
    private(set) var index = 0
    private(set) var enLecture = false
    private(set) var tempsActuel: Double = 0
    private(set) var dureeTotale: Double = 0

    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private let bibliotheque: Bibliotheque
    @ObservationIgnored private var observateurTemps: Any?
    @ObservationIgnored private var observateurFin: NSObjectProtocol?

    var mediaActuel: Media? {
        file.indices.contains(index) ? file[index] : nil
    }

    init(bibliotheque: Bibliotheque) {
        self.bibliotheque = bibliotheque

        observateurTemps = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] temps in
            MainActor.assumeIsolated {
                guard let self else { return }
                if temps.seconds.isFinite { self.tempsActuel = temps.seconds }
                self.enLecture = self.player.rate != 0
            }
        }

        observateurFin = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let item = notification.object as? AVPlayerItem
            MainActor.assumeIsolated {
                guard let self, item === self.player.currentItem else { return }
                self.finDeLecture()
            }
        }

        configurerCommandesDistantes()
    }

    // MARK: - Commandes

    func lire(_ media: Media, dans liste: [Media]) {
        sauverPosition()
        file = liste.isEmpty ? [media] : liste
        index = file.firstIndex { $0.id == media.id } ?? 0
        charger()
        estAffiche = true
    }

    func basculerLecture() {
        if player.rate == 0 { player.play() } else { player.pause() }
        enLecture = player.rate != 0
        mettreAJourNowPlaying()
    }

    func suivant() {
        guard !file.isEmpty else { return }
        sauverPosition()
        index = (index + 1) % file.count
        charger()
    }

    func precedent() {
        guard !file.isEmpty else { return }
        if player.currentTime().seconds > 3 {
            chercher(0)
            return
        }
        sauverPosition()
        index = (index - 1 + file.count) % file.count
        charger()
    }

    func chercher(_ secondes: Double) {
        player.seek(to: CMTime(seconds: secondes, preferredTimescale: 600))
        tempsActuel = secondes
        mettreAJourNowPlaying()
    }

    func fermer() {
        sauverPosition()
        player.pause()
        enLecture = false
        estAffiche = false
    }

    func sauverPosition() {
        guard let media = mediaActuel else { return }
        let s = player.currentTime().seconds
        if s.isFinite { bibliotheque.memoriserPosition(media.id, s) }
    }

    // MARK: - Interne

    private func charger() {
        guard let enFile = mediaActuel else { return }
        let media = bibliotheque.media(id: enFile.id) ?? enFile
        player.replaceCurrentItem(with: AVPlayerItem(url: bibliotheque.url(de: media)))
        dureeTotale = media.duree
        tempsActuel = 0

        let reprendre = UserDefaults.standard.bool(forKey: "reprendreLecture")
        if reprendre, media.position > 2, media.position < media.duree - 2 {
            player.seek(to: CMTime(seconds: media.position, preferredTimescale: 600))
            tempsActuel = media.position
        }
        player.play()
        enLecture = true
        bibliotheque.memoriserPosition(media.id, tempsActuel)
        mettreAJourNowPlaying()
    }

    private func finDeLecture() {
        if let media = mediaActuel { bibliotheque.memoriserPosition(media.id, 0) }
        let brut = UserDefaults.standard.string(forKey: "modeLectureAuto") ?? ""
        switch ModeLectureAuto(rawValue: brut) ?? .arreter {
        case .arreter:
            enLecture = false
        case .repeterUn:
            player.seek(to: .zero)
            player.play()
        case .enchainer:
            if index + 1 < file.count {
                index += 1
                charger()
            } else {
                enLecture = false
            }
        case .boucle:
            index = (index + 1) % max(file.count, 1)
            charger()
        case .retourListe:
            fermer()
        }
    }

    private func mettreAJourNowPlaying() {
        guard let media = mediaActuel else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let ecoule = player.currentTime().seconds
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: media.nom,
            MPMediaItemPropertyArtist: "Elara",
            MPMediaItemPropertyPlaybackDuration: media.duree,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: ecoule.isFinite ? ecoule : 0,
            MPNowPlayingInfoPropertyPlaybackRate: player.rate
        ]
    }

    private func configurerCommandesDistantes() {
        let centre = MPRemoteCommandCenter.shared()
        centre.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.play(); self?.mettreAJourNowPlaying() }
            return .success
        }
        centre.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.pause(); self?.mettreAJourNowPlaying() }
            return .success
        }
        centre.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.basculerLecture() }
            return .success
        }
        centre.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.suivant() }
            return .success
        }
        centre.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.precedent() }
            return .success
        }
        centre.changePlaybackPositionCommand.addTarget { [weak self] evenement in
            guard let e = evenement as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = e.positionTime
            Task { @MainActor in self?.chercher(position) }
            return .success
        }
    }
}
