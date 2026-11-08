import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var pillController: PillWindowController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        Appearance.registerDefaults()

        MusicManager.shared.start()
        BatteryManager.shared.start()
        CalendarManager.shared.start()
        ScreenshotManager.shared.start()
        ScreenRecordingManager.shared.start()
        FocusManager.shared.start()
        HUDManager.shared.start()
        TimerManager.shared.start()
        BluetoothManager.shared.start()
        WeatherManager.shared.start()
        DownloadManager.shared.start()
        VerificationCodeManager.shared.start()
        UpdateManager.shared.start()

        pillController = PillWindowController()
        pillController?.onOpenSettings = { [weak self] in self?.openSettings() }
        setupStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
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
