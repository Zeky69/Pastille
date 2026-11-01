import Foundation

/// Clés de préférences partagées (lues via @AppStorage dans les vues).
enum Settings {
    static let openOnHoverKey = "openOnHover"
    static let hoverDelayKey = "hoverDelay"
    static let hapticsKey = "haptics"
    static let showBatteryPercentKey = "showBatteryPercent"
    static let musicLiveActivityKey = "musicLiveActivity"
    static let showMenuBarIconKey = "showMenuBarIcon"
    static let hideInFullscreenKey = "hideInFullscreen"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            openOnHoverKey: true,
            hoverDelayKey: 0.15,
            hapticsKey: true,
            showBatteryPercentKey: true,
            musicLiveActivityKey: true,
            showMenuBarIconKey: true,
            hideInFullscreenKey: true,
        ])
    }

    static var openOnHover: Bool { UserDefaults.standard.bool(forKey: openOnHoverKey) }
    static var hoverDelay: Double { UserDefaults.standard.double(forKey: hoverDelayKey) }
    static var haptics: Bool { UserDefaults.standard.bool(forKey: hapticsKey) }
    static var musicLiveActivity: Bool { UserDefaults.standard.bool(forKey: musicLiveActivityKey) }
    static var hideInFullscreen: Bool { UserDefaults.standard.bool(forKey: hideInFullscreenKey) }
    static var showMenuBarIcon: Bool { UserDefaults.standard.bool(forKey: showMenuBarIconKey) }
}
