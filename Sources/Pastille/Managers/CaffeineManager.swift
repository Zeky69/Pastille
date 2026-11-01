import Foundation
import IOKit.pwr_mgt

/// Garde le Mac (et l'écran) éveillé tant que la tasse est activée.
/// L'assertion est rendue à macOS en désactivant, ou automatiquement si Pastille quitte.
@MainActor
final class CaffeineManager: ObservableObject {
    static let shared = CaffeineManager()

    @Published private(set) var isActive = false
    /// Bref affichage dans la pastille fermée après un changement.
    @Published private(set) var flash = false

    private var assertion: IOPMAssertionID = 0
    private var flashWork: DispatchWorkItem?

    func toggle() {
        if isActive {
            IOPMAssertionRelease(assertion)
            isActive = false
        } else {
            let status = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Pastille garde le Mac éveillé" as CFString,
                &assertion
            )
            isActive = status == kIOReturnSuccess
        }
        showFlash()
    }

    private func showFlash() {
        flash = true
        flashWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flash = false }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
