import SwiftUI

/// Personnalisation de la pastille. Les valeurs par défaut reproduisent l'affichage d'origine (préréglage « Classique »).
enum Appearance {
    // MARK: - Clés

    static let presetKey = "appearance.preset"
    static let homeLayoutKey = "appearance.homeLayout"
    static let calendarStyleKey = "appearance.calendarStyle"
    static let musicStyleKey = "appearance.musicStyle"
    static let accentKey = "appearance.accent"
    static let sizeKey = "appearance.size"
    static let showWeatherKey = "appearance.showWeather"
    static let showBluetoothKey = "appearance.showBluetooth"
    static let showCaffeineKey = "appearance.showCaffeine"
    static let showScreenshotsTabKey = "appearance.showScreenshotsTab"

    static let clockActivityKey = "activity.clock"
    static let downloadActivityKey = "activity.download"
    static let codeActivityKey = "activity.code"
    static let hudActivityKey = "activity.hud"
    static let batteryAlertKey = "activity.batteryAlert"
    static let deviceConnectedKey = "activity.deviceConnected"
    static let powerKey = "activity.power"
    static let codesMessagesKey = "codes.messages"
    static let codesMailKey = "codes.mail"
    static let musicPriorityKey = "music.priority"
    static let musicOtherAppsKey = "music.otherApps"
    static let musicSourceBadgeKey = "music.sourceBadge"
    static let weatherUnitKey = "weather.unit"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            presetKey: Preset.classic.rawValue,
            homeLayoutKey: HomeLayout.musicAndCalendar.rawValue,
            calendarStyleKey: CalendarStyle.wheel.rawValue,
            musicStyleKey: MusicStyle.artwork.rawValue,
            accentKey: AccentChoice.artwork.rawValue,
            sizeKey: PillSize.standard.rawValue,
            showWeatherKey: true,
            showBluetoothKey: true,
            showCaffeineKey: true,
            showScreenshotsTabKey: true,
            clockActivityKey: true,
            downloadActivityKey: true,
            codeActivityKey: true,
            hudActivityKey: true,
            batteryAlertKey: true,
            deviceConnectedKey: true,
            powerKey: true,
            codesMessagesKey: true,
            codesMailKey: true,
            musicPriorityKey: true,
            musicOtherAppsKey: true,
            musicSourceBadgeKey: true,
            weatherUnitKey: "celsius",
        ])
    }

    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }

    static var size: PillSize {
        PillSize(rawValue: UserDefaults.standard.string(forKey: sizeKey) ?? "") ?? .standard
    }

    static var homeLayout: HomeLayout {
        HomeLayout(rawValue: UserDefaults.standard.string(forKey: homeLayoutKey) ?? "") ?? .musicAndCalendar
    }

    static var musicStyle: MusicStyle {
        MusicStyle(rawValue: UserDefaults.standard.string(forKey: musicStyleKey) ?? "") ?? .artwork
    }

    /// Taille de la pastille ouverte : celle du réglage, sauf avec le lecteur seul,
    /// où le style décide (compact : bien plus petite ; vinyle et immersif : un peu plus haute).
    /// Ce qui change la hauteur du contenu : la hauteur mesurée est mémorisée pour chaque combinaison.
    static var contentKey: String {
        let defaults = UserDefaults.standard
        return [homeLayoutKey, calendarStyleKey, musicStyleKey, sizeKey]
            .map { defaults.string(forKey: $0) ?? "" }
            .joined(separator: "|")
    }

    /// Lecteur compact seul : en-tête et marges resserrés.
    static var isCompactLayout: Bool { homeLayout == .musicOnly && musicStyle == .compact }

    /// Marge intérieure gauche et droite de la pastille ouverte.
    static var horizontalPadding: CGFloat { isCompactLayout ? 19 + 3 : 19 + 12 }

    /// `cutout` : taille de l'encoche, qui sert d'en-tête à la pastille ouverte.
    static func expandedSize(cutout: CGSize) -> CGSize {
        let cutoutHeight = cutout.height
        let base = size.expanded
        guard homeLayout == .musicOnly else { return base }
        switch musicStyle {
        // En-tête + 6 pt + une ligne de 38 pt, 8 pt, barre de 9 pt + 12 pt de marge basse : rien de plus.
        // Largeur : de chaque côté de l'encoche, la place de l'en-tête resserré (onglets + météo à gauche ;
        // Bluetooth, café, batterie, réglages à droite), plus les marges réduites de la pastille.
        case .compact: return CGSize(width: cutout.width + 2 * 135 + 2 * horizontalPadding, height: cutoutHeight + 6 + 55 + 12)
        case .vinyl, .immersive: return CGSize(width: base.width - 60, height: base.height + 20)
        case .poster: return CGSize(width: base.width - 40, height: base.height + 30)
        case .artwork: return base
        }
    }

    // MARK: - Choix

    enum HomeLayout: String, CaseIterable, Identifiable {
        case musicAndCalendar, musicOnly, calendarOnly
        var id: String { rawValue }
        var label: String {
            switch self {
            case .musicAndCalendar: "Musique + agenda"
            case .musicOnly: "Musique"
            case .calendarOnly: "Agenda"
            }
        }
    }

    enum CalendarStyle: String, CaseIterable, Identifiable {
        case wheel, agenda, month
        var id: String { rawValue }
        var label: String {
            switch self {
            case .wheel: "Frise"
            case .agenda: "Liste"
            case .month: "Mois"
            }
        }
        var symbol: String {
            switch self {
            case .wheel: "calendar.day.timeline.left"
            case .agenda: "list.bullet.rectangle"
            case .month: "calendar"
            }
        }
    }

    /// Styles du lecteur. « artwork » (valeur historique) est le lecteur d'origine, appelé « Classique ».
    enum MusicStyle: String, CaseIterable, Identifiable {
        case artwork, poster, compact, immersive, vinyl
        var id: String { rawValue }
        var label: String {
            switch self {
            case .artwork: "Classique"
            case .poster: "Pochette"
            case .compact: "Compact"
            case .immersive: "Immersif"
            case .vinyl: "Vinyle"
            }
        }
        var symbol: String {
            switch self {
            case .artwork: "rectangle.split.2x1"
            case .poster: "photo.artframe"
            case .compact: "rectangle.compress.vertical"
            case .immersive: "sparkles.rectangle.stack"
            case .vinyl: "record.circle"
            }
        }
        var summary: String {
            switch self {
            case .artwork: "Pochette moyenne, titre, barre et commandes : l'affichage d'origine."
            case .poster: "Grande pochette sur toute la hauteur, titre en gros."
            case .compact: "Une seule ligne ; seule, la pastille devient beaucoup plus petite."
            case .immersive: "La pochette floutée remplit toute la pastille, commandes centrées."
            case .vinyl: "Un disque qui tourne pendant la lecture."
            }
        }
    }

    enum AccentChoice: String, CaseIterable, Identifiable {
        case artwork, blue, purple, pink, red, orange, yellow, green, white
        var id: String { rawValue }
        var label: String {
            switch self {
            case .artwork: "Couleur de la pochette"
            case .blue: "Bleu"
            case .purple: "Violet"
            case .pink: "Rose"
            case .red: "Rouge"
            case .orange: "Orange"
            case .yellow: "Jaune"
            case .green: "Vert"
            case .white: "Blanc"
            }
        }
        /// nil pour « couleur de la pochette ».
        var color: Color? {
            switch self {
            case .artwork: nil
            case .blue: .blue
            case .purple: .purple
            case .pink: .pink
            case .red: .red
            case .orange: .orange
            case .yellow: .yellow
            case .green: .green
            case .white: .white
            }
        }
    }

    enum PillSize: String, CaseIterable, Identifiable {
        case compact, standard, large
        var id: String { rawValue }
        var label: String {
            switch self {
            case .compact: "Petite"
            case .standard: "Normale"
            case .large: "Grande"
            }
        }
        var expanded: CGSize {
            switch self {
            case .compact: CGSize(width: 560, height: 180)
            case .standard: CGSize(width: 640, height: 190)
            case .large: CGSize(width: 740, height: 210)
            }
        }
    }

    // MARK: - Préréglages

    enum Preset: String, CaseIterable, Identifiable {
        case classic, minimal, music, agenda, custom
        var id: String { rawValue }

        static var selectable: [Preset] { [.classic, .minimal, .music, .agenda] }

        var label: String {
            switch self {
            case .classic: "Classique"
            case .minimal: "Minimal"
            case .music: "Musique"
            case .agenda: "Agenda"
            case .custom: "Perso"
            }
        }

        var summary: String {
            switch self {
            case .classic: "Musique et frise des jours, l'affichage d'origine."
            case .minimal: "Petite pastille, lecteur compact, l'essentiel."
            case .music: "Grande pochette floutée en fond, rien d'autre."
            case .agenda: "Tes prochains événements en liste, en grand."
            case .custom: "Tes propres réglages."
            }
        }

        var symbol: String {
            switch self {
            case .classic: "capsule.fill"
            case .minimal: "minus.circle"
            case .music: "music.note"
            case .agenda: "calendar"
            case .custom: "slider.horizontal.3"
            }
        }

        /// Réglages appliqués par le préréglage (les activités ne sont pas touchées).
        var values: [String: Any] {
            switch self {
            case .classic, .custom:
                return [
                    homeLayoutKey: HomeLayout.musicAndCalendar.rawValue,
                    calendarStyleKey: CalendarStyle.wheel.rawValue,
                    musicStyleKey: MusicStyle.artwork.rawValue,
                    accentKey: AccentChoice.artwork.rawValue,
                    sizeKey: PillSize.standard.rawValue,
                    showWeatherKey: true, showBluetoothKey: true, showCaffeineKey: true, showScreenshotsTabKey: true,
                ]
            case .minimal:
                return [
                    homeLayoutKey: HomeLayout.musicOnly.rawValue,
                    calendarStyleKey: CalendarStyle.wheel.rawValue,
                    musicStyleKey: MusicStyle.compact.rawValue,
                    accentKey: AccentChoice.white.rawValue,
                    sizeKey: PillSize.compact.rawValue,
                    showWeatherKey: true, showBluetoothKey: false, showCaffeineKey: false, showScreenshotsTabKey: true,
                ]
            case .music:
                return [
                    homeLayoutKey: HomeLayout.musicOnly.rawValue,
                    calendarStyleKey: CalendarStyle.wheel.rawValue,
                    musicStyleKey: MusicStyle.immersive.rawValue,
                    accentKey: AccentChoice.artwork.rawValue,
                    sizeKey: PillSize.large.rawValue,
                    showWeatherKey: false, showBluetoothKey: true, showCaffeineKey: false, showScreenshotsTabKey: true,
                ]
            case .agenda:
                return [
                    homeLayoutKey: HomeLayout.calendarOnly.rawValue,
                    calendarStyleKey: CalendarStyle.agenda.rawValue,
                    musicStyleKey: MusicStyle.artwork.rawValue,
                    accentKey: AccentChoice.blue.rawValue,
                    sizeKey: PillSize.standard.rawValue,
                    showWeatherKey: true, showBluetoothKey: true, showCaffeineKey: true, showScreenshotsTabKey: true,
                ]
            }
        }

        func apply() {
            let defaults = UserDefaults.standard
            for (key, value) in values { defaults.set(value, forKey: key) }
            defaults.set(rawValue, forKey: presetKey)
        }
    }

    /// Retour à l'affichage d'origine : préréglage Classique et toutes les activités réactivées.
    /// (Les réglages de comportement — survol, haptique, lancement — ne sont pas touchés.)
    static func resetToDefaults() {
        let defaults = UserDefaults.standard
        for key in [clockActivityKey, downloadActivityKey, codeActivityKey, hudActivityKey, batteryAlertKey,
                    deviceConnectedKey, powerKey, codesMessagesKey, codesMailKey,
                    musicPriorityKey, musicOtherAppsKey, musicSourceBadgeKey, weatherUnitKey,
                    Settings.musicLiveActivityKey, Settings.showBatteryPercentKey] {
            defaults.removeObject(forKey: key)
        }
        Preset.classic.apply()
    }

    /// Un réglage modifié à la main fait passer en « Perso ».
    static func markCustom() {
        UserDefaults.standard.set(Preset.custom.rawValue, forKey: presetKey)
    }
}

extension Appearance.AccentChoice {
    /// Couleur effective : la couleur choisie, ou celle de la pochette (ou l'accent système à défaut).
    static func resolve(_ raw: String, artwork: Color = .accentColor) -> Color {
        Self(rawValue: raw)?.color ?? artwork
    }
}
