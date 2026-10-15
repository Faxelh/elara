import SwiftUI
import UIKit

/// Miniatures gardées en mémoire et décodées hors de l'écran principal :
/// le défilement des grilles reste fluide, même avec des centaines de vidéos.
@MainActor
enum CacheMiniatures {
    static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 400
        return c
    }()

    static func cle(_ url: URL, version: Int) -> NSString { "\(url.path)#\(version)" as NSString }

    static func charger(_ url: URL, version: Int) async -> UIImage? {
        let k = cle(url, version: version)
        if let image = cache.object(forKey: k) { return image }
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let brute = UIImage(contentsOfFile: url.path) else { return nil }
            return brute.preparingForDisplay() ?? brute
        }.value
        if let image { cache.setObject(image, forKey: k) }
        return image
    }
}

/// Miniature d'un média (ou icône pour l'audio), chargée sans bloquer le défilement.
struct ImageMiniature: View {
    @Environment(Bibliotheque.self) private var bib
    let media: Media
    var iconeTaille: Font = .largeTitle

    @State private var image: UIImage?

    var body: some View {
        let url = bib.urlMiniature(de: media)
        let version = bib.versionMiniatures
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.degrade
                Image(systemName: media.type == .audio ? "music.note" : "film")
                    .font(iconeTaille)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .task(id: "\(url.path)#\(version)#\(media.fichier)") {
            guard media.type == .video else { image = nil; return }
            if let deja = CacheMiniatures.cache.object(forKey: CacheMiniatures.cle(url, version: version)) {
                image = deja
                return
            }
            image = await CacheMiniatures.charger(url, version: version)
        }
    }
}
