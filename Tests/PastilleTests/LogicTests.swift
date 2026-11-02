import AppKit
import Foundation
import Testing
@testable import Pastille

/// Tailles courtes des téléchargements (« 812 Mo », « 1,2 Go »).
@Suite struct DownloadFormatTests {
    @Test(arguments: [
        (0.0, "0 o"),
        (999.0, "999 o"),
        (1_500.0, "2 Ko"),
        (850_000.0, "850 Ko"),
        (2_500_000.0, "2,5 Mo"),
        (812_000_000.0, "812 Mo"),
        (1_200_000_000.0, "1,2 Go"),
        (3_000_000_000_000.0, "3,0 To"),
        // Aux bords des unités : jamais « 1000 Mo » ni « 10,0 Mo ».
        (999_600_000.0, "1,0 Go"),
        (9_960_000.0, "10 Mo"),
        (999_999.0, "1,0 Mo"),
    ])
    func shortSize(bytes: Double, expected: String) {
        #expect(DownloadManager.short(bytes) == expected)
    }

    @Test func neverMoreThanThreeDigitsOrOneDecimal() {
        var bytes = 1.0
        while bytes < 1e14 {
            let text = DownloadManager.short(bytes)
            let number = text.split(separator: " ")[0]
            #expect(number.count <= 3, "\(bytes) → \(text)")
            bytes *= 1.37
        }
    }
}

/// Minuteur et chronomètre de l'app Horloge.
@Suite struct ClockTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func timer(state: Int, duration: Double = 300, fire: Date? = nil, remaining: Double? = nil) -> [String: Any] {
        var fireTime: [String: Any] = [:]
        if let fire { fireTime["$MTTimerDate"] = ["MTTimerTimeDate": fire] }
        if let remaining { fireTime["$MTTimerTimeInterval"] = ["MTTimerTimeInterval": remaining] }
        return ["MTTimerState": state, "MTTimerDuration": duration, "MTTimerFireTime": fireTime]
    }

    @Test func runningTimer() throws {
        let parsed = try #require(ClockTimerSource.parse(timer(state: 3, fire: now + 120), now: now))
        #expect(!parsed.isPaused)
        #expect(parsed.remaining(at: now) == 120)
        #expect(parsed.progress(at: now) == 0.4)
        #expect(parsed.remaining(at: now + 500) == 0)
    }

    @Test func pausedTimer() throws {
        let parsed = try #require(ClockTimerSource.parse(timer(state: 2, remaining: 42), now: now))
        #expect(parsed.isPaused)
        #expect(parsed.remaining(at: now + 1000) == 42)
    }

    @Test func ignoredTimers() {
        #expect(ClockTimerSource.parse(timer(state: 1, fire: now + 60), now: now) == nil)   // arrêté
        #expect(ClockTimerSource.parse(timer(state: 3, fire: now - 1), now: now) == nil)    // déjà sonné
        #expect(ClockTimerSource.parse(timer(state: 3, duration: 0, fire: now + 60), now: now) == nil)
        #expect(ClockTimerSource.parse(timer(state: 9, fire: now + 60), now: now) == nil)   // état inconnu
        #expect(ClockTimerSource.parse([:], now: now) == nil)
        #expect(ClockTimerSource.parse(["MTTimerState": "3"], now: now) == nil)              // mauvais type
    }

    @Test func zeroDurationHasNoProgress() {
        #expect(ClockTimer(duration: 0, fireDate: nil, pausedRemaining: 5).progress() == 0)
    }

    @Test func stopwatch() {
        let running = ClockStopwatch(offset: 10, startDate: now)
        #expect(running.elapsed(at: now + 5) == 15)
        #expect(running.elapsed(at: now - 5) == 10)  // horloge qui recule : jamais moins
        #expect(ClockStopwatch(offset: 7, startDate: nil).elapsed(at: now + 99) == 7)
    }

    @Test func stalePauseDisappearsAfterTenSeconds() {
        var pause: (value: ClockStopwatch, since: Date)?
        let paused = ClockStopwatch(offset: 5, startDate: nil)
        func shown(_ value: ClockStopwatch?, at time: TimeInterval) -> ClockStopwatch? {
            TimerManager.hidingStalePause(value, \.isPaused, pause: &pause, now: now + time)
        }
        #expect(shown(paused, at: 0) == paused)
        #expect(shown(paused, at: 9) == paused)
        #expect(shown(paused, at: 11) == nil)
        // Une nouvelle pause (autre valeur) repart pour 10 s.
        let other = ClockStopwatch(offset: 8, startDate: nil)
        #expect(shown(other, at: 12) == other)
        // Relancé : toujours affiché, et la pause est oubliée.
        let running = ClockStopwatch(offset: 8, startDate: now)
        #expect(shown(running, at: 30) == running)
        #expect(pause == nil)
        #expect(shown(nil, at: 31) == nil)
    }
}

