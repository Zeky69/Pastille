import Combine
import Foundation
import IOKit.ps

@MainActor
final class BatteryManager: ObservableObject {
    static let shared = BatteryManager()

    @Published private(set) var level = 100
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var hasBattery = false
    enum Event {
        /// Seuil franchi (20, 10 ou 5 %) sur batterie.
        case low(Int)
        /// Le Mac, branché, vient d'atteindre 100 %.
        case full
    }

    /// Moments à montrer dans la pastille ; c'est elle qui décide quand et combien de temps.
    let events = PassthroughSubject<Event, Never>()

    private static let thresholds = [20, 10, 5]
    private var previousLevel: Int?

    private var source: CFRunLoopSource?

    func start() {
        update()
        let callback: IOPowerSourceCallbackType = { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { BatteryManager.shared.update() }
            }
        }
        if let src = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            source = src
        }
    }

    func update() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            hasBattery = true
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            level = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            isPluggedIn = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            checkLowBattery()
            return
        }
    }

    /// Repère le passage d'un seuil bas (sur batterie) ou des 100 % (branché).
    private func checkLowBattery() {
        defer { previousLevel = level }
        guard let previous = previousLevel else { return }
        if isPluggedIn {
            if level >= 100, previous < 100 { events.send(.full) }
            return
        }
        if let crossed = Self.thresholds.last(where: { previous > $0 && level <= $0 }) {
            events.send(.low(crossed))
        }
    }
}
