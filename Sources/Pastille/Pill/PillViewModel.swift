import AppKit
import Combine
import SwiftUI

enum PillState { case compact, expanded }

enum PillTab: String, CaseIterable, Identifiable {
    case home, screenshots
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: "house.fill"
        case .screenshots: "camera.viewfinder"
        }
    }
}

/// Activité affichée de part et d'autre de la pastille compacte (façon « Live Activity »).
enum LiveActivity: Equatable { case none, music, charging, unplugged, charged, deviceConnected, lowBattery, timer, stopwatch, download, caffeine, code, hud }

@MainActor
final class PillViewModel: ObservableObject {
    @Published var state: PillState = .compact
    @Published var tab: PillTab = .home
    /// Sens du dernier changement d'onglet (pour faire glisser la page du bon côté).
    @Published private(set) var tabMovesForward = true

    var availableTabs: [PillTab] {
        Appearance.bool(Appearance.showScreenshotsTabKey) ? PillTab.allCases : [.home]
    }

    func select(_ newTab: PillTab) {
        guard newTab != tab, let from = availableTabs.firstIndex(of: tab), let to = availableTabs.firstIndex(of: newTab) else { return }
        tabMovesForward = to > from
        withAnimation(.spring(duration: 0.4, bounce: 0.15)) { tab = newTab }
    }

    /// Page suivante (+1) ou précédente (-1) ; renvoie false au bout.
    @discardableResult
    func moveTab(by offset: Int) -> Bool {
        let tabs = availableTabs
        guard let index = tabs.firstIndex(of: tab), tabs.indices.contains(index + offset) else { return false }
        select(tabs[index + offset])
        return true
    }
    /// Taille de la découpe de l'écran (ou d'une découpe simulée sur un écran externe).
    @Published private(set) var cutoutSize = CGSize(width: 185, height: 32)
    @Published private(set) var liveActivity: LiveActivity = .none

    /// Taille ouverte, selon les réglages « Taille » et « Lecteur » (normale : 640 × 190).
    @Published private(set) var expandedSize = Appearance.expandedSize
    /// Appelé quand la taille ouverte change, pour redimensionner la fenêtre.
    var onExpandedSizeChange: (() -> Void)?

