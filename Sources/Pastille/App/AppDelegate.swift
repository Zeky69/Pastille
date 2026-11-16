import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var pillController: PillWindowController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        Appearance.registerDefaults()
        // Aucune question de macOS au démarrage : l'assistant les pose une à une, après explication.
        Permissions.adoptPreviousInstallIfNeeded()

        MusicManager.shared.start()
        BatteryManager.shared.start()
        CalendarManager.shared.start()
        Permissions.startFolderWatchersIfAllowed()
        ScreenRecordingManager.shared.start()
        CallManager.shared.start()
        FocusManager.shared.start()
        HUDManager.shared.start()
        TimerManager.shared.start()
        BluetoothManager.shared.start()
        WeatherManager.shared.start()
        VerificationCodeManager.shared.start()
        UpdateManager.shared.start()
        CaffeineManager.shared.start()

        pillController = PillWindowController()
        pillController?.onOpenSettings = { [weak self] in self?.openSettings() }
        setupStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        if !Onboarding.isDone {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.showOnboarding() }
        }

        // Arrêt par signal (pkill, fermeture de session) : quitter proprement pour rétablir la veille.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        termination = source
    }

    private var termination: DispatchSourceSignal?

    func applicationWillTerminate(_ notification: Notification) {
        // La super tasse ne doit jamais survivre à Pastille : un Mac qui ne dort plus capot fermé chauffe dans un sac.
        CaffeineManager.shared.stop()
    }

    // MARK: - Assistant des autorisations

    func showOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 620),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Bienvenue dans Pastille"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.contentView = NSHostingView(rootView: OnboardingView { [weak window] in window?.close() })
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            onboardingWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    /// Assistant terminé ou fermé : les fonctions qui attendaient (Musique, Spotify, captures,
    /// téléchargements) démarrent avec les autorisations accordées.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === onboardingWindow else { return }
        Onboarding.markDone()
        onboardingWindow = nil
        MusicManager.shared.refreshPlayers()
        Permissions.startFolderWatchersIfAllowed()
    }

    @objc private func screensChanged() {
        pillController?.reposition()
    }

    // MARK: - Barre de menus

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Pastille")
        let menu = NSMenu()
        let update = NSMenuItem(title: "Rechercher les mises à jour…", action: #selector(updateMenuClicked), keyEquivalent: "")
        update.target = self
        updateMenuItem = update
        menu.addItem(update)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Réglages…", action: #selector(openSettings), keyEquivalent: ","))
        let launch = NSMenuItem(title: "Ouvrir au démarrage du Mac", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launchMenuItem = launch
        menu.addItem(launch)
        menu.delegate = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quitter Pastille", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { if $0.action == #selector(openSettings) { $0.target = self } }
        item.menu = menu
        item.isVisible = Settings.showMenuBarIcon
        statusItem = item
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.statusItem?.isVisible != Settings.showMenuBarIcon { self?.statusItem?.isVisible = Settings.showMenuBarIcon }
            }
        }
    }

    private var launchMenuItem: NSMenuItem?
    private var updateMenuItem: NSMenuItem?

    /// Coche à jour à chaque ouverture du menu (l'état peut changer depuis Réglages Système).
    func menuWillOpen(_ menu: NSMenu) {
        launchMenuItem?.state = LaunchAtLogin.isEnabled ? .on : .off
        updateMenuItem?.title = switch UpdateManager.shared.state {
        case let .available(release): "Installer Pastille \(release.version)"
        case .installing: "Installation de la mise à jour…"
        case .checking: "Recherche de mises à jour…"
        default: "Rechercher les mises à jour…"
        }
    }

    /// Mise à jour trouvée : on l'installe ; sinon on cherche, et le résultat s'affiche dans les Réglages.
    @objc private func updateMenuClicked() {
        let updates = UpdateManager.shared
        if updates.available != nil {
            updates.install()
        } else {
            updates.check()
            openSettings()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
        if LaunchAtLogin.needsApproval { LaunchAtLogin.openLoginItemsSettings() }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 640),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Réglages de Pastille"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
