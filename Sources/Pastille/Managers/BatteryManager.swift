import Foundation
import IOKit.ps

@MainActor
final class BatteryManager: ObservableObject {
    static let shared = BatteryManager()

    @Published private(set) var level = 100
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var hasBattery = false
    /// Vrai quelques secondes quand le Mac, branché, atteint 100 %.
    @Published private(set) var justFullyCharged = false
    private var fullWork: DispatchWorkItem?

    /// Seuil franchi (20, 10 ou 5 %) pendant l'alerte de batterie faible, sinon nil.
    @Published private(set) var lowAlert: Int?

    private static let thresholds = [20, 10, 5]
    private var previousLevel: Int?
    private var alertWork: DispatchWorkItem?

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

    /// Alerte quand le niveau descend sous un seuil (sur batterie uniquement).
    private func checkLowBattery() {
        defer { previousLevel = level }
        if isPluggedIn, level >= 100, let previous = previousLevel, previous < 100 {
            justFullyCharged = true
            fullWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.justFullyCharged = false }
            fullWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
        }
        if isPluggedIn {
            hideLowAlert()
            return
        }
        guard let previous = previousLevel,
              let crossed = Self.thresholds.last(where: { previous > $0 && level <= $0 }) else { return }
        lowAlert = crossed
        alertWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.lowAlert = nil }
        alertWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func hideLowAlert() {
        alertWork?.cancel()
        if lowAlert != nil { lowAlert = nil }
    }
}
