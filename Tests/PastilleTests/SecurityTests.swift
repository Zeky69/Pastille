import Foundation
import Testing
@testable import Pastille

/// Le titre d'une vidéo (choisi par n'importe quelle page web) est inséré dans un AppleScript pour
/// retrouver l'onglet qui joue : il doit toujours rester du texte, jamais devenir du code.
@MainActor
@Suite(.serialized) struct AppleScriptInjectionTests {
    /// Compile `return "<titre échappé>"` et renvoie ce que le script produit vraiment.
    private func roundTrip(_ text: String) -> String? {
        let source = "return \"\(MusicManager.appleScriptEscaped(text))\""
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
    }

    @Test(arguments: [
        "Une chanson normale",
        "Titre avec \"guillemets\"",
        "Antislash \\ au milieu",
        "Fin par antislash \\",
        "\\\" & (do shell script \"echo pwned\") & \"",
        "\" & (do shell script \"echo pwned\") & \"",
        "Ligne 1\nLigne 2\tTab\rRetour",
        "Accents éàü, émojis 🎵, « chevrons » et “guillemets courbes”",
        "«data utf8414243»",
        "-- commentaire",
        "(* commentaire *)",
    ])
    func titleStaysPlainText(title: String) {
        #expect(roundTrip(title) == title)
    }

    @Test func noShellCommandRuns() throws {
        let marker = FileManager.default.temporaryDirectory.appending(path: "pastille-injection-\(UUID().uuidString)")
        let payload = "\" & (do shell script \"touch \(marker.path)\") & \""
        _ = roundTrip(payload)
        _ = roundTrip("\\" + payload)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }
}
