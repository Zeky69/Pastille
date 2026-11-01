import ApplicationServices
import CoreBluetooth
import CoreGraphics
import CoreLocation
import EventKit
import Foundation
import SQLite3

/// État des autorisations macOS et des fonctions qui passent par des chemins non officiels.
/// Affiché dans Réglages › Autorisations ; une fonction en panne s'y signale au lieu de se taire.
enum HealthCheck {
    enum Status: Equatable {
        case ok
        case missing
        case broken(String)
        case unknown(String)
    }

    struct Item: Identifiable, Equatable {
        var id: String { title }
        var title: String
        var detail: String
        var symbol: String
        var status: Status
        /// Volet des Réglages Système à ouvrir pour corriger.
        var settingsPane: String?
    }

    // MARK: - Autorisations

    static func permissions() -> [Item] {
        [
            Item(title: "Accessibilité", detail: "Remplacer l'indicateur de volume et de luminosité d'Apple.",
                 symbol: "accessibility", status: AXIsProcessTrusted() ? .ok : .missing,
                 settingsPane: "Privacy_Accessibility"),
            Item(title: "Surveillance de l'entrée", detail: "Repérer les touches de volume et de luminosité.",
                 symbol: "keyboard", status: CGPreflightListenEventAccess() ? .ok : .missing,
                 settingsPane: "Privacy_ListenEvent"),
            Item(title: "Accès complet au disque", detail: "Codes de vérification dans Messages et Mail.",
                 symbol: "internaldrive", status: canReadMessages ? .ok : .missing,
                 settingsPane: "Privacy_AllFiles"),
            Item(title: "Calendrier", detail: "Événements dans la page d'accueil.",
                 symbol: "calendar", status: EKEventStore.authorizationStatus(for: .event) == .fullAccess ? .ok : .missing,
                 settingsPane: "Privacy_Calendars"),
            Item(title: "Localisation", detail: "Météo de l'endroit où tu es.",
                 symbol: "location.fill", status: locationStatus,
                 settingsPane: "Privacy_LocationServices"),
            Item(title: "Bluetooth", detail: "Batterie des casques et appareils connectés.",
                 symbol: "dot.radiowaves.left.and.right",
                 status: CBManager.authorization == .allowedAlways ? .ok : .missing,
                 settingsPane: "Privacy_Bluetooth"),
        ]
    }

    private static var canReadMessages: Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Messages/chat.db").path
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        try? handle.close()
        return true
    }

    private static var locationStatus: Status {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: .ok
        case .notDetermined: .unknown("Pas encore demandée")
        default: .missing
        }
    }

    // MARK: - Fonctions non officielles (peuvent casser avec une mise à jour de macOS)

    /// Vérifications un peu plus lentes (lancement de petits processus) : à appeler hors du fil principal.
    static func features() -> [Item] {
        [
            Item(title: "Minuteur et chronomètre d'Horloge", detail: "Lus dans les préférences d'Horloge.",
                 symbol: "timer", status: clockStatus, settingsPane: nil),
            Item(title: "Pochettes Apple Music", detail: "Lecteur « À l'écoute » de macOS, via perl.",
                 symbol: "music.note",
                 status: MusicManager.nowPlayingReaderWorks() ? .ok : .broken("Le lecteur ne répond plus"),
                 settingsPane: nil),
            Item(title: "Batterie des casques", detail: "Module Bluetooth de macOS.",
                 symbol: "headphones",
                 status: BluetoothManager.levelsReaderWorks() ? .ok : .broken("Le lecteur ne répond plus"),
                 settingsPane: nil),
            Item(title: "Codes dans Messages", detail: "Base de données de Messages.",
                 symbol: "message.fill", status: messagesStatus, settingsPane: "Privacy_AllFiles"),
            Item(title: "Codes dans Mail", detail: "Base de données de Mail.",
                 symbol: "envelope.fill", status: mailStatus, settingsPane: "Privacy_AllFiles"),
            Item(title: "Luminosité", detail: "Framework d'affichage de macOS.",
                 symbol: "sun.max.fill",
                 status: HUDManager.brightnessControlAvailable ? .ok : .broken("Écran intégré introuvable ou fonction retirée"),
                 settingsPane: nil),
        ]
    }

    private static var clockStatus: Status {
        let domain = "com.apple.mobiletimerd" as CFString
        CFPreferencesAppSynchronize(domain)
        let timers = CFPreferencesCopyAppValue("MTTimers" as CFString, domain) as? [String: Any]
        guard let timers else { return .unknown("Horloge jamais utilisée ?") }
        return timers["MTTimers"] is [Any] ? .ok : .broken("Format des données d'Horloge inconnu")
    }

    private static var messagesStatus: Status {
        guard canReadMessages else { return .missing }
        return querySucceeds(path: "Library/Messages/chat.db", sql: "SELECT ROWID, text, attributedBody, is_from_me, handle_id FROM message LIMIT 1")
            ? .ok : .broken("Structure de la base de Messages changée")
    }

    private static var mailStatus: Status {
        let mail = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Mail")
        guard let version = ((try? FileManager.default.contentsOfDirectory(atPath: mail.path)) ?? [])
            .filter({ $0.hasPrefix("V") }).sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }).last
        else { return canReadMessages ? .unknown("App Mail jamais configurée ?") : .missing }
        return querySucceeds(path: "Library/Mail/\(version)/MailData/Envelope Index",
                             sql: "SELECT m.ROWID, s.subject, su.summary, m.date_received FROM messages m LEFT JOIN subjects s ON s.ROWID = m.subject LEFT JOIN summaries su ON su.ROWID = m.summary LIMIT 1")
            ? .ok : .broken("Structure de la base de Mail changée")
    }

    private static func querySucceeds(path: String, sql: String) -> Bool {
        var db: OpaquePointer?
        let full = FileManager.default.homeDirectoryForCurrentUser.appending(path: path).path
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(full, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return false }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        return sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK
    }
}
