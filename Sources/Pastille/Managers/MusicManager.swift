import AppKit
import SwiftUI

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
}

/// App qui joue le son en cours (Musique, Spotify, Brave pour YouTube, Deezer…).
struct AudioSource: Equatable {
    var name: String
    var bundleID: String?

    var icon: NSImage? {
        guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Lecture en cours, quelle que soit l'app, à partir de deux sources :
/// - « À l'écoute » de macOS (MediaRemote), qui connaît n'importe quelle app (YouTube dans un
///   navigateur, Deezer…) mais une seule à la fois, en général la dernière qui a joué. macOS réserve
///   ces infos à ses propres programmes ; on passe par /usr/bin/perl, qui charge notre petite
///   bibliothèque (Resources/NowPlaying.dylib) et nous envoie une ligne JSON à chaque changement ;
/// - Musique et Spotify interrogés directement (AppleScript), qui préviennent eux-mêmes à chaque
///   lecture, pause ou changement de morceau.
/// La musique passe en priorité : une vidéo ne s'affiche que si aucune musique ne joue.
@MainActor
final class MusicManager: ObservableObject {
    static let shared = MusicManager()

    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accentColor: Color = .white
    @Published private(set) var source: AudioSource?

    /// Apps considérées comme « musique » (prioritaires sur une vidéo ou un podcast).
    private static let musicApps: Set<String> = [
        "com.apple.Music", "com.spotify.client", "com.deezer.deezer-desktop", "com.tidal.desktop",
        "com.amazon.music", "com.soundcloud.desktop", "com.qobuz.QobuzDesktop",
    ]

    private var position: Double = 0
    private var positionDate = Date()
    private var rate: Double = 1

    /// Dernier état reçu de chaque source, et celle qui est affichée.
    private var nowPlaying: [String: Any] = [:]
    private var nowPlayingArtwork: NSImage?
    private var players: [String: Any] = [:]
    private var showsPlayers = false
    /// Pochettes déjà vues (« titre|artiste »), pour retrouver celle d'un morceau Apple Music
    /// quand macOS est passé à une autre source et qu'AppleScript ne la donne pas.
    private var artworkCache: [String: NSImage] = [:]

    private var stream: Process?
    private var buffer = Data()
    private var streamFailures: [Date] = []
    private var streamBroken = false
    private let legacy = LegacyPlayers()
    private var playersPoll: Timer?

    func start() {
        // Réglages de priorité ou de sources modifiés : on refait le choix tout de suite.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MusicManager.shared.decide() }
        }
        legacy.start { info in MusicManager.shared.receivePlayers(info) }
        // Pendant qu'un morceau Musique/Spotify est affiché et joue, on recale sa position de temps en temps.
        playersPoll = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated {
                let manager = MusicManager.shared
                if manager.showsPlayers, manager.isPlaying { manager.legacy.refresh() }
            }
        }
        playersPoll?.tolerance = 1
        startStream()
    }

    /// Position extrapolée à `date` (évite d'interroger le lecteur à chaque frame).
    func elapsed(at date: Date = Date()) -> Double {
        guard let track else { return 0 }
        let value = isPlaying ? position + date.timeIntervalSince(positionDate) * rate : position
        return min(max(value, 0), track.duration > 0 ? track.duration : value)
    }

    // MARK: - Commandes (envoyées à l'app affichée)

    func playPause() {
        // Réponse immédiate à l'écran ; la source confirmera.
        position = elapsed()
        positionDate = Date()
        isPlaying.toggle()
        send("toggle")
    }

    func next() { send("next") }
    func previous() { send("previous") }

    func seek(to seconds: Double) {
        position = seconds
        positionDate = Date()
        send("seek:\(seconds)")
    }