    /// Bref affichage au branchement (.charging) ou au débranchement (.unplugged).
    private var powerFlash: LiveActivity?
    private var powerFlashTask: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Réglages modifiés : nouvelle taille, et on revoit l'activité affichée (activités désactivées…).
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let size = Appearance.expandedSize
                if size != self.expandedSize {
                    self.expandedSize = size
                    self.onExpandedSizeChange?()
                }
                if !Appearance.bool(Appearance.showScreenshotsTabKey), self.tab == .screenshots { self.tab = .home }
                self.refreshLiveActivity()
            }
            .store(in: &cancellables)

        let music = MusicManager.shared
        let battery = BatteryManager.shared

        music.$isPlaying
            .combineLatest(music.$track)
            .sink { [weak self] _, _ in
                DispatchQueue.main.async { self?.refreshLiveActivity() }
            }
            .store(in: &cancellables)

        HUDManager.shared.$current
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshLiveActivity() }
            }
            .store(in: &cancellables)

        TimerManager.shared.$timer
            .map { $0.map { $0.isPaused ? "paused" : "running" } ?? "none" }
            .combineLatest(
                TimerManager.shared.$stopwatch.map { $0.map { $0.isPaused ? "paused" : "running" } ?? "none" },
                TimerManager.shared.$stopwatchDigits
            )
            .map { "\($0)\($1)\($2)" }
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshLiveActivity() }
            }
            .store(in: &cancellables)

        DownloadManager.shared.$state
            .map { state -> Int in
                switch state {
                case .idle: 0
                case .downloading: 1
                case .finished: 2
                }
            }
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshLiveActivity() }
            }
            .store(in: &cancellables)

        VerificationCodeManager.shared.$current
            .map { $0?.code }
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshLiveActivity() }
            }
            .store(in: &cancellables)

        BluetoothManager.shared.$justConnected
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshLiveActivity() }
            }
            .store(in: &cancellables)

        BatteryManager.shared.$justFullyCharged
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshLiveActivity() }
            }
            .store(in: &cancellables)

        CaffeineManager.shared.$flash
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshLiveActivity() }
            }
            .store(in: &cancellables)

        battery.$lowAlert
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshLiveActivity() }
            }
            .store(in: &cancellables)

        battery.$isPluggedIn
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] plugged in self?.flashPower(plugged ? .charging : .unplugged) }
            .store(in: &cancellables)
    }

    var isExpanded: Bool { state == .expanded }

    /// Taille compacte, élargie quand une activité est en cours.
    var compactSize: CGSize {
        CGSize(width: cutoutSize.width + 2 * sideWidth, height: cutoutSize.height)
    }

    /// Largeur ajoutée de chaque côté de la découpe (symétrique pour rester centré).
    var sideWidth: CGFloat {
        switch liveActivity {
        case .none: 0
        case .music, .charging, .unplugged: cutoutSize.height + 10
        case .lowBattery: 42
        case .download: cutoutSize.height + 6
        case .caffeine: 58
        case .charged: 60
        case .deviceConnected: 96
        // Largeur du code (chiffres à ~7,4 pt) + marge extérieure, 2 pt de débord côté encoche.
        case .code: CGFloat(VerificationCodeManager.shared.current?.code.count ?? 6) * 7.4 + 10
        case .timer: timerSideWidth
        case .stopwatch: [48, 56, 68][TimerManager.shared.stopwatchDigits] + 12 - 2
        case .hud: 66
        }
    }

    /// Juste la place du temps restant (« 4:59 », « 14:59 » ou « 1:00:00 ») et de sa marge extérieure ;
    /// le texte déborde de 2 pt côté encoche pour coller au bord de la découpe.
    private var timerSideWidth: CGFloat {
        let duration = TimerManager.shared.timer?.duration ?? 0
        let text: CGFloat = duration >= 3600 ? 48 : duration >= 600 ? 36 : 28
        return text + 12 - 2
    }

    var currentSize: CGSize { isExpanded ? expandedSize : compactSize }

    func update(for screen: NSScreen) {
        let inset = screen.safeAreaInsets.top
        if inset > 0,
           let left = screen.auxiliaryTopLeftArea?.width,
           let right = screen.auxiliaryTopRightArea?.width {
            cutoutSize = CGSize(width: screen.frame.width - left - right + 4, height: inset)
        } else {
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            cutoutSize = CGSize(width: 185, height: max(menuBar, 24))
        }
    }

    private func flashPower(_ activity: LiveActivity) {
        powerFlash = activity
        refreshLiveActivity()
        powerFlashTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.powerFlash = nil
            self?.refreshLiveActivity()
        }
        powerFlashTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + (activity == .charging ? 3 : 2.5), execute: task)
    }

    /// Minuteur ou chronomètre : ce qui tourne passe avant ce qui est en pause, le minuteur d'abord.
    private var clockActivity: LiveActivity? {
        let timer = TimerManager.shared.timer
        let stopwatch = TimerManager.shared.stopwatch
        if timer?.isPaused == false { return .timer }
        if stopwatch?.isPaused == false { return .stopwatch }
        if timer != nil { return .timer }
        if stopwatch != nil { return .stopwatch }
        return nil
    }

    private func refreshLiveActivity() {
        let music = MusicManager.shared
        let new: LiveActivity
        if HUDManager.shared.current != nil {
            new = .hud
        } else if Appearance.bool(Appearance.codeActivityKey), VerificationCodeManager.shared.current != nil {
            new = .code
        } else if CaffeineManager.shared.flash {
            new = .caffeine
        } else if Appearance.bool(Appearance.batteryAlertKey), BatteryManager.shared.lowAlert != nil {
            new = .lowBattery
        } else if BluetoothManager.shared.justConnected != nil {
            new = .deviceConnected
        } else if BatteryManager.shared.justFullyCharged {
            new = .charged
        } else if let powerFlash {
            new = powerFlash
        } else if Appearance.bool(Appearance.clockActivityKey), let clock = clockActivity {
            new = clock
        } else if Appearance.bool(Appearance.downloadActivityKey), DownloadManager.shared.state != .idle {
            new = .download
        } else if Settings.musicLiveActivity, music.isPlaying, music.track != nil {
            new = .music
        } else {
            new = .none
        }
        if new != liveActivity {
            withAnimation(PillAnimation.activity) { liveActivity = new }
        }
    }
}
