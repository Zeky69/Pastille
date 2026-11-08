import Foundation
import Testing
@testable import Pastille

/// Vérifications avant de publier une version (lancées par ./build.sh publish avec les autres tests).
@Suite struct ReleaseTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private var info: [String: Any] {
        (try? PropertyListSerialization.propertyList(
            from: Data(contentsOf: root.appendingPathComponent("Support/Info.plist")), format: nil)) as? [String: Any] ?? [:]
    }

    @Test func versionIsWellFormed() {
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        #expect(version.split(separator: ".").count == 3)
        #expect(version.split(separator: ".").allSatisfy { Int($0) != nil })
    }

    @Test func releaseNotesExistForThisVersion() throws {
        let version = try #require(info["CFBundleShortVersionString"] as? String)
        let notes = root.appendingPathComponent("docs/releases/\(version).md")
        let text = try String(contentsOf: notes, encoding: .utf8)
        #expect(text.contains("Nouveautés"))
        // Les instructions d'installation citent la bonne archive.
        #expect(text.contains("Pastille-\(version).zip"))
    }

    @Test func bundleIdentifierNeverChanges() {
        // Changer d'identifiant ferait perdre toutes les autorisations macOS aux utilisateurs.
        #expect(info["CFBundleIdentifier"] as? String == "com.macky.pastille")
        #expect(info["LSUIElement"] as? Bool == true)
    }
}
