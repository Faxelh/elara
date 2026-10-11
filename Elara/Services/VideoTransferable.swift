import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Permet de récupérer le fichier d'une vidéo choisie dans Photos.
struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { recu in
            let dossier = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
            let destination = dossier.appendingPathComponent(recu.file.lastPathComponent)
            try FileManager.default.copyItem(at: recu.file, to: destination)
            return VideoTransferable(url: destination)
        }
    }
}
