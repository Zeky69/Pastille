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
                             .caffeine(true), .timerDone, .newTrack(track, nil)]
        for moment in all {
            #expect(moment.duration > 0)
            #expect(moment.replaces(moment))
        }
    }
}
