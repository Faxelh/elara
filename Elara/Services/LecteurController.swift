import Foundation
import AVFoundation
import AVKit
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
    private(set) var vitesse: Float = 1
    /// Vrai pendant l'image dans l'image : l'écran du lecteur est fermé, la vidéo continue dans la fenêtre flottante.
    var enPip = false
    @ObservationIgnored var pip: AVPictureInPictureController?

    /// Répéter la vidéo en cours (bouton du lecteur, en plus du réglage « Lecture automatique »).
    var repeterUn = false
    /// Minuterie de mise en veille : pause à cette heure, ou à la fin de la vidéo.
    private(set) var minuterieFin: Date?
    private(set) var minuterieFinVideo = false
    @ObservationIgnored private var tacheMinuterie: Task<Void, Never>?

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

    /// Vrai quand la vidéo est arrivée au bout : le bouton devient « Revoir ».
    private(set) var termine = false

    func basculerLecture() {
        if player.rate == 0 {
            // Vidéo terminée : on la reprend depuis le début (sinon « Lecture » ne fait rien).
            let fin = player.currentItem.map { $0.duration.seconds } ?? dureeTotale
            let position = player.currentTime().seconds
            if termine || (fin.isFinite && fin > 0 && position >= fin - 0.3) {
                player.seek(to: .zero)
                tempsActuel = 0
            }
            termine = false
            player.play()
        } else {
            player.pause()
        }
        enLecture = player.rate != 0
        mettreAJourNowPlaying()
    }

    func basculerPip() {
        guard let pip else { return }
        if pip.isPictureInPictureActive { pip.stopPictureInPicture() } else { pip.startPictureInPicture() }
    }

    func definirVitesse(_ v: Float) {
        vitesse = v
        player.defaultRate = v
        if player.rate != 0 { player.rate = v }
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
        termine = false
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
        termine = false
        guard let enFile = mediaActuel else { return }
        let media = bibliotheque.media(id: enFile.id) ?? enFile
        player.replaceCurrentItem(with: AVPlayerItem(url: bibliotheque.url(de: media)))
        player.allowsExternalPlayback = Cle.booleen(Cle.airplay, defaut: true)
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

    // MARK: - Minuterie

    /// `minutes = nil` : s'arrêter à la fin de la vidéo en cours.
    func programmerMinuterie(minutes: Int?) {
        annulerMinuterie()
        guard let minutes else {
            minuterieFinVideo = true
            return
        }
        let fin = Date().addingTimeInterval(TimeInterval(minutes * 60))
        minuterieFin = fin
        tacheMinuterie = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(minutes * 60)))
            guard !Task.isCancelled, let self else { return }
            self.player.pause()
            self.enLecture = false
            self.sauverPosition()
            self.minuterieFin = nil
        }
    }

    func annulerMinuterie() {
        tacheMinuterie?.cancel()
        tacheMinuterie = nil
        minuterieFin = nil
        minuterieFinVideo = false
    }

    var minuterieActive: Bool { minuterieFin != nil || minuterieFinVideo }

    // MARK: - Pistes audio et sous-titres

    /// Pistes proposées par la vidéo (langues audio, sous-titres intégrés).
    func pistes(_ type: AVMediaCharacteristic) async -> (groupe: AVMediaSelectionGroup, options: [AVMediaSelectionOption])? {
        guard let item = player.currentItem,
              let groupe = try? await item.asset.loadMediaSelectionGroup(for: type),
              !groupe.options.isEmpty else { return nil }
        return (groupe, groupe.options)
    }

    func choisir(_ option: AVMediaSelectionOption?, dans groupe: AVMediaSelectionGroup) {
        player.currentItem?.select(option, in: groupe)
    }

    func optionActuelle(dans groupe: AVMediaSelectionGroup) -> AVMediaSelectionOption? {
        player.currentItem?.currentMediaSelection.selectedMediaOption(in: groupe)
    }

    private func finDeLecture() {
        if let media = mediaActuel { bibliotheque.memoriserPosition(media.id, 0) }
        if minuterieFinVideo {
            annulerMinuterie()
            enLecture = false
            termine = true
            return
        }
        if repeterUn {
            player.seek(to: .zero)
            player.play()
            return
        }
        let brut = UserDefaults.standard.string(forKey: "modeLectureAuto") ?? ""
        switch ModeLectureAuto(rawValue: brut) ?? .arreter {
        case .arreter:
            enLecture = false
            termine = true
        case .repeterUn:
            player.seek(to: .zero)
            player.play()
        case .enchainer:
            if index + 1 < file.count {
                index += 1
                charger()
            } else {
                enLecture = false
                termine = true
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
            MPMediaItemPropertyArtist: (UserDefaults.standard.string(forKey: NomApp.cle)).flatMap { $0.isEmpty ? nil : $0 } ?? NomApp.nomIcone,
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
