import Foundation

/// Lecture du minuteur et du chronomètre d'Horloge depuis ses préférences (`com.apple.mobiletimerd`).
/// Le service d'Horloge refuse les apps tierces, mais il recopie l'état des minuteurs dans ce domaine.
enum ClockTimerSource {
    private static let domain = "com.apple.mobiletimerd" as CFString

    /// États observés : 1 = arrêté, 2 = en pause, 3 = en cours.
    private enum State: Int { case stopped = 1, paused = 2, running = 3 }

    static func read() -> ClockTimer? {
        CFPreferencesAppSynchronize(domain)
        guard let root = CFPreferencesCopyAppValue("MTTimers" as CFString, domain) as? [String: Any],
              let timers = root["MTTimers"] as? [[String: Any]] else { return nil }

        let now = Date()
        let active = timers.compactMap { entry -> ClockTimer? in
            guard let timer = entry["$MTTimer"] as? [String: Any] else { return nil }
            return parse(timer, now: now)
        }
        // Plusieurs minuteurs : on montre celui qui finit le plus tôt.
        return active.min { $0.remaining(at: now) < $1.remaining(at: now) }
    }

    /// Chronomètre : 0 = remis à zéro, 1 = en pause, 2 = en cours.
    static func readStopwatch() -> ClockStopwatch? {
        guard let root = CFPreferencesCopyAppValue("MTStopwatches" as CFString, domain) as? [String: Any],
              let list = root["MTStopwatches"] as? [[String: Any]],
              let watch = list.first?["$MTStopwatch"] as? [String: Any],
              let state = watch["MTStopwatchState"] as? Int else { return nil }
        let offset = watch["MTStopwatchOffset"] as? Double ?? 0
        switch state {
        case 2:
            guard let start = watch["MTStopwatchStartDate"] as? Date else { return nil }
            return ClockStopwatch(offset: offset, startDate: start)
        case 1 where offset > 0:
            return ClockStopwatch(offset: offset, startDate: nil)
        default:
            return nil
        }
    }

    static func parse(_ timer: [String: Any], now: Date) -> ClockTimer? {
        guard let raw = timer["MTTimerState"] as? Int,
              let state = State(rawValue: raw), state != .stopped,
              let duration = timer["MTTimerDuration"] as? Double, duration > 0,
              let fireTime = timer["MTTimerFireTime"] as? [String: Any] else { return nil }

        switch state {
        case .running:
            guard let date = (fireTime["$MTTimerDate"] as? [String: Any])?["MTTimerTimeDate"] as? Date,
                  date > now else { return nil }
            return ClockTimer(duration: duration, fireDate: date, pausedRemaining: 0)
        case .paused:
            let remaining = (fireTime["$MTTimerTimeInterval"] as? [String: Any])?["MTTimerTimeInterval"] as? Double
            return ClockTimer(duration: duration, fireDate: nil, pausedRemaining: remaining ?? duration)
        case .stopped:
            return nil
        }
    }
}
