import Foundation

/// App qui utilise le son (vue par Core Audio) : un processus, son app, et s'il capte ou joue du son.
struct AudioClient: Equatable {
    var bundleID: String?
    /// Nom du processus (les services de macOS n'ont pas toujours d'identifiant d'app).
    var processName: String?
    var usesInput: Bool
    var usesOutput: Bool
}

/// App d'appel reconnue.
struct CallApp: Equatable {
    /// App à afficher et à ouvrir (l'app principale, pas son processus d'aide).
    var bundleID: String
    /// Navigateur (visio dans une page web) : il joue aussi du son hors appel.
    var isBrowser: Bool
}

/// Reconnaît, parmi les processus qui utilisent le son, une app d'appel.
enum CallDetector {
    /// Préfixes d'identifiants : les processus d'aide (« com.hnc.Discord.helper… ») sont reconnus aussi.
    /// Le premier élément est l'app affichée.
    static let apps: [(main: String, prefixes: [String])] = [
        ("com.apple.FaceTime", ["com.apple.FaceTime", "com.apple.avconferenced"]),
        ("com.hnc.Discord", ["com.hnc.Discord"]),
        ("net.whatsapp.WhatsApp", ["net.whatsapp.WhatsApp", "desktop.WhatsApp"]),
        ("us.zoom.xos", ["us.zoom."]),
        ("com.microsoft.teams2", ["com.microsoft.teams"]),
        ("com.tinyspeck.slackmacgap", ["com.tinyspeck.slackmacgap"]),
        ("com.skype.skype", ["com.skype."]),
        ("ru.keepcoder.Telegram", ["ru.keepcoder.Telegram", "org.telegram."]),
        ("org.whispersystems.signal-desktop", ["org.whispersystems.signal-desktop"]),
        ("Cisco-Systems.Spark", ["Cisco-Systems.Spark", "com.webex."]),
        ("com.facebook.archon", ["com.facebook.archon"]),
    ]

    static let browsers = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.mozilla.firefox", "com.apple.Safari",
        // Son des pages Safari (et des apps qui affichent du web).
        "com.apple.WebKit.GPU",
    ]

    /// Services de macOS qui portent le son des appels FaceTime et téléphone (via l'iPhone).
    static let callServices: Set<String> = ["avconferenced"]

    static func app(for client: AudioClient) -> CallApp? {
        if let name = client.processName, callServices.contains(name) {
            return CallApp(bundleID: "com.apple.FaceTime", isBrowser: false)
        }
        guard let id = client.bundleID else { return nil }
        if let match = apps.first(where: { $0.prefixes.contains { matches(id, prefix: $0) } }) {
            return CallApp(bundleID: match.main, isBrowser: false)
        }
        if let browser = browsers.first(where: { matches(id, prefix: $0) }) {
            return CallApp(bundleID: browser == "com.apple.WebKit.GPU" ? "com.apple.Safari" : browser, isBrowser: true)
        }
        return nil
    }

    /// « com.hnc.Discord » reconnaît aussi « com.hnc.Discord.helper » et « com.hnc.DiscordPTB ».
    private static func matches(_ id: String, prefix: String) -> Bool {
        id.lowercased().hasPrefix(prefix.lowercased())
    }
}

/// Suit les appels d'un relevé à l'autre.
/// - Un appel commence quand une app d'appel capte le micro depuis au moins `startDelay` secondes
///   (un bref accès au micro n'est pas un appel) ; sa durée part du moment où le micro s'est ouvert.
/// - Il continue tant que l'app capte le micro, ou joue du son (une app d'appel coupe parfois le micro
///   quand on se met en sourdine ; pas un navigateur, qui joue aussi des vidéos).
/// - Il se termine quand plus rien de tout ça n'arrive depuis `endDelay` secondes.
struct CallTracker {
    struct Call: Equatable {
        var app: CallApp
        var startedAt: Date
    }

    enum Change: Equatable {
        case started(Call)
        case ended(Call)
    }

    var startDelay: TimeInterval = 2
    var endDelay: TimeInterval = 3

    private(set) var call: Call?
    private var pending: Call?
    private var quietSince: Date?

    mutating func update(_ clients: [AudioClient], at now: Date) -> Change? {
        let candidates = clients.compactMap { client in CallDetector.app(for: client).map { (app: $0, client: client) } }

        if let current = call {
            let alive = candidates.contains { $0.app == current.app && ($0.client.usesInput || (!current.app.isBrowser && $0.client.usesOutput)) }
            if alive {
                quietSince = nil
                return nil
            }
            let since = quietSince ?? now
            quietSince = since
            guard now.timeIntervalSince(since) >= endDelay else { return nil }
            call = nil
            quietSince = nil
            return .ended(current)
        }

        guard let speaking = candidates.first(where: { $0.client.usesInput })?.app else {
            pending = nil
            return nil
        }
        guard let waiting = pending, waiting.app == speaking else {
            pending = Call(app: speaking, startedAt: now)
            return nil
        }
        guard now.timeIntervalSince(waiting.startedAt) >= startDelay else { return nil }
        call = waiting
        pending = nil
        return .started(waiting)
    }
}
