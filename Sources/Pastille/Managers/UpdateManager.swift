import AppKit
import Combine
import CryptoKit

/// Version de Pastille publiée sur GitHub.
struct AppRelease: Equatable {
    var version: String
    /// Page de la release (notes de version).
    var page: URL
    var archive: URL
    /// Signature Ed25519 de l'archive, faite avec la clé privée du développeur.
    var signature: URL
}

/// Cherche les nouvelles versions sur GitHub (au lancement puis toutes les 6 h) et les installe en un clic.
/// Une archive n'est installée que si sa signature correspond à la clé publique intégrée à l'app :
/// même un compte GitHub piraté ne pourrait pas pousser une fausse version.
@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    enum State: Equatable {
        case idle, checking, upToDate
        case available(AppRelease)
        case installing(AppRelease)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// Nouvelle version trouvée : annoncée une seule fois dans la pastille.
    let announced = PassthroughSubject<String, Never>()

    nonisolated static let repository = "Zeky69/Pastille"
    nonisolated static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
    private static let announcedVersionKey = "update.announcedVersion"
    private var timer: Timer?

    var available: AppRelease? {
        if case let .available(release) = state { release } else { nil }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            MainActor.assumeIsolated { UpdateManager.shared.checkIfEnabled() }
        }
        timer?.tolerance = 600
        // Pas tout de suite : le Mac vient peut-être de démarrer et le réseau n'est pas prêt.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { UpdateManager.shared.checkIfEnabled() }
    }

    private func checkIfEnabled() {
        guard Settings.checkForUpdates, available == nil else { return }
        check()
    }

    func check() {
        switch state {
        case .checking, .installing: return
        default: break
        }
        state = .checking
        Task {
            do {
                guard let release = try await Self.fetchLatest(),
                      Self.isNewer(release.version, than: Self.currentVersion) else {
                    state = .upToDate
                    return
                }
                state = .available(release)
                if UserDefaults.standard.string(forKey: Self.announcedVersionKey) != release.version {
                    UserDefaults.standard.set(release.version, forKey: Self.announcedVersionKey)
                    announced.send(release.version)
                }
            } catch {
                state = .failed("GitHub ne répond pas. Réessaie plus tard.")
            }
        }
    }

    /// Télécharge, vérifie, remplace l'app et la relance.
    func install() {
        guard let release = available else { return }
        state = .installing(release)
        let installed = Bundle.main.bundleURL
        let bundleID = Bundle.main.bundleIdentifier ?? "com.macky.pastille"
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "PastilleUpdatePublicKey") as? String
        Task {
            do {
                let app = try await Self.download(release, next: installed, bundleID: bundleID, publicKey: publicKey)
                try Self.replace(installed, with: app)
                Self.relaunch(installed)
            } catch {
                state = .failed((error as? UpdateError)?.message ?? "Le téléchargement a échoué. Réessaie plus tard.")
            }
        }
    }

    /// Notes de la version trouvée, ou la liste des versions.
    func openReleasePage() {
        let page: URL? = switch state {
        case let .available(release), let .installing(release): release.page
        default: URL(string: "https://github.com/\(Self.repository)/releases")
        }
        if let page { NSWorkspace.shared.open(page) }
    }

    // MARK: - GitHub

    nonisolated static func fetchLatest() async throws -> AppRelease? {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Pastille/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }  // aucune release publiée
        guard status == 200 else { throw UpdateError.network }
        return parseRelease(data)
    }

    /// Release publiée (ni brouillon ni préversion) avec son archive .zip et sa signature .zip.sig.
    nonisolated static func parseRelease(_ data: Data) -> AppRelease? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
              let assets = json["assets"] as? [[String: Any]] else { return nil }
        func asset(endingWith suffix: String) -> URL? {
            assets.first { ($0["name"] as? String)?.hasSuffix(suffix) == true }
                .flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
                .flatMap { $0.scheme == "https" ? $0 : nil }
        }
        guard let archive = asset(endingWith: ".zip"), let signature = asset(endingWith: ".zip.sig") else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return AppRelease(version: version, page: page, archive: archive, signature: signature)
    }

    /// « 0.10.0 » est plus récent que « 0.9.2 » ; « 1.0 » et « 1.0.0 » sont égales.
    nonisolated static func isNewer(_ remote: String, than local: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let a = parts(remote), b = parts(local)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Installation

    enum UpdateError: Error, Equatable {
        case network, missingKey, badSignature, badArchive, wrongApp, cannotReplace

        var message: String {
            switch self {
            case .network: "Le téléchargement a échoué. Réessaie plus tard."
            case .missingKey: "Cette version de Pastille ne sait pas vérifier les mises à jour : télécharge-la depuis GitHub."
            case .badSignature: "La mise à jour n'est pas signée par Pastille : elle a été refusée."
            case .badArchive: "L'archive téléchargée est abîmée."
            case .wrongApp: "L'archive ne contient pas la bonne version de Pastille."
            case .cannotReplace: "Impossible de remplacer Pastille (droits insuffisants ?). Installe-la depuis GitHub."
            }
        }
    }

    /// Archive vérifiée puis décompressée à côté de l'app installée (même volume, pour un remplacement atomique).
    nonisolated static func download(_ release: AppRelease, next installed: URL, bundleID: String, publicKey: String?) async throws -> URL {
        let (archive, archiveResponse) = try await URLSession.shared.data(from: release.archive)
        let (signature, signatureResponse) = try await URLSession.shared.data(from: release.signature)
        guard (archiveResponse as? HTTPURLResponse)?.statusCode == 200,
              (signatureResponse as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.network }
        try verify(archive, signature: signature, publicKey: publicKey)

        let folder: URL
        do {
            folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                 appropriateFor: installed, create: true)
        } catch {
            throw UpdateError.cannotReplace
        }
        let zip = folder.appending(path: "Pastille.zip")
        do { try archive.write(to: zip) } catch { throw UpdateError.cannotReplace }
        return try extract(zip, into: folder, bundleID: bundleID, version: release.version)
    }

    nonisolated static func verify(_ data: Data, signature: Data, publicKey: String?) throws {
        guard let publicKey, let raw = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { throw UpdateError.missingKey }
        let text = String(decoding: signature, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bytes = Data(base64Encoded: text), key.isValidSignature(bytes, for: data) else {
            throw UpdateError.badSignature
        }
    }

    nonisolated static func extract(_ zip: URL, into folder: URL, bundleID: String, version: String) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, folder.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw UpdateError.badArchive }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.badArchive }

        let app = folder.appending(path: "Pastille.app")
        guard let info = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == bundleID,
              info["CFBundleShortVersionString"] as? String == version else { throw UpdateError.wrongApp }
        return app
    }

    nonisolated static func replace(_ installed: URL, with new: URL) throws {
        do {
            _ = try FileManager.default.replaceItemAt(installed, withItemAt: new)
        } catch {
            throw UpdateError.cannotReplace
        }
    }

    /// Relance la nouvelle version dès que celle-ci s'est fermée.
    private static func relaunch(_ app: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Chemin et numéro passés en arguments (jamais insérés dans la commande).
        process.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"",
                             "sh", String(getpid()), app.path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
