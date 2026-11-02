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

/// Apparition courte (quelques secondes) dans la pastille fermée. Elles passent l'une après l'autre
/// dans une file d'attente : aucune n'est perdue si une autre est déjà à l'écran.
enum Moment: Equatable {
    case charging, unplugged, charged
    case lowBattery(Int)
    case deviceConnected(BluetoothDevice)
    case caffeine(Bool)
    case timerDone
    case newTrack(Track, NSImage?)

    var activity: LiveActivity {
        switch self {
        case .charging: .charging
        case .unplugged: .unplugged
        case .charged: .charged
        case .lowBattery: .lowBattery
        case .deviceConnected: .deviceConnected
        case .caffeine: .caffeine
        case .timerDone: .timerDone
        case .newTrack: .newTrack
        }
    }

    var duration: TimeInterval {
        switch self {
        case .charging: 3
        case .unplugged: 2.5
        case .charged, .lowBattery, .deviceConnected: 4
        case .caffeine: 2
        case .timerDone: 5
        case .newTrack: 2.5
        }
    }

    /// Un nouveau moment du même genre remplace l'ancien plutôt que de s'ajouter à la file.
    func replaces(_ other: Moment) -> Bool {
        switch (self, other) {
        case (.charging, .charging), (.charging, .unplugged), (.unplugged, .unplugged), (.unplugged, .charging),
             (.charged, .charged), (.lowBattery, .lowBattery), (.caffeine, .caffeine),
             (.timerDone, .timerDone), (.newTrack, .newTrack):
            true
        case let (.deviceConnected(a), .deviceConnected(b)):
            a.id == b.id
        default:
            false
        }
    }
}

/// Activité affichée de part et d'autre de la pastille compacte (façon « Live Activity »).
enum LiveActivity: Equatable { case none, music, charging, unplugged, charged, deviceConnected, lowBattery, timer, timerDone, stopwatch, newTrack, download, caffeine, code, hud }
