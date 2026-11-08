import AppKit
import Combine

/// Enregistrement d'écran lancé avec ⌘⇧5 (ou QuickTime, qui passe par le même outil).
/// Pendant l'enregistrement, l'outil Capture d'écran (screencaptureui) pose une icône « Arrêter
/// l'enregistrement » dans la barre des menus. Sur les macOS récents, ces icônes ne sont plus des
/// fenêtres visibles de l'extérieur : on la lit par l'Accessibilité (déjà autorisée pour le plein écran).
/// On ne regarde que pendant que l'outil tourne, deux fois par seconde.
@MainActor
final class ScreenRecordingManager: ObservableObject {
    static let shared = ScreenRecordingManager()

    /// Début de l'enregistrement en cours (nil : rien n'est enregistré).
    @Published private(set) var startedAt: Date?
    var isRecording: Bool { startedAt != nil }

    private static let toolID = "com.apple.screencaptureui"
    private var appsWatch: NSKeyValueObservation?
    private var poll: Timer?

    func start() {
        appsWatch = NSWorkspace.shared.observe(\.runningApplications, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.followTool() } }
        }
    }

    /// Arrête l'enregistrement en appuyant sur l'icône d'Apple ; à défaut, avec son raccourci ⌘⌃Échap.
    func stop() {
        if let item = toolPID.flatMap(Self.stopItem), AXUIElementPerformAction(item, kAXPressAction as CFString) == .success {
            return
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: isDown)
            event?.flags = [.maskCommand, .maskControl]
            event?.post(tap: .cghidEventTap)
        }
    }

    private var toolPID: pid_t? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == Self.toolID }?.processIdentifier
    }

    private func followTool() {
        if toolPID != nil {
            guard poll == nil else { return }
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
            RunLoop.main.add(timer, forMode: .common)
            poll = timer
            check()
        } else {
            poll?.invalidate()
            poll = nil
            if startedAt != nil { startedAt = nil }
        }
    }

    private func check() {
        let recording = toolPID.flatMap(Self.stopItem) != nil
        if recording, startedAt == nil {
            startedAt = Date()
        } else if !recording, startedAt != nil {
            startedAt = nil
        }
    }

    /// L'icône de l'outil dans la barre des menus : elle n'existe que pendant un enregistrement
    /// (la barre d'outils ⌘⇧5 et la sélection n'en posent pas).
    private static func stopItem(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &bar) == .success, let bar,
              CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children)
        return (children as? [AXUIElement])?.first
    }
}