/// Crans du volume et de la luminosité.
@Suite struct HUDTests {
    @Test func snapsToSteps() {
        let step: Float = 1 / 16
        #expect(HUDManager.snap(0.5 + 0.01, step) == 0.5)
        #expect(HUDManager.snap(-0.2, step) == 0)
        #expect(HUDManager.snap(1.3, step) == 1)
        #expect(HUDManager.snap(0.03, step) == 0)
        #expect(HUDManager.snap(0.04, step) == 0.0625)
        // 16 crans montent de 0 à 1 sans dérive.
        var value: Float = 0
        for _ in 0..<16 { value = HUDManager.snap(value + step, step) }
        #expect(value == 1)
        for _ in 0..<16 { value = HUDManager.snap(value - step, step) }
        #expect(value == 0)
    }
}

/// Batterie des appareils Bluetooth (sortie de system_profiler).
@Suite struct BluetoothTests {
    @Test func airPodsShowTheLowestBud() throws {
        let device = try #require(BluetoothManager.device(name: "AirPods Pro", info: [
            "device_address": "80:C3:BA:66:F4:B6",
            "device_batteryLevelLeft": "80 %",
            "device_batteryLevelRight": "75%",
            "device_batteryLevelCase": "40 %",
            "device_minorType": "Headphones",
        ], fallback: [:]))
        #expect(device.level == 75)
        #expect(device.detail == "G 80 % · D 75 % · Boîtier 40 %")
        #expect(device.levels == ["left": 80, "right": 75, "case": 40])
    }

    @Test func thirdPartyHeadsetUsesTheBluetoothModule() throws {
        let device = try #require(BluetoothManager.device(name: "MOMENTUM 4", info: [
            "device_address": "00-1b-66-aa-bb-cc",
        ], fallback: ["00:1B:66:AA:BB:CC": ["main": 60]]))
        #expect(device.level == 60)
        #expect(device.detail == "60 %")
    }

    @Test func noBatteryNoDevice() {
        #expect(BluetoothManager.device(name: "Clavier", info: [:], fallback: [:]) == nil)
        #expect(BluetoothManager.device(name: "Souris", info: ["device_batteryLevelMain": "n/a"], fallback: [:]) == nil)
    }

    @Test func addressesAreNormalized() {
        #expect(BluetoothManager.normalize("80-c3-ba-66-f4-b6") == "80:C3:BA:66:F4:B6")
        #expect(BluetoothManager.normalize("80:C3:BA:66:F4:B6") == "80:C3:BA:66:F4:B6")
    }
}

/// Cache des pochettes : borné, il ne grossit pas morceau après morceau.
@Suite struct BoundedCacheTests {
    @Test func keepsOnlyTheMostRecent() {
        var cache = BoundedCache<String, Int>(capacity: 3)
        for (i, key) in ["a", "b", "c", "d"].enumerated() { cache[key] = i }
        #expect(cache.count == 3)
        #expect(cache["a"] == nil)
        #expect(cache["d"] == 3)
        // Réécrire une entrée la rend la plus récente.
        cache["b"] = 10
        cache["e"] = 4
        #expect(cache["b"] == 10)
        #expect(cache["c"] == nil)
        cache["b"] = nil
        #expect(cache.count == 2)
    }

    @Test func manyTracksStayBounded() {
        var cache = BoundedCache<String, Int>(capacity: 30)
        for i in 0..<10_000 { cache["titre \(i)|artiste"] = i }
        #expect(cache.count == 30)
        #expect(cache["titre 9999|artiste"] == 9999)
    }
}
