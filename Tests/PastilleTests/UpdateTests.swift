import CryptoKit
import Foundation
import Testing
@testable import Pastille

/// Recherche et installation des mises à jour.
@Suite struct UpdateTests {
    typealias Updates = UpdateManager

    @Test(arguments: [
        ("0.2.0", "0.1.0", true),
        ("0.10.0", "0.9.2", true),
        ("1.0", "0.99.99", true),
        ("0.1.1", "0.1", true),
        ("0.1.0", "0.1.0", false),
        ("1.0", "1.0.0", false),
        ("0.1.0", "0.2.0", false),
        ("0.9", "0.10", false),
        ("", "0.1.0", false),
    ])
    func comparesVersions(remote: String, local: String, newer: Bool) {
        #expect(Updates.isNewer(remote, than: local) == newer)
    }

    // MARK: - Réponse de GitHub

    private func releaseJSON(tag: String = "v0.2.0", draft: Bool = false, prerelease: Bool = false,
                             assets: [String] = ["Pastille-0.2.0.zip", "Pastille-0.2.0.zip.sig"],
                             scheme: String = "https") -> Data {
        let list = assets.map { name in
            ["name": name, "browser_download_url": "\(scheme)://github.com/Zeky69/Pastille/releases/download/\(tag)/\(name)"]
        }
        let json: [String: Any] = [
            "tag_name": tag, "draft": draft, "prerelease": prerelease,
            "html_url": "https://github.com/Zeky69/Pastille/releases/tag/\(tag)", "assets": list,
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    @Test func readsAPublishedRelease() throws {
        let release = try #require(Updates.parseRelease(releaseJSON()))
        #expect(release.version == "0.2.0")
        #expect(release.archive.lastPathComponent == "Pastille-0.2.0.zip")
        #expect(release.signature.lastPathComponent == "Pastille-0.2.0.zip.sig")
    }

    @Test func ignoresUnusableReleases() {
        #expect(Updates.parseRelease(releaseJSON(draft: true)) == nil)
        #expect(Updates.parseRelease(releaseJSON(prerelease: true)) == nil)
        #expect(Updates.parseRelease(releaseJSON(assets: ["Pastille-0.2.0.zip"])) == nil)  // pas signée
        #expect(Updates.parseRelease(releaseJSON(assets: [])) == nil)
        #expect(Updates.parseRelease(releaseJSON(scheme: "http")) == nil)                  // jamais sans https
        #expect(Updates.parseRelease(Data("{\"message\":\"Not Found\"}".utf8)) == nil)
        #expect(Updates.parseRelease(Data("pas du json".utf8)) == nil)
    }

    // MARK: - Signature

    private let key = Curve25519.Signing.PrivateKey()
    private var publicKey: String { key.publicKey.rawRepresentation.base64EncodedString() }
    private func sign(_ data: Data) throws -> Data {
        Data(try key.signature(for: data).base64EncodedString().utf8)
    }

    @Test func acceptsOnlyTheRightSignature() throws {
        let archive = Data("archive de Pastille".utf8)
        let signature = try sign(archive)
        try Updates.verify(archive, signature: signature, publicKey: publicKey)
        // Avec un retour à la ligne final, comme écrit par un éditeur.
        try Updates.verify(archive, signature: signature + Data("\n".utf8), publicKey: publicKey)

        #expect(throws: Updates.UpdateError.badSignature) {
            try Updates.verify(Data("archive modifiée".utf8), signature: signature, publicKey: publicKey)
        }
        let otherKey = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        #expect(throws: Updates.UpdateError.badSignature) {
            try Updates.verify(archive, signature: signature, publicKey: otherKey)
        }
        #expect(throws: Updates.UpdateError.badSignature) {
            try Updates.verify(archive, signature: Data("n'importe quoi".utf8), publicKey: publicKey)
        }
        #expect(throws: Updates.UpdateError.missingKey) {
            try Updates.verify(archive, signature: signature, publicKey: nil)
        }
        #expect(throws: Updates.UpdateError.missingKey) {
            try Updates.verify(archive, signature: signature, publicKey: "pas une clé")
        }
    }

    @Test func appShipsAValidPublicKey() throws {
        // La clé intégrée à Info.plist doit être une clé Ed25519 lisible.
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Support/Info.plist")
        let info = try #require(NSDictionary(contentsOf: plist))
        let text = try #require(info["PastilleUpdatePublicKey"] as? String)
        let raw = try #require(Data(base64Encoded: text))
        _ = try Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }

    // MARK: - Installation (dans un dossier temporaire)

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pastille-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Fausse Pastille.app (un Info.plist et un fichier repère), puis archivée comme par build.sh.
    private func fakeApp(in folder: URL, version: String, bundleID: String = "com.macky.pastille", marker: String) throws -> URL {
        let app = folder.appending(path: "Pastille.app")
        let contents = app.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: NSDictionary = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version]
        try info.write(to: contents.appending(path: "Info.plist"))
        try Data(marker.utf8).write(to: contents.appending(path: "marker"))
        return app
    }

    private func zip(_ app: URL, to zip: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", app.path, zip.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func extractsChecksAndReplacesTheApp() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = try fakeApp(in: root.appending(path: "Applications"), version: "0.1.0", marker: "ancienne")
        let built = try fakeApp(in: root.appending(path: "build"), version: "0.2.0", marker: "nouvelle")
        let archive = root.appending(path: "Pastille-0.2.0.zip")
        try zip(built, to: archive)

        let work = root.appending(path: "work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let extracted = try Updates.extract(archive, into: work, bundleID: "com.macky.pastille", version: "0.2.0")
        try Updates.replace(installed, with: extracted)

        let marker = try String(contentsOf: installed.appending(path: "Contents/marker"), encoding: .utf8)
        #expect(marker == "nouvelle")
        // Rien ne reste à côté de l'app remplacée.
        let left = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Applications").path)
        #expect(left == ["Pastille.app"])
    }

    @Test func refusesTheWrongApp() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let other = try fakeApp(in: root.appending(path: "a"), version: "0.2.0", bundleID: "com.example.autre", marker: "x")
        try zip(other, to: root.appending(path: "autre.zip"))
        #expect(throws: Updates.UpdateError.wrongApp) {
            try Updates.extract(root.appending(path: "autre.zip"), into: root.appending(path: "w1"),
                                bundleID: "com.macky.pastille", version: "0.2.0")
        }
        let older = try fakeApp(in: root.appending(path: "b"), version: "0.1.5", marker: "x")
        try zip(older, to: root.appending(path: "ancienne.zip"))
        #expect(throws: Updates.UpdateError.wrongApp) {
            try Updates.extract(root.appending(path: "ancienne.zip"), into: root.appending(path: "w2"),
                                bundleID: "com.macky.pastille", version: "0.2.0")
        }
        try Data("pas un zip".utf8).write(to: root.appending(path: "abime.zip"))
        #expect(throws: Updates.UpdateError.badArchive) {
            try Updates.extract(root.appending(path: "abime.zip"), into: root.appending(path: "w3"),
                                bundleID: "com.macky.pastille", version: "0.2.0")
        }
    }
}

/// Vraie release sur GitHub : téléchargée, signature vérifiée avec la clé de l'app, décompressée.
/// Seulement sur demande (réseau) : PASTILLE_NETWORK_TESTS=1 swift test --filter PublishedReleaseTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PASTILLE_NETWORK_TESTS"] == "1"))
struct PublishedReleaseTests {
    @Test func latestReleaseIsSignedAndInstallable() async throws {
        let release = try #require(try await UpdateManager.fetchLatest(), "aucune release publiée")
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Support/Info.plist")
        let info = try #require(NSDictionary(contentsOf: plist))
        let folder = FileManager.default.temporaryDirectory.appending(path: "pastille-release-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let app = try await UpdateManager.download(
            release, next: folder.appending(path: "Pastille.app"),
            bundleID: "com.macky.pastille", publicKey: info["PastilleUpdatePublicKey"] as? String
        )
        #expect(FileManager.default.fileExists(atPath: app.appending(path: "Contents/MacOS/Pastille").path))
        #expect(FileManager.default.fileExists(atPath: app.appending(path: "Contents/Resources/NowPlaying.dylib").path))
    }
}
