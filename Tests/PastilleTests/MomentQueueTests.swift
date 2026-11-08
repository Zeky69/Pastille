import AppKit
import Foundation
import Testing
@testable import Pastille

/// File d'attente des apparitions courtes de la pastille fermée.
@MainActor
@Suite struct MomentQueueTests {
    init() { registerAppDefaults() }

    private let track = Track(title: "Titre", artist: "Artiste", album: "Album", duration: 200)
    private func airPods(_ id: String = "A") -> BluetoothDevice {
        BluetoothDevice(id: id, name: "AirPods", symbol: "airpods", level: 80, detail: "", levels: [:])
    }

    @Test func firstMomentShowsAtOnce() {
        let model = PillViewModel()
        model.enqueue(.charging)
        #expect(model.moment == .charging)
        #expect(model.liveActivity == .charging)
        #expect(model.queuedMoments.isEmpty)
    }

    @Test func othersWaitTheirTurnInOrder() {
        let model = PillViewModel()
        model.enqueue(.charging)
        model.enqueue(.lowBattery(20))
        model.enqueue(.deviceConnected(airPods()))
        #expect(model.moment == .charging)
        #expect(model.queuedMoments == [.lowBattery(20), .deviceConnected(airPods())])
    }

    @Test func sameKindReplacesInsteadOfStacking() {
        let model = PillViewModel()
        model.enqueue(.charging)
        model.enqueue(.unplugged)  // branché puis débranché : seul le dernier compte
        #expect(model.moment == .unplugged)
        #expect(model.queuedMoments.isEmpty)

        model.enqueue(.lowBattery(20))
        model.enqueue(.lowBattery(10))
        #expect(model.queuedMoments == [.lowBattery(10)])
    }

    @Test func eachDeviceHasItsOwnMoment() {
        let model = PillViewModel()
        model.enqueue(.charging)
        model.enqueue(.deviceConnected(airPods("A")))
        model.enqueue(.deviceConnected(airPods("B")))
        model.enqueue(.deviceConnected(airPods("A")))
        #expect(model.queuedMoments.count == 2)
    }

    @Test func collapsingDropsTrackAnnouncements() {
        let model = PillViewModel()
        model.enqueue(.charging)
        model.enqueue(.newTrack(track, nil))
        model.enqueue(.lowBattery(5))
        model.state = .expanded
        model.state = .compact
        #expect(model.queuedMoments == [.lowBattery(5)])
    }

    private let shot = Screenshot(url: URL(fileURLWithPath: "/tmp/Capture.png"), date: Date(timeIntervalSince1970: 0))

    @Test func screenshotWidensFirstThenDrops() {
        let model = PillViewModel()
        model.enqueue(.screenshot(shot, 0.625))
        #expect(model.liveActivity == .screenshot)
        // D'abord plus large que l'encoche, à sa hauteur…
        #expect(model.compactSize.width >= model.cutoutSize.width + 48)
        #expect(model.extraHeight == 0)
        // …puis elle descend, l'image à la largeur de la pastille et à ses proportions.
        model.dropScreenshot()
        let preview = model.screenshotPreviewSize
        // Elle ne descend pas trop bas : la hauteur est plafonnée, la largeur suit les proportions.
        #expect(preview.height <= PillViewModel.screenshotMaxHeight)
        #expect(preview.width <= model.compactSize.width - 24)
        #expect(abs(preview.height / preview.width - 0.625) < 0.01)
        #expect(model.extraHeight > preview.height)
        // La fenêtre est assez grande pour l'aperçu.
        #expect(model.compactSize.height <= model.canvasSize.height)
        #expect(model.compactSize.width <= model.canvasSize.width)
    }

    @Test func tallScreenshotStaysWithinTheWindow() {
        let model = PillViewModel()
        model.enqueue(.screenshot(shot, 3))
        model.dropScreenshot()
        #expect(model.screenshotPreviewSize.height <= PillViewModel.screenshotMaxHeight)
        #expect(model.compactSize.height <= model.canvasSize.height)
    }

    @Test func hoveringKeepsTheMomentOnScreen() {
        let model = PillViewModel()
        model.enqueue(.screenshot(shot, 0.625))
        model.momentHeld = true
        model.momentHeld = false
        #expect(model.moment == .screenshot(shot, 0.625))
    }

    @Test func focusAnnouncementReplacesThePreviousOne() {
        let model = PillViewModel()
        let dnd = FocusMode(id: "com.apple.donotdisturb.mode.default", name: "Ne pas déranger", symbol: "moon.fill", tint: "systemIndigoColor")
        model.enqueue(.focus(dnd, true))
        model.enqueue(.focus(dnd, false))
        #expect(model.moment == .focus(dnd, false))
        #expect(model.queuedMoments.isEmpty)
        #expect(model.sideWidth >= 58)
    }

    @Test func screenshotShowsEvenInFullscreen() {
        let model = PillViewModel()
        model.fullscreenAppActive = true
        model.enqueue(.screenshot(shot, 0.625))
        #expect(model.liveActivity == .screenshot)
        #expect(!model.isConcealed)
    }

    @Test func openingDuringAScreenshotGoesToTheCapturesTab() {
        let model = PillViewModel()
        model.enqueue(.screenshot(shot, 0.625))
        model.state = .expanded
        #expect(model.moment == nil)
        #expect(model.tab == (model.availableTabs.contains(.screenshots) ? .screenshots : .home))
    }

    @Test func fullscreenHidesTheActivity() {
        let model = PillViewModel()
        model.enqueue(.charging)
        model.fullscreenAppActive = true
        #expect(model.liveActivity == .none)
        // Le moment n'est pas perdu : il réapparaît à la sortie du plein écran.
        #expect(model.moment == .charging)
        model.fullscreenAppActive = false
        #expect(model.liveActivity == .charging)
    }

    @Test func durationsArePositive() {
        let all: [Moment] = [.charging, .unplugged, .charged, .lowBattery(5), .deviceConnected(airPods()),
                             .caffeine(true), .timerDone, .newTrack(track, nil), .update("0.2.0"),
                             .screenshot(shot, 0.625),
                             .focus(FocusMode(id: "x", name: "Travail", symbol: "moon.fill", tint: ""), true)]
        for moment in all {
            #expect(moment.duration > 0)
            #expect(moment.replaces(moment))
        }
    }
}
