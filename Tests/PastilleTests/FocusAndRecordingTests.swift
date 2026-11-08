import Foundation
import Testing
@testable import Pastille

/// Lecture du mode Concentration et repérage de l'enregistrement d'écran.
@Suite struct FocusAndRecordingTests {
    private func json(_ text: String) -> Data { Data(text.utf8) }

    @Test func readsTheActiveFocus() {
        let active = json("""
        {"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.work"}}]}]}
        """)
        #expect(FocusManager.activeModeID(assertions: active) == "com.apple.focus.work")
    }

    @Test func noAssertionMeansNoFocus() {
        // Ce que macOS laisse quand on coupe Ne pas déranger : seulement des invalidations.
        let ended = json("""
        {"data":[{"storeInvalidationRecords":[{"invalidationAssertion":{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.donotdisturb.mode.default"}}}]}]}
        """)
        #expect(FocusManager.activeModeID(assertions: ended) == nil)
        #expect(FocusManager.activeModeID(assertions: json("pas du json")) == nil)
    }

    @Test func appleModesAreNamedInFrench() {
        let config = json("""
        {"data":[{"modeConfigurations":{
          "com.apple.donotdisturb.mode.default":{"mode":{"name":"Do Not Disturb","symbolImageName":"moon.fill","tintColorName":"systemIndigoColor"}},
          "com.apple.sleep.sleep-mode":{"mode":{"name":"Sleep","symbolImageName":"bed.double.fill","tintColorName":"systemMintColor"}},
          "com.apple.donotdisturb.mode.flamefill":{"mode":{"name":"Spider","symbolImageName":"diamond.fill","tintColorName":"systemIndigoColor"}}
        }}]}
        """)
        #expect(FocusManager.mode(id: "com.apple.donotdisturb.mode.default", configurations: config).name == "Ne pas déranger")
        let sleep = FocusManager.mode(id: "com.apple.sleep.sleep-mode", configurations: config)
        #expect(sleep.name == "Sommeil")
        #expect(sleep.symbol == "bed.double.fill")
        #expect(sleep.tint == "systemMintColor")
        // Un mode créé par la personne garde son nom.
        #expect(FocusManager.mode(id: "com.apple.donotdisturb.mode.flamefill", configurations: config).name == "Spider")
        #expect(FocusManager.mode(id: "inconnu", configurations: nil).name == "Concentration")
    }

    @MainActor @Test func elapsedTimeFormat() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(CompactPillView.elapsed(since: start, at: Date(timeIntervalSince1970: 7)) == "0:07")
        #expect(CompactPillView.elapsed(since: start, at: Date(timeIntervalSince1970: 754)) == "12:34")
        #expect(CompactPillView.elapsed(since: start, at: Date(timeIntervalSince1970: 3723)) == "1:02:03")
    }
}
