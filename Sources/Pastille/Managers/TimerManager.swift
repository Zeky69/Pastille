import Combine
import Foundation

/// Minuteur en cours dans l'app Horloge.
struct ClockTimer: Equatable {
    var duration: Double
    /// Date de fin si le minuteur tourne ; nil s'il est en pause.
    var fireDate: Date?
    /// Temps restant figé quand le minuteur est en pause.
    var pausedRemaining: Double

    var isPaused: Bool { fireDate == nil }

    func remaining(at date: Date = Date()) -> Double {
        guard let fireDate else { return pausedRemaining }
        return max(fireDate.timeIntervalSince(date), 0)
    }

    func progress(at date: Date = Date()) -> Double {
        duration > 0 ? remaining(at: date) / duration : 0
    }
}

/// Chronomètre de l'app Horloge.
struct ClockStopwatch: Equatable {
    /// Temps accumulé avant le dernier démarrage.
    var offset: Double
    /// Moment du dernier démarrage si le chronomètre tourne ; nil s'il est en pause.
    var startDate: Date?

    var isPaused: Bool { startDate == nil }

    func elapsed(at date: Date = Date()) -> Double {
        guard let startDate else { return offset }
        return offset + max(date.timeIntervalSince(startDate), 0)
    }
}

@MainActor
final class TimerManager: ObservableObject {
    static let shared = TimerManager()

    @Published private(set) var timer: ClockTimer?
    @Published private(set) var stopwatch: ClockStopwatch?
    /// Format du chronomètre (« m:ss,cc », « mm:ss,cc » ou « h:mm:ss,cc ») : fixe la largeur de la pastille.
    @Published private(set) var stopwatchDigits = 0
    /// Un minuteur vient d'arriver à zéro (durée totale, pour l'affichage).
    let finished = PassthroughSubject<Double, Never>()

    /// Horloge ne prévient personne et n'écrit son fichier sur disque que de temps en temps :
    /// on relit ses préférences en mémoire (via cfprefsd, ~0,02 ms) toutes les demi-secondes,
    /// pour qu'une pause ou une reprise se voie presque aussitôt.
    private var poll: Timer?
    private var endWork: DispatchWorkItem?

    /// Un minuteur ou chronomètre en pause s'efface après ce délai ; il revient s'il repart.
    private static let pausedLifetime: TimeInterval = 10
    private var timerPause: (value: ClockTimer, since: Date)?
    private var stopwatchPause: (value: ClockStopwatch, since: Date)?

    func start() {
        poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { TimerManager.shared.refresh() }
        }
        poll?.tolerance = 0.1
        refresh()
    }

    func refresh() {
        let now = Date()
        let new = Self.hidingStalePause(ClockTimerSource.read(), \.isPaused, pause: &timerPause, now: now)
        // Le minuteur en cours disparaît alors que sa fin est atteinte : il vient de sonner
        // (et non d'être annulé, ce qui le ferait disparaître avant l'heure).
        if new == nil, let old = timer, let fireDate = old.fireDate, fireDate.timeIntervalSince(now) < 1 {
            finished.send(old.duration)
        }
        if new != timer { timer = new }
        let watch = Self.hidingStalePause(ClockTimerSource.readStopwatch(), \.isPaused, pause: &stopwatchPause, now: now)
        if watch != stopwatch { stopwatch = watch }
        let elapsed = watch?.elapsed() ?? 0
        let digits = elapsed >= 3600 ? 2 : elapsed >= 600 ? 1 : 0
        if digits != stopwatchDigits { stopwatchDigits = digits }
        scheduleEnd()
    }

    /// Renvoie nil pour une pause qui dure depuis plus de `pausedLifetime`.
    /// Une nouvelle pause (valeur différente) repart pour 10 secondes.
    private static func hidingStalePause<T: Equatable>(
        _ value: T?, _ isPaused: KeyPath<T, Bool>, pause: inout (value: T, since: Date)?, now: Date
    ) -> T? {
        guard let value, value[keyPath: isPaused] else {
            pause = nil
            return value
        }
        if pause?.value != value { pause = (value, now) }
        return now.timeIntervalSince(pause!.since) < pausedLifetime ? value : nil
    }

    /// Fait disparaître le minuteur pile à la fin, sans attendre la prochaine relecture.
    private func scheduleEnd() {
        endWork?.cancel()
        guard let fireDate = timer?.fireDate else { return }
        let work = DispatchWorkItem { TimerManager.shared.refresh() }
        endWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(fireDate.timeIntervalSinceNow, 0) + 0.3, execute: work)
    }
}
