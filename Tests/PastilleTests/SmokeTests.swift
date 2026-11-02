import Foundation
import Testing
@testable import Pastille

/// Réglages par défaut de l'app (en mémoire seulement : rien n'est écrit dans les préférences).
func registerAppDefaults() {
    Appearance.registerDefaults()
    Settings.registerDefaults()
}
