import Combine
import Foundation
import IOKit.pwr_mgt

/// Garde le Mac (et l'écran) éveillé tant que la tasse est activée.
/// L'assertion est rendue à macOS en désactivant, ou automatiquement si Pastille quitte.
@MainActor
final class CaffeineManager: ObservableObject {
    static let shared = CaffeineManager()

    @Published private(set) var isActive = false
    /// Envoyé à chaque bascule (nouvel état), pour un bref affichage dans la pastille fermée.
    let toggled = PassthroughSubject<Bool, Never>()

    private var assertion: IOPMAssertionID = 0

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
        toggled.send(isActive)
    }
}
