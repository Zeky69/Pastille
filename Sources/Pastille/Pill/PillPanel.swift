import AppKit

/// Panneau transparent, sans bordure, posé au-dessus de la barre de menus.
final class PillPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        level = .mainMenu + 3
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        // Toujours en thème sombre : le verre liquide reste fumé même si macOS est en mode clair.
        appearance = NSAppearance(named: .darkAqua)
    }

    // Les matériaux (verre, flou) pâlissent quand leur fenêtre n'est pas active. La pastille n'est
    // presque jamais la fenêtre active : on lui donne toujours l'apparence active, pour un verre
    // fumé constant (méthodes AppKit internes, consultées par le rendu des matériaux).
    @objc func _hasActiveAppearance() -> Bool { true }
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
    @objc func _hasKeyAppearance() -> Bool { true }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
