import AppKit

/// Suit les fenêtres de l'app au premier plan via l'Accessibilité. Certains lecteurs (VLC) passent
/// en plein écran sans changer d'espace ni d'app : seule leur fenêtre change de taille.
@MainActor
final class FrontWindowWatcher {
    private var observer: AXObserver?
    private var app: AXUIElement?
    private let onChange: () -> Void

    private static let notifications = [
        kAXWindowResizedNotification, kAXWindowMovedNotification, kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification, kAXWindowMiniaturizedNotification, kAXUIElementDestroyedNotification,
    ]

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    /// Remplace l'app suivie. Sans autorisation d'Accessibilité, rien n'est suivi.
    func watch(pid: pid_t) {
        stop()
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<FrontWindowWatcher>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.onChange() }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.notifications {
            AXObserverAddNotification(created, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        app = element
    }

    func stop() {
        guard let observer else { return }
        if let app {
            for name in Self.notifications { AXObserverRemoveNotification(observer, app, name as CFString) }
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = nil
        app = nil
    }
}
