import SwiftUI

enum Theme {
    static let accent = Color(red: 0.45, green: 0.36, blue: 0.96)
    static let bleu = Color(red: 0.22, green: 0.55, blue: 0.98)
    static let vert = Color(red: 0.20, green: 0.70, blue: 0.45)
    static let corail = Color(red: 0.96, green: 0.42, blue: 0.38)

    static let degrade = LinearGradient(
        colors: [Color(red: 0.56, green: 0.40, blue: 0.98), bleu],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

enum Format {
    /// 125 s -> "02:05", 3725 s -> "1:02:05"
    static func duree(_ secondes: Double) -> String {
        guard secondes.isFinite, secondes > 0 else { return "00:00" }
        let total = Int(secondes.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    static func taille(_ octets: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: octets, countStyle: .file)
    }
}