    private func send(_ command: String) {
        if showsPlayers {
            legacy.send(command)
            return
        }
        guard let resources = Bundle.main.resourceURL else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            resources.appending(path: "now-playing.pl").path,
            resources.appending(path: "NowPlaying.dylib").path,
            "command", command,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // MARK: - Flux « À l'écoute »

    private func startStream() {
        guard let resources = Bundle.main.resourceURL else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            resources.appending(path: "now-playing.pl").path,
            resources.appending(path: "NowPlaying.dylib").path,
            "stream",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { MusicManager.shared.receive(data) } }
        }
        process.terminationHandler = { _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { MainActor.assumeIsolated { MusicManager.shared.streamEnded() } }
        }
        do {
            try process.run()
            stream = process
        } catch {
            streamEnded()
        }
    }

    /// Le flux s'est arrêté : on le relance, sauf s'il tombe en boucle (3 fois en 30 s). Dans ce cas
    /// on continue avec Musique et Spotify seulement.
    private func streamEnded() {
        stream = nil
        streamFailures = streamFailures.filter { Date().timeIntervalSince($0) < 30 } + [Date()]
        guard streamFailures.count < 3 else {
            streamBroken = true
            nowPlaying = [:]
            return decide()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MusicManager.shared.startStream() }
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let info = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let base64 = info["artwork"] as? String, let bytes = Data(base64Encoded: base64) {
                nowPlayingArtwork = NSImage(data: bytes)
            } else if info["artworkHash"] == nil {
                nowPlayingArtwork = nil
            }
            if let image = nowPlayingArtwork { artworkCache[Self.key(info)] = image }
            nowPlaying = info
            decide()
            // Musique ou Spotify a pu changer en même temps (macOS vient de basculer) : on les relit.
            legacy.refresh()
        }
    }

    private func receivePlayers(_ info: [String: Any]) {
        players = info
        decide()
    }

    // MARK: - Choix de la source affichée

    /// 1. une app de musique joue → la musique ; 2. sinon, ce qui joue (vidéo…) ;
    /// 3. rien ne joue → la musique en pause plutôt que la vidéo en pause.
    private func decide() {
        func has(_ info: [String: Any]) -> Bool { !((info["title"] as? String) ?? "").isEmpty }
        func playing(_ info: [String: Any]) -> Bool { (info["playing"] as? NSNumber)?.boolValue ?? false }
        let nowPlayingIsMusic = (nowPlaying["bundle"] as? String).map(Self.musicApps.contains) ?? false
        // Réglage « son des autres apps » coupé : une vidéo ou un navigateur est ignoré.
        let nowPlaying = nowPlayingIsMusic || Appearance.bool(Appearance.musicOtherAppsKey) ? self.nowPlaying : [:]

        let usePlayers: Bool
        if !Appearance.bool(Appearance.musicPriorityKey) {
            // Sans priorité : ce que macOS montre, sauf s'il est en pause alors que Musique/Spotify joue.
            usePlayers = !has(nowPlaying) || (!playing(nowPlaying) && playing(players))
        } else if has(nowPlaying), nowPlayingIsMusic, playing(nowPlaying) || !playing(players) {
            usePlayers = false
        } else if has(players), playing(players) {
            usePlayers = true
        } else if has(nowPlaying), playing(nowPlaying) {
            usePlayers = false
        } else {
            usePlayers = has(players) && !nowPlayingIsMusic
        }
        showsPlayers = usePlayers

        let info = usePlayers ? players : nowPlaying
        let image = usePlayers
            ? (players["image"] as? NSImage) ?? artworkCache[Self.key(players)]
            : nowPlayingArtwork
        present(info, artwork: image)
    }

    private static func key(_ info: [String: Any]) -> String {
        "\(info["title"] as? String ?? "")|\(info["artist"] as? String ?? "")"
    }

    /// Affiche un état : titre, position, lecture, app, pochette.
    private func present(_ info: [String: Any], artwork image: NSImage?) {
        guard let title = info["title"] as? String, !title.isEmpty else {
            if track != nil { track = nil }
            if isPlaying { isPlaying = false }
            if source != nil { source = nil }
            setArtwork(nil)
            return
        }
        let newTrack = Track(
            title: title,
            artist: info["artist"] as? String ?? "",
            album: info["album"] as? String ?? "",
            duration: (info["duration"] as? NSNumber)?.doubleValue ?? 0
        )
        if newTrack != track { track = newTrack }

        rate = (info["rate"] as? NSNumber)?.doubleValue ?? 1
        let playing = (info["playing"] as? NSNumber)?.boolValue ?? (rate > 0)
        if isPlaying != playing { isPlaying = playing }
        if rate <= 0 { rate = 1 }

        // Position donnée à un instant précis : on la ramène à maintenant.
        if let elapsed = (info["elapsed"] as? NSNumber)?.doubleValue {
            let stamp = (info["timestamp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? Date()
            position = playing ? elapsed + Date().timeIntervalSince(stamp) * rate : elapsed
            positionDate = Date()
        }

        let newSource = (info["app"] as? String).map { AudioSource(name: $0, bundleID: info["bundle"] as? String) }
        if newSource != source { source = newSource }
        setArtwork(image)
    }

    private func setArtwork(_ image: NSImage?) {
        guard image !== artwork else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            artwork = image
            accentColor = image?.averageColor.map(Color.init(nsColor:)) ?? .white
        }
    }

    /// Vérification : le lecteur « À l'écoute » (perl + bibliothèque) répond-il en JSON ?
    nonisolated static func nowPlayingReaderWorks() -> Bool {
        guard let resources = Bundle.main.resourceURL else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            resources.appending(path: "now-playing.pl").path,
            resources.appending(path: "NowPlaying.dylib").path,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 && (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}

// MARK: - Musique et Spotify (AppleScript)

/// Interroge Musique et Spotify directement. Ils préviennent eux-mêmes à chaque lecture, pause ou
/// changement de morceau (notifications), donc rien ne tourne en continu.
@MainActor
private final class LegacyPlayers {
    private enum Player: String, CaseIterable {
        case spotify = "com.spotify.client"
        case music = "com.apple.Music"

        var name: String { self == .spotify ? "Spotify" : "Musique" }
        var notification: String {
            self == .spotify ? "com.spotify.client.PlaybackStateChanged" : "com.apple.Music.playerInfo"
        }
        var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty }
    }

    private var current: Player?
    private var onChange: (([String: Any]) -> Void)?
    /// Pochettes Spotify déjà téléchargées, par adresse.
    private var spotifyArtwork: [String: NSImage] = [:]
    private let queue = DispatchQueue(label: "pastille.applescript")

    func start(onChange: @escaping ([String: Any]) -> Void) {
        self.onChange = onChange
        for player in Player.allCases {
            DistributedNotificationCenter.default().addObserver(forName: .init(player.notification), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.refresh() }
            }
        }
        // App quittée : elle ne prévient pas toujours.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let id = app?.bundleIdentifier, Player(rawValue: id) != nil else { return }
            MainActor.assumeIsolated { self.refresh() }
        }
        refresh()
    }

    func send(_ command: String) {
        guard let current else { return }
        let script: String
        switch command {
        case "toggle": script = "playpause"
        case "next": script = "next track"
        case "previous": script = "previous track"
        default:
            guard command.hasPrefix("seek:") else { return }
            script = "set player position to \(command.dropFirst(5))"
        }
        let source = "tell application id \"\(current.rawValue)\" to \(script)"
        queue.async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MainActor.assumeIsolated { self.refresh() } }
        }
    }

    func refresh() {
        let running = Player.allCases.filter(\.isRunning)
        let preferred = current
        let cache = spotifyArtwork
        queue.async {
            let results = running.compactMap { player in Self.query(player).map { (player, $0) } }
            let best = results.first { $0.1["playing"] as? Bool == true }
                ?? results.first { $0.0 == preferred }
                ?? results.first
            var info = best?.1 ?? [:]
            // Pochette Spotify : téléchargée une fois par adresse.
            if let url = info["artworkURL"] as? String {
                if let image = cache[url] {
                    info["image"] = image
                } else if let link = URL(string: url), let data = try? Data(contentsOf: link), let image = NSImage(data: data) {
                    info["image"] = image
                    info["newArtworkURL"] = url
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.current = best?.0
                    if let url = info["newArtworkURL"] as? String { self.spotifyArtwork[url] = info["image"] as? NSImage }
                    self.onChange?(info)
                }
            }
        }
    }

    nonisolated private static func query(_ player: Player) -> [String: Any]? {
        let artwork = player == .spotify ? "artwork url of t" : "\"\""
        let duration = player == .spotify ? "(duration of t) / 1000" : "duration of t"
        let source = """
        tell application id "\(player.rawValue)"
            set s to player state as string
            if s is "stopped" then return {s}
            set t to current track
            return {s, name of t, artist of t, album of t, \(duration), player position, \(artwork)}
        end tell
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error),
              result.numberOfItems >= 7 else { return nil }
        var info: [String: Any] = [
            "title": result.atIndex(2)?.stringValue ?? "",
            "artist": result.atIndex(3)?.stringValue ?? "",
            "album": result.atIndex(4)?.stringValue ?? "",
            "duration": result.atIndex(5)?.doubleValue ?? 0,
            "elapsed": result.atIndex(6)?.doubleValue ?? 0,
            "playing": result.atIndex(1)?.stringValue == "playing",
            "app": player.name,
            "bundle": player.rawValue,
        ]
        if let url = result.atIndex(7)?.stringValue, !url.isEmpty { info["artworkURL"] = url }
        return info
    }
}

extension NSImage {
    /// Couleur moyenne (sert d'accent pour le visualiseur et la barre de progression).
    var averageColor: NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let color = NSColor(
            red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255, alpha: 1
        )
        // On éclaircit les couleurs trop sombres pour qu'elles restent visibles sur fond noir.
        return color.brightnessComponent < 0.5
            ? NSColor(hue: color.hueComponent, saturation: color.saturationComponent, brightness: 0.75, alpha: 1)
            : color
    }
}
