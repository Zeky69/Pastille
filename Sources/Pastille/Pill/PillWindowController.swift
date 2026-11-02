import AppKit
import Combine
import SwiftUI

/// Place le panneau en haut de l'écran et gère l'ouverture / fermeture au survol.
@MainActor
final class PillWindowController {
    let viewModel = PillViewModel()
    var onOpenSettings: (() -> Void)?

    private let panel: PillPanel
    private var screen: NSScreen
    private var monitors: [Any] = []
    private var activityWatch: AnyCancellable?
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    /// Un menu contextuel ouvert depuis la pastille ne doit pas la refermer.
    private var isMenuOpen = false
    /// Glissement horizontal à deux doigts en cours : distance cumulée, et page déjà changée ou non.
    private var swipeDistance: CGFloat = 0
    private var swipeHandled = false
    /// Liste horizontale sous les doigts au début du geste : ne change de page que si elle était déjà au bout.
    private var swipeAllowsPrevious = true
    private var swipeAllowsNext = true

    /// Marge autour de la zone ouverte pour laisser respirer l'ombre.
    private let shadowPadding: CGFloat = 30

    init() {
        screen = Self.preferredScreen()
        panel = PillPanel(contentRect: .zero)
        viewModel.update(for: screen)
        viewModel.onExpandedSizeChange = { [weak self] in self?.reposition() }

        let root = PillRootView(
            viewModel: viewModel,
            onOpenSettings: { [weak self] in
                self?.collapse()
                self?.onOpenSettings?()
            }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.ignoresMouseEvents = true
        // Mouvements de souris aussi reçus au-dessus de la pastille quand elle capte les clics.
        panel.acceptsMouseMovedEvents = true

        reposition()
        panel.orderFrontRegardless()
        installMonitors()
        watchFullscreen()
        // Avec le spectre (vue macOS animée en continu) dans la pastille, la toute première animation
        // de taille ne démarrait pas : elle restait figée jusqu'à la mise à jour suivante. On provoque
        // donc nous-mêmes cette mise à jour, une image après chaque changement d'activité.
        activityWatch = viewModel.$liveActivity
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
                    self?.viewModel.objectWillChange.send()
                }
            }
    }

    // MARK: - Plein écran

    /// Entrer en plein écran change d'espace (ou active une autre app) ; l'animation d'entrée dure
    /// environ une seconde, d'où les vérifications un peu décalées.
    private func watchFullscreen() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Après le glissement de macOS vers l'espace plein écran, pour que le repli se voie.
                    for delay in [0.6, 1.2, 2.0] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.checkFullscreen() }
                    }
                }
            }
        }
        checkFullscreen()
    }

    /// Plein écran : on demande à l'app au premier plan (via l'Accessibilité) si sa fenêtre active est
    /// en plein écran macOS. En secours, pour les apps qui font leur propre plein écran (jeux, lecteurs),
    /// une de ses fenêtres couvre-t-elle tout l'écran de la pastille, bande de l'encoche comprise ?
    private func checkFullscreen() {
        var covered = false
        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            covered = Self.focusedWindowIsFullscreen(pid: app.processIdentifier)
                || Self.windowCoversScreen(pid: app.processIdentifier, screen: screen.frame)
        }
        if covered != viewModel.fullscreenAppActive { viewModel.fullscreenAppActive = covered }
    }

    private static func focusedWindowIsFullscreen(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return false }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, "AXFullScreen" as CFString, &value) == .success else {
            return false
        }
        return (value as? Bool) ?? false
    }

    private static func windowCoversScreen(pid: pid_t, screen: CGRect) -> Bool {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.height
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windows.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? Int32) == pid,
                  (info[kCGWindowLayer as String] as? Int ?? -1) >= 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { return false }
            // Coordonnées CG : origine en haut à gauche de l'écran principal.
            let frame = CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            return frame.insetBy(dx: -1, dy: -1).contains(screen)
        }
    }

    static func preferredScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func reposition() {
        screen = Self.preferredScreen()
        viewModel.update(for: screen)
        let size = CGSize(
            width: viewModel.expandedSize.width + shadowPadding * 2,
            height: viewModel.expandedSize.height + shadowPadding
        )
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
    }

    // MARK: - Ouverture / fermeture

    func expand() {
        collapseWork?.cancel()
        guard !viewModel.isExpanded else { return }
        BluetoothManager.shared.setVisible(true)
        WeatherManager.shared.refreshIfStale()
        if Settings.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        withAnimation(PillAnimation.expand) {
            viewModel.state = .expanded
        }
        panel.ignoresMouseEvents = false
    }

    func collapse() {
        expandWork?.cancel()
        guard viewModel.isExpanded else { return }
        BluetoothManager.shared.setVisible(false)
        withAnimation(PillAnimation.collapse) {
            viewModel.state = .compact
        }
        panel.ignoresMouseEvents = true
    }

    // MARK: - Suivi de la souris

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) {
            monitors.append(local)
        }
        if let swipe = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            // Seul un booléen ressort du contexte principal (NSEvent n'est pas Sendable).
            let consumed = MainActor.assumeIsolated { self?.consumesSwipe(event) ?? false }
            return consumed ? nil : event
        }) {
            monitors.append(swipe)
        }

        let center = NotificationCenter.default
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isMenuOpen = true }
        }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isMenuOpen = false
                if self.viewModel.isExpanded, !self.hotRect().contains(NSEvent.mouseLocation) { self.collapse() }
            }
        }
    }

    /// Zone active en coordonnées écran (origine en bas à gauche).
    private func hotRect() -> NSRect {
        let size = viewModel.currentSize
        let extra: CGFloat = viewModel.isExpanded ? 8 : 4
        return NSRect(
            x: screen.frame.midX - size.width / 2 - extra,
            y: screen.frame.maxY - size.height - extra,
            width: size.width + extra * 2,
            height: size.height + extra + 1
        )
    }

    // MARK: - Glisser à deux doigts pour changer de page

    /// Un glissement horizontal sur une zone sans défilement propre change d'onglet.
    /// Les listes qui défilent elles-mêmes (captures, frise des jours) gardent leur geste.
    /// Renvoie true si le geste a changé de page (l'événement est alors absorbé).
    private func consumesSwipe(_ event: NSEvent) -> Bool {
        guard Settings.swipePages, viewModel.isExpanded, event.window === panel, event.hasPreciseScrollingDeltas,
              event.momentumPhase.isEmpty else { return false }

        if event.phase.contains(.began) {
            swipeDistance = 0
            let point = panel.contentView.map { $0.convert(event.locationInWindow, from: nil) } ?? .zero
            // Zones où glisser ne change jamais de page (la frise des jours).
            swipeHandled = PageSwipeBlockers.frames.values.contains { $0.contains(point) }
            (swipeAllowsPrevious, swipeAllowsNext) = Self.scrollerEdges(event, in: panel)
        }
        guard !swipeHandled else {
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) { swipeHandled = false }
            return false
        }

        swipeDistance += event.scrollingDeltaX
        // Doigts vers la gauche → page suivante, quel que soit le sens de défilement choisi.
        let fingers = event.isDirectionInvertedFromDevice ? swipeDistance : -swipeDistance
        let forward = fingers < 0
        if abs(fingers) > 40, abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY),
           forward ? swipeAllowsNext : swipeAllowsPrevious {
            swipeHandled = true
            if viewModel.moveTab(by: forward ? 1 : -1), Settings.haptics {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            return true
        }
        return false
    }

    /// Sous le curseur, une liste qui défile sur le côté ? Si oui, on ne change de page vers
    /// l'arrière que si elle est déjà tout au début, et vers l'avant que si elle est déjà tout au bout.
    private static func scrollerEdges(_ event: NSEvent, in panel: NSPanel) -> (previous: Bool, next: Bool) {
        guard let content = panel.contentView else { return (true, true) }
        var view = content.hitTest(content.convert(event.locationInWindow, from: nil))
        while let current = view {
            if let scroll = current as? NSScrollView, let document = scroll.documentView {
                let visible = scroll.contentView.bounds
                if document.frame.width > visible.width + 1 {
                    return (visible.minX <= 1, visible.maxX >= document.frame.width - 1)
                }
            }
            view = current.superview
        }
        return (true, true)
    }

    private func handle(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        let inside = hotRect().contains(location)
        // Coche verte d'un téléchargement terminé : elle se clique au lieu d'ouvrir la pastille.
        let downloadClickable = !viewModel.isExpanded && viewModel.liveActivity == .download
            && DownloadManager.shared.state == .finished

        if event.type == .leftMouseDown {
            if downloadClickable, inside {
                DownloadManager.shared.openFinished(reveal: event.modifierFlags.contains(.option))
                panel.ignoresMouseEvents = true
            } else if !viewModel.isExpanded, inside {
                expand()
            }
            return
        }

        if downloadClickable {
            // On capte le clic (sinon il passerait à la barre des menus dessous), sans ouvrir au survol.
            panel.ignoresMouseEvents = !inside
            DownloadManager.shared.setFinishedHovered(inside)
            return
        }
        if !viewModel.isExpanded, !panel.ignoresMouseEvents, !inside { panel.ignoresMouseEvents = true }

        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            guard !viewModel.isExpanded, Settings.openOnHover, expandWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.expandWork = nil
                if self.hotRect().contains(NSEvent.mouseLocation) { self.expand() }
            }
            expandWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Settings.hoverDelay, execute: work)
        } else {
            expandWork?.cancel()
            expandWork = nil
            guard viewModel.isExpanded, collapseWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.collapseWork = nil
                if !self.isMenuOpen, !self.hotRect().contains(NSEvent.mouseLocation) { self.collapse() }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
}
