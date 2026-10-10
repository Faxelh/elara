#if PERSO
import Foundation
import WebKit

/// Version perso uniquement (installée avec Sideloadly) : retrouve le fichier mp4
/// d'une vidéo Facebook publique (ou visible par le compte connecté dans Elara).
/// Ce fichier n'est pas compilé dans la version App Store.
@MainActor
enum ExtracteurFacebook {
    static let domaines = ["facebook.com", "fb.watch", "fb.com", "fb.gg"]

    static let agentMobile = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    static let agentOrdinateur = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    static func gere(_ hote: String) -> Bool {
        domaines.contains { hote == $0 || hote.hasSuffix("." + $0) }
    }

    /// Renvoie le lien direct vers le fichier vidéo.
    static func lienVideo(depuis url: URL) async throws -> URL {
        // La connexion faite dans l'onglet Facebook sert aussi aux liens collés.
        await partagerConnexion()
        // 1. Lecture rapide de la page, sans navigateur.
        for agent in [agentOrdinateur, agentMobile] {
            if let html = try? await page(url, agent: agent), let lien = chercher(dans: html) {
                return lien
            }
        }
        // 2. Navigateur caché (exécute la page et utilise la connexion Facebook faite dans Elara).
        if let lien = await NavigateurCache.chercherVideo(url) {
            return lien
        }
        throw ErreurTelechargement(message: String(localized: "Vidéo Facebook introuvable. Elle est peut-être privée ou réservée aux membres : connectez-vous à Facebook dans Elara puis réessayez."))
    }

    /// Copie les cookies Facebook du navigateur intégré vers les requêtes de l'app.
    private static func partagerConnexion() async {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        for cookie in cookies where domaines.contains(where: { cookie.domain.hasSuffix($0) }) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    private static func page(_ url: URL, agent: String) async throws -> String {
        var requete = URLRequest(url: url, timeoutInterval: 20)
        requete.setValue(agent, forHTTPHeaderField: "User-Agent")
        requete.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        requete.setValue("fr-FR,fr;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        requete.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        requete.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        let (donnees, _) = try await URLSession.shared.data(for: requete)
        return String(decoding: donnees, as: UTF8.self)
    }

    /// Cherche, dans le code de la page, le lien du fichier vidéo (HD en priorité).
    nonisolated static func chercher(dans html: String) -> URL? {
        let cles = [
            "browser_native_hd_url", "playable_url_quality_hd", "hd_src_no_ratelimit", "hd_src",
            "browser_native_sd_url", "playable_url", "sd_src_no_ratelimit", "sd_src"
        ]
        for cle in cles {
            let motif = #""?"# + cle + #""?\s*:\s*"((?:[^"\\]|\\.)+)""#
            if let brut = premiereCapture(motif, dans: html), let lien = decoderJSON(brut) {
                return lien
            }
        }
        let meta = #"<meta[^>]+property="og:video(?::secure_url|:url)?"[^>]+content="([^"]+)""#
        if let brut = premiereCapture(meta, dans: html) {
            let propre = brut.replacingOccurrences(of: "&amp;", with: "&")
            if let lien = URL(string: propre), lien.scheme == "https" { return lien }
        }
        return nil
    }

    nonisolated private static func premiereCapture(_ motif: String, dans texte: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: motif) else { return nil }
        let ns = texte as NSString
        guard let resultat = regex.firstMatch(in: texte, range: NSRange(location: 0, length: ns.length)),
              resultat.numberOfRanges > 1 else { return nil }
        return ns.substring(with: resultat.range(at: 1))
    }

    nonisolated private static func decoderJSON(_ brut: String) -> URL? {
        guard let texte = try? JSONDecoder().decode(String.self, from: Data(("\"" + brut + "\"").utf8)),
              let lien = URL(string: texte),
              lien.scheme == "https" else { return nil }
        return lien
    }

    /// Déconnecte Facebook dans Elara.
    static func deconnecter() async {
        let magasin = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let enregistrements = await magasin.dataRecords(ofTypes: types)
        let facebook = enregistrements.filter { r in domaines.contains { r.displayName.contains($0) } }
        await magasin.removeData(ofTypes: types, for: facebook)
    }
}

/// Ouvre la page dans un navigateur invisible et lit son code une fois chargé.
@MainActor
enum NavigateurCache {
    static func chercherVideo(_ url: URL) async -> URL? {
        // Version ordinateur d'abord (les liens des fichiers y sont plus souvent présents), puis mobile.
        if let lien = await essayer(url, agent: ExtracteurFacebook.agentOrdinateur, secondes: 12) { return lien }
        return await essayer(url, agent: ExtracteurFacebook.agentMobile, secondes: 10)
    }

    private static func essayer(_ url: URL, agent: String, secondes: Int) async -> URL? {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        #if PERSO
        // Même script que l'onglet Facebook : il note les liens des fichiers vidéo reçus par la page.
        configuration.userContentController.addUserScript(
            WKUserScript(source: NavigateurFacebook.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        #endif
        let vue = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        vue.customUserAgent = agent
        vue.load(URLRequest(url: url))
        defer { vue.stopLoading() }

        let script = """
        (function() {
          var v = Array.from(document.querySelectorAll('video'))
            .map(function(e) { return e.currentSrc || e.src || ''; })
            .find(function(s) { return s.indexOf('https://') === 0; });
          return JSON.stringify({ html: document.documentElement.outerHTML, video: v || '',
                                  page: location.href, videos: JSON.stringify(window.__elaraVideos || {}) });
        })()
        """
        for _ in 0..<secondes {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return nil }
            guard let json = await evaluer(script, dans: vue),
                  let objet = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String] else { continue }
            if let video = objet["video"], !video.isEmpty, let lien = URL(string: video) { return lien }
            if let lien = lienCapture(objet) { return lien }
            if let html = objet["html"], let lien = ExtracteurFacebook.chercher(dans: html) { return lien }
        }
        return nil
    }

    /// Lien noté par le script : celui dont le numéro est dans l'adresse, sinon le seul trouvé.
    private static func lienCapture(_ objet: [String: String]) -> URL? {
        guard let texte = objet["videos"],
              let videos = try? JSONSerialization.jsonObject(with: Data(texte.utf8)) as? [String: [String: String]],
              !videos.isEmpty else { return nil }
        #if PERSO
        if let page = objet["page"], let id = NavigateurFacebook.numeroVideo(dans: page), let v = videos[id] {
            return (v["hd"] ?? v["sd"]).flatMap(URL.init(string:))
        }
        #endif
        if videos.count == 1, let v = videos.values.first {
            return (v["hd"] ?? v["sd"]).flatMap(URL.init(string:))
        }
        return nil
    }

    private static func evaluer(_ script: String, dans vue: WKWebView) async -> String? {
        await withCheckedContinuation { suite in
            vue.evaluateJavaScript(script) { resultat, _ in
                suite.resume(returning: resultat as? String)
            }
        }
    }
}
#endif
