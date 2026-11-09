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
    private var frontWindows: FrontWindowWatcher?
    private var fullscreenWork: DispatchWorkItem?
    /// Un menu contextuel ouvert depuis la pastille ne doit pas la refermer.
    private var isMenuOpen = false
    /// Compteur du presse-papiers de glisser-déposer au dernier clic : s'il a bougé depuis,
    /// un nouveau glisser a commencé (ses données ne datent pas d'un glisser précédent).
    private var dragBaseline = NSPasteboard(name: .drag).changeCount
    /// Surveillance du glisser, seulement tant que le bouton de la souris est enfoncé.
    private var dragWatch: Timer?
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
                    // L'aperçu d'une capture a besoin d'une fenêtre plus haute (et la rend ensuite).
                    self?.resizePanelIfNeeded()
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
                    self?.followFrontApp()
                    // Après le glissement de macOS vers l'espace plein écran, pour que le repli se voie.
                    for delay in [0.6, 1.2, 2.0] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.checkFullscreen() }
                    }
                }
            }
        }
        // Plein écran sans changement d'espace (VLC…) : la fenêtre change de taille, on revérifie
        // une fois les mouvements terminés.
        frontWindows = FrontWindowWatcher { [weak self] in
            guard let self else { return }
            checkFullscreen()
            fullscreenWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.checkFullscreen() }
            fullscreenWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
        followFrontApp()
        checkFullscreen()
    }

    private func followFrontApp() {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            frontWindows?.watch(pid: pid)
        }
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
            return covers(bounds, screen: screen, primaryHeight: primaryHeight)
        }
    }

    /// `bounds` en coordonnées CG (origine en haut à gauche de l'écran principal), `screen` en
    /// coordonnées AppKit. Vrai si la fenêtre recouvre tout l'écran, bande de l'encoche comprise.
    nonisolated static func covers(_ bounds: CGRect, screen: CGRect, primaryHeight: CGFloat) -> Bool {
        let frame = CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
        return frame.insetBy(dx: -1, dy: -1).contains(screen)
    }

    static func preferredScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func resizePanelIfNeeded() {
        let canvas = viewModel.canvasSize
        let expected = CGSize(width: canvas.width + shadowPadding * 2, height: canvas.height + shadowPadding)
        if panel.frame.size != expected { reposition() }
    }

    func reposition() {
        screen = Self.preferredScreen()
        viewModel.update(for: screen)
        let canvas = viewModel.canvasSize
        let size = CGSize(
            width: canvas.width + shadowPadding * 2,
            height: canvas.height + shadowPadding
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
            MainActor.assumeIsolated {
                self?.isMenuOpen = true
                if self?.viewModel.liveActivity == .screenshot { self?.viewModel.momentHeld = true }
            }
        }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isMenuOpen = false
                if self.viewModel.liveActivity == .screenshot {
                    self.viewModel.momentHeld = self.hotRect().contains(NSEvent.mouseLocation)
                }
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

    // MARK: - Fichiers glissés vers l'encoche

    /// À chaque clic, on note l'état du glisser-déposer puis on regarde, tant que le bouton reste
    /// enfoncé, si des fichiers sont glissés vers l'encoche. Pendant un glisser, macOS n'envoie pas
    /// toujours les mouvements de souris aux autres apps : on ne dépend donc pas d'eux.
    private func startDragWatch() {
        dragBaseline = NSPasteboard(name: .drag).changeCount
        dragWatch?.invalidate()
        dragWatch = nil
        // Un glisser qui part de la pastille (une capture, un fichier de l'étagère qu'on sort)
        // ne doit pas la faire changer de page en plein geste.
        guard !hotRect().contains(NSEvent.mouseLocation) else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkFileDrag() }
        }
        RunLoop.main.add(timer, forMode: .common)
        dragWatch = timer
    }

    private func checkFileDrag() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            dragWatch?.invalidate()
            dragWatch = nil
            return
        }
        guard isDraggingFiles(),
              Self.shelfDropZone(screen: screen.frame, cutout: viewModel.cutoutSize,
                                 open: viewModel.isExpanded ? viewModel.expandedSize : nil)
                .contains(NSEvent.mouseLocation) else { return }
        openShelfForDrop()
    }

    /// La pastille s'ouvre (ou change de page) sur l'étagère, prête à recevoir les fichiers.
    private func openShelfForDrop() {
        expandWork?.cancel()
        expandWork = nil
        collapseWork?.cancel()
        collapseWork = nil
        if viewModel.isExpanded {
            if viewModel.tab != .shelf { viewModel.select(.shelf) }
        } else {
            viewModel.showShelf()
            expand()
        }
    }

    /// Zone où un fichier glissé ouvre l'étagère (coordonnées écran) : une large bande en haut,
    /// autour de l'encoche, pour ne pas devoir viser la découpe ; la pastille entière une fois ouverte.
    nonisolated static func shelfDropZone(screen: CGRect, cutout: CGSize, open: CGSize?) -> CGRect {
        let size = open.map { CGSize(width: $0.width + 16, height: $0.height + 8) }
            ?? CGSize(width: cutout.width + 240, height: cutout.height + 50)
        return CGRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height, width: size.width, height: size.height)
    }

    /// Un glisser de fichiers est en cours (depuis le Finder, le Bureau, une autre app…).
    private func isDraggingFiles() -> Bool {
        guard Appearance.bool(Appearance.showShelfTabKey) else { return false }
        let pasteboard = NSPasteboard(name: .drag)
        return pasteboard.changeCount != dragBaseline && Self.carriesFiles(pasteboard.types ?? [])
    }

    nonisolated static func carriesFiles(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        types.contains(.fileURL) || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
    }

    private func handle(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        let inside = hotRect().contains(location)
        // Coche verte d'un téléchargement terminé : elle se clique au lieu d'ouvrir la pastille.
        let downloadClickable = !viewModel.isExpanded && viewModel.liveActivity == .download
            && DownloadManager.shared.state == .finished
        // Aperçu d'une capture : survolé, il reste affiché et ses boutons se cliquent (pas d'ouverture).
        let previewActive = !viewModel.isExpanded && viewModel.liveActivity == .screenshot
        if !previewActive, viewModel.momentHeld { viewModel.momentHeld = false }

        if event.type == .leftMouseDown {
            startDragWatch()
        }
        // Glisser de fichiers en cours : vérifié tout de suite, sans attendre la surveillance.
        if event.type == .leftMouseDragged, dragWatch != nil {
            checkFileDrag()
        }

        if event.type == .leftMouseDown {
            if downloadClickable, inside {
                DownloadManager.shared.openFinished(reveal: event.modifierFlags.contains(.option))
                panel.ignoresMouseEvents = true
            } else if previewActive {
                // Le clic va à l'aperçu lui-même.
            } else if !viewModel.isExpanded, inside {
                expand()
            }
            return
        }

        if previewActive {
            panel.ignoresMouseEvents = !inside
            viewModel.momentHeld = inside || isMenuOpen
            expandWork?.cancel()
            expandWork = nil
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
