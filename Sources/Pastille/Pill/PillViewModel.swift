import AppKit
import Combine
import SwiftUI

@MainActor
final class PillViewModel: ObservableObject {
    @Published var state: PillState = .compact {
        // Pastille refermée : une annonce de morceau lancée pendant qu'elle était ouverte n'a plus lieu d'être.
        didSet {
            if state == .compact, oldValue == .expanded {
                dropMoments { if case .newTrack = $0 { true } else { false } }
            }
        }
    }
    @Published var tab: PillTab = .home {
        didSet { if tab != oldValue { refreshExpandedSize() } }
    }

    /// Hauteur mesurée du contenu de chaque page, par mise en page, mémorisée d'un lancement à l'autre
    /// pour que la pastille s'ouvre directement à la bonne taille.
    private var contentHeights = UserDefaults.standard.dictionary(forKey: "measuredContentHeights") as? [String: Double] ?? [:]

    private func contentKey(for tab: PillTab) -> String { "\(tab.rawValue)|\(Appearance.contentKey)" }

    /// Appelé par la page affichée avec sa hauteur réelle.
    func reportContentHeight(_ height: CGFloat, for tab: PillTab) {
        let key = contentKey(for: tab)
        guard height > 1, abs((contentHeights[key] ?? 0) - Double(height)) > 0.5 else { return }
        contentHeights[key] = Double(height)
        UserDefaults.standard.set(contentHeights, forKey: "measuredContentHeights")
        refreshExpandedSize()
    }
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
    /// Une app est en plein écran sur l'écran de la pastille (vidéo, jeu, présentation).
    @Published var fullscreenAppActive = false {
        didSet { if fullscreenAppActive != oldValue { refreshLiveActivity() } }
    }

    /// En plein écran, la pastille fermée se replie dans l'encoche puis s'efface ; le volume et la
    /// luminosité restent visibles, et elle réapparaît dès qu'on l'ouvre en approchant la souris.
    var isConcealed: Bool {
        fullscreenAppActive && Settings.hideInFullscreen && !isExpanded && liveActivity != .hud
    }

    /// Taille ouverte, selon les réglages « Taille » et « Lecteur » (normale : 640 × 190).
    @Published private(set) var expandedSize = Appearance.expandedSize(cutout: CGSize(width: 185, height: 32))
    /// Appelé quand la taille ouverte change, pour redimensionner la fenêtre.
    var onExpandedSizeChange: (() -> Void)?

    /// Moment à l'écran (ou en tête de file s'il est momentanément caché par le volume).
    @Published private(set) var moment: Moment?
    private var pendingMoments: [Moment] = []
    /// Moments en attente, dans l'ordre (lecture seule, pour les tests).
    var queuedMoments: [Moment] { pendingMoments }
    /// Le compte à rebours d'un moment ne tourne que pendant qu'il est réellement visible.
    private var momentRemaining: TimeInterval = 0
    private var momentShownAt: Date?
    private var momentWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Réglages modifiés : nouvelle taille, et on revoit l'activité affichée (activités désactivées…).
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshExpandedSize()
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

