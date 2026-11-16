import AppKit
import ApplicationServices
import CoreBluetooth
import CoreLocation
import CoreServices
import EventKit

/// Autorisations macOS, demandées une à une et toujours expliquées avant : par l'assistant du premier
/// lancement, ou depuis Réglages › Autorisations. Rien n'est demandé tout seul au démarrage.
@MainActor
enum Permissions {
    enum Kind: String, CaseIterable, Identifiable {
        case accessibility, automation, calendar, location, bluetooth, fullDisk, folders
        var id: String { rawValue }
    }

    enum State: Equatable {
        case granted
        case notAsked
        case denied
        /// Rien à demander pour l'instant (raison affichée).
        case unavailable(String)
    }

    // MARK: - État

    static func state(of kind: Kind) -> State {
        switch kind {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : (wasAsked(kind) ? .denied : .notAsked)
        case .automation:
            return automationState
        case .calendar:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: return .granted
            case .notDetermined: return .notAsked
            default: return .denied
            }
        case .location:
            switch CLLocationManager().authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse: return .granted
            case .notDetermined: return .notAsked
            default: return .denied
            }
        case .bluetooth:
            return bluetoothState
        case .fullDisk:
            return hasFullDiskAccess ? .granted : (wasAsked(kind) ? .denied : .notAsked)
        case .folders:
            if hasFullDiskAccess { return .granted }
            guard wasAsked(kind), !foldersCheckInFlight else { return .notAsked }
            return UserDefaults.standard.bool(forKey: foldersGrantedKey) ? .granted : .denied
        }
    }

    static var bluetoothState: State {
        switch CBManager.authorization {
        case .allowedAlways: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    static var hasFullDiskAccess: Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Messages/chat.db").path
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        try? handle.close()
        return true
    }

    // MARK: - Demande

    /// Fait apparaître la question de macOS (ou ouvre le bon volet des Réglages Système quand macOS
    /// ne sait pas poser la question lui-même, ou qu'elle a déjà été refusée).
    static func request(_ kind: Kind) {
        markAsked(kind)
        if state(of: kind) == .denied {
            // Déjà refusée : macOS ne repose pas la question, seul Réglages Système peut l'accorder.
            if kind == .folders { requestFolders() }
            return openSettings(for: kind)
        }
        switch kind {
        case .accessibility: HUDManager.shared.requestAccess()
        case .automation: requestAutomation()
        case .calendar: CalendarManager.shared.requestAccess()
        case .location: WeatherManager.shared.requestAccess()
        case .bluetooth: BluetoothManager.shared.requestAccess()
        case .fullDisk: openSettings(for: kind)
        case .folders: requestFolders()
        }
    }

    static func openSettings(for kind: Kind) {
        openSettingsPane(settingsPane(for: kind))
    }

    static func openSettingsPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    static func settingsPane(for kind: Kind) -> String {
        switch kind {
        case .accessibility: "Privacy_Accessibility"
        case .automation: "Privacy_Automation"
        case .calendar: "Privacy_Calendars"
        case .location: "Privacy_LocationServices"
        case .bluetooth: "Privacy_Bluetooth"
        case .fullDisk: "Privacy_AllFiles"
        case .folders: "Privacy_FilesAndFolders"
        }
    }

    private static func askedKey(_ kind: Kind) -> String { "permissions.asked.\(kind.rawValue)" }
    private static func wasAsked(_ kind: Kind) -> Bool { UserDefaults.standard.bool(forKey: askedKey(kind)) }
    private static func markAsked(_ kind: Kind) { UserDefaults.standard.set(true, forKey: askedKey(kind)) }

    // MARK: - Musique et Spotify (Automatisation)

    /// Apps pilotées par AppleScript (voir LegacyPlayers).
    static let scriptedPlayers = ["com.apple.Music", "com.spotify.client"]

    private static var runningPlayers: [String] {
        scriptedPlayers.filter { id in NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == id } }
    }

    private static var automationState: State {
        let running = runningPlayers
        guard !running.isEmpty else {
            return .unavailable("Musique et Spotify sont fermés : macOS posera la question à leur prochaine ouverture.")
        }
        let results = running.map { automationStatus(bundleID: $0, ask: false) }
        if results.contains(noErr) { return .granted }
        if results.contains(OSStatus(errAEEventWouldRequireUserConsent)) { return .notAsked }
        return .denied
    }

    private static func requestAutomation() {
        let running = runningPlayers
        // La question de macOS bloque jusqu'à la réponse : jamais sur le fil principal.
        DispatchQueue.global(qos: .userInitiated).async {
            for id in running { _ = automationStatus(bundleID: id, ask: true) }
            DispatchQueue.main.async { MainActor.assumeIsolated { MusicManager.shared.refreshPlayers() } }
        }
    }

    /// Droit d'envoyer à l'app les événements d'AppleScript (« get » : titre, position…).
    nonisolated static func automationStatus(bundleID: String, ask: Bool) -> OSStatus {
        var target = AEAddressDesc()
        let bytes = Array(bundleID.utf8)
        guard AECreateDesc(DescType(typeApplicationBundleID), bytes, bytes.count, &target) == noErr else { return OSStatus(procNotFound) }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, AEEventClass(kCoreEventClass), AEEventID(kAEGetData), ask)
    }

    // MARK: - Bureau et Téléchargements

    private static let foldersGrantedKey = "permissions.folders.granted"
    private static var watchersStarted = false
    /// Question de macOS en cours pour les dossiers (réponse pas encore connue).
    private static var foldersCheckInFlight = false

    /// Captures (Bureau ou dossier choisi) et téléchargements : macOS demande l'accès à chaque dossier
    /// la première fois qu'on le lit. La question bloque le fil qui lit : on la pose à côté.
    private static func requestFolders() {
        checkFolders { startFolderWatchers() }
    }

    /// Démarre la surveillance des captures et des téléchargements, une seule fois.
    static func startFolderWatchers() {
        guard !watchersStarted else { return }
        watchersStarted = true
        ScreenshotManager.shared.start()
        DownloadManager.shared.start()
    }

    /// Au lancement : on ne relit les dossiers que si la question a déjà été posée (pas de nouvelle question).
    static func startFolderWatchersIfAllowed() {
        guard wasAsked(.folders) || hasFullDiskAccess else { return }
        checkFolders { startFolderWatchers() }
    }

    private static func checkFolders(then done: @escaping @MainActor () -> Void) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        foldersCheckInFlight = true
        DispatchQueue.global(qos: .userInitiated).async {
            let readable = ["Desktop", "Downloads"].allSatisfy {
                (try? FileManager.default.contentsOfDirectory(atPath: home.appending(path: $0).path)) != nil
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    UserDefaults.standard.set(readable, forKey: foldersGrantedKey)
                    foldersCheckInFlight = false
                    done()
                }
            }
        }
    }

    // MARK: - Anciennes installations

    /// Installation d'avant l'assistant : macOS a déjà posé ses questions, on ne les repose pas.
    static func adoptPreviousInstallIfNeeded() {
        guard !Onboarding.isDone else { return }
        let alreadyAnswered = EKEventStore.authorizationStatus(for: .event) != .notDetermined
            || CLLocationManager().authorizationStatus != .notDetermined
            || CBManager.authorization != .notDetermined
            || AXIsProcessTrusted()
        guard alreadyAnswered else { return }
        for kind in Kind.allCases { markAsked(kind) }
        Onboarding.markDone()
    }
}

/// Assistant du premier lancement.
enum Onboarding {
    static let doneKey = "onboarding.done"
    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }
    static func markDone() { UserDefaults.standard.set(true, forKey: doneKey) }
}