        // Le total d'un téléchargement sans pourcentage arrive après coup : la pastille s'élargit un peu.
        DownloadManager.shared.$measure
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    withAnimation(PillAnimation.activity) { self?.objectWillChange.send() }
                }
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

        VerificationCodeManager.shared.$showsInClosedPill
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshLiveActivity() }
            }
            .store(in: &cancellables)

        BluetoothManager.shared.connections
            .receive(on: DispatchQueue.main)
            .sink { [weak self] device in
                if Appearance.bool(Appearance.deviceConnectedKey) { self?.enqueue(.deviceConnected(device)) }
            }
            .store(in: &cancellables)

        // La batterie d'un appareil qui vient de se connecter arrive après coup : on redessine.
        BluetoothManager.shared.$devices
            .sink { [weak self] _ in
                guard case .deviceConnected = self?.moment else { return }
                DispatchQueue.main.async { self?.objectWillChange.send() }
            }
            .store(in: &cancellables)

        battery.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                switch event {
                case .full:
                    if Appearance.bool(Appearance.powerKey) { self?.enqueue(.charged) }
                case .low(let threshold):
                    if Appearance.bool(Appearance.batteryAlertKey) { self?.enqueue(.lowBattery(threshold)) }
                }
            }
            .store(in: &cancellables)

        TimerManager.shared.finished
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if Appearance.bool(Appearance.timerDoneKey) { self?.enqueue(.timerDone) }
            }
            .store(in: &cancellables)

        MusicManager.shared.trackChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                // Pastille ouverte : le morceau est déjà sous les yeux dans le lecteur.
                guard Appearance.bool(Appearance.newTrackKey), self?.isExpanded == false else { return }
                self?.enqueue(.newTrack(track, MusicManager.shared.artwork))
            }
            .store(in: &cancellables)

        CaffeineManager.shared.toggled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOn in self?.enqueue(.caffeine(isOn)) }
            .store(in: &cancellables)

        battery.$isPluggedIn
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] plugged in
                // Branché : l'alerte de batterie faible n'a plus lieu d'être.
                if plugged { self?.dropMoments { if case .lowBattery = $0 { true } else { false } } }
                if Appearance.bool(Appearance.powerKey) { self?.enqueue(plugged ? .charging : .unplugged) }
            }
            .store(in: &cancellables)
    }

    var isExpanded: Bool { state == .expanded }

    /// Taille compacte, élargie quand une activité est en cours.
    var compactSize: CGSize {
        CGSize(width: cutoutSize.width + 2 * sideWidth, height: cutoutSize.height + extraHeight)
    }

    /// Hauteur ajoutée sous l'encoche : le nouveau morceau y affiche son titre en entier.
    var extraHeight: CGFloat {
        liveActivity == .newTrack ? 38 : 0
    }

    /// Largeur ajoutée de chaque côté de la découpe (symétrique pour rester centré).
    var sideWidth: CGFloat {
        switch liveActivity {
        case .none: 0
        case .music, .charging, .unplugged: cutoutSize.height + 10
        case .lowBattery: 42
        // Pastille fermée : flèche + total court (« 812 Mo ») quand l'app ne donne pas de pourcentage.
        case .download: DownloadManager.shared.measure != nil ? 58 : cutoutSize.height + 6
        case .caffeine: 58
        case .charged: 60
        case .timerDone: 68
        case .newTrack: newTrackSideWidth
        case .deviceConnected: deviceSideWidth
        // Largeur du code (chiffres à ~7,4 pt) + marge extérieure, 2 pt de débord côté encoche.
        case .code: CGFloat(VerificationCodeManager.shared.current?.code.count ?? 6) * 7.4 + 10
        case .timer: timerSideWidth
        case .stopwatch: [48, 56, 68][TimerManager.shared.stopwatchDigits] + 12 - 2
        case .hud: 66
        }
    }

    /// Icône + nom de l'appareil à gauche (« AirPods Pro » en entier), pourcentage et anneau à droite.
    private var deviceSideWidth: CGFloat {
        guard case .deviceConnected(let device) = moment else { return 96 }
        let name = (device.name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width
        return min(max(12 + 22 + 6 + name + 10, 96), 170)
    }

    /// Assez large pour le titre du nouveau morceau sous l'encoche (pochette + titre + spectre),
    /// sans dépasser une largeur raisonnable : au-delà, le titre est coupé par « … ».
    private var newTrackSideWidth: CGFloat {
        guard case .newTrack(let track, _) = moment else { return 64 }
        let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        let titleWidth = max(
            (track.title as NSString).size(withAttributes: [.font: font]).width,
            (track.artist as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10.5)]).width
        )
        let row = 30 + 9 + titleWidth + 9 + 18 + 2 * 14
        return min(max((row - cutoutSize.width) / 2, 64), 190)
    }

    /// Juste la place du temps restant (« 4:59 », « 14:59 » ou « 1:00:00 ») et de sa marge extérieure ;
    /// le texte déborde de 2 pt côté encoche pour coller au bord de la découpe.
    private var timerSideWidth: CGFloat {
        let duration = TimerManager.shared.timer?.duration ?? 0
        let text: CGFloat = duration >= 3600 ? 48 : duration >= 600 ? 36 : 28
        return text + 12 - 2
    }

    var currentSize: CGSize { isExpanded ? expandedSize : compactSize }

    /// Largeur selon les réglages ; hauteur = en-tête (encoche) + 6 pt + contenu mesuré + 12 pt de marge basse.
    private func refreshExpandedSize() {
        var size = Appearance.expandedSize(cutout: cutoutSize)
        if let content = contentHeights[contentKey(for: tab)] {
            size.height = min(max(cutoutSize.height + 6 + CGFloat(content) + 12, cutoutSize.height + 50), 320)
        }
        guard size != expandedSize else { return }
        withAnimation(.spring(duration: 0.35, bounce: 0.12)) { expandedSize = size }
        onExpandedSizeChange?()
    }

    func update(for screen: NSScreen) {
        defer { refreshExpandedSize() }
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

    // MARK: - File d'attente des moments

    func enqueue(_ new: Moment) {
        if let current = moment, new.replaces(current) {
            // Même genre déjà à l'écran : on met à jour et on relance son compte à rebours.
            moment = new
            restartMomentTimer()
        } else {
            pendingMoments.removeAll { new.replaces($0) }
            pendingMoments.append(new)
            if moment == nil { advanceMoment() }
        }
        refreshLiveActivity()
    }

    private func dropMoments(where match: (Moment) -> Bool) {
        pendingMoments.removeAll(where: match)
        if let moment, match(moment) { advanceMoment() }
    }

    private func advanceMoment() {
        momentWork?.cancel()
        momentWork = nil
        momentShownAt = nil
        moment = pendingMoments.isEmpty ? nil : pendingMoments.removeFirst()
        momentRemaining = moment?.duration ?? 0
        refreshLiveActivity()
    }

    private func restartMomentTimer() {
        momentRemaining = moment?.duration ?? 0
        if momentShownAt != nil {
            momentShownAt = nil
            momentWork?.cancel()
            momentWork = nil
        }
    }

    /// Démarre ou met en pause le compte à rebours selon que le moment est visible ou caché.
    private func syncMomentTimer() {
        let visible = moment.map { liveActivity == $0.activity } ?? false
        if visible, momentShownAt == nil {
            momentShownAt = Date()
            let work = DispatchWorkItem { [weak self] in self?.advanceMoment() }
            momentWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + momentRemaining, execute: work)
        } else if !visible, let shownAt = momentShownAt {
            momentRemaining = max(momentRemaining - Date().timeIntervalSince(shownAt), 0.5)
            momentShownAt = nil
            momentWork?.cancel()
            momentWork = nil
        }
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
        var new: LiveActivity
        if HUDManager.shared.current != nil {
            new = .hud
        } else if Appearance.bool(Appearance.codeActivityKey), VerificationCodeManager.shared.showsInClosedPill,
                  VerificationCodeManager.shared.current != nil {
            // Le code ne reste que 5 s dans la pastille fermée : il passe avant les autres moments,
            // qui attendent leur tour dans la file.
            new = .code
        } else if let moment {
            new = moment.activity
        } else if Appearance.bool(Appearance.clockActivityKey), let clock = clockActivity {
            new = clock
        } else if Appearance.bool(Appearance.downloadActivityKey), DownloadManager.shared.state != .idle {
            new = .download
        } else if Settings.musicLiveActivity, music.isPlaying, music.track != nil {
            new = .music
        } else {
            new = .none
        }
        // Plein écran : l'activité se replie dans l'encoche (même ressort qu'une fin d'activité).
        if fullscreenAppActive, Settings.hideInFullscreen, new != .hud {
            new = .none
        }
        if new != liveActivity {
            withAnimation(PillAnimation.activity) { liveActivity = new }
        }
        syncMomentTimer()
    }
}
