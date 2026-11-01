import AppKit
import SwiftUI

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
}

enum MusicPlayer: String, CaseIterable {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"

    var name: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Musique"
        }
    }

    var notificationName: String {
        switch self {
        case .spotify: "com.spotify.client.PlaybackStateChanged"
        case .music: "com.apple.Music.playerInfo"
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty
    }
}

/// Lecture en cours via AppleScript (Spotify / Musique) + notifications distribuées
/// pour réagir instantanément aux changements de piste.
@MainActor
final class MusicManager: ObservableObject {
    static let shared = MusicManager()

    @Published private(set) var player: MusicPlayer?
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accentColor: Color = .white

    private var position: Double = 0
    private var positionDate = Date()
    private var artworkKey: String?
    private var timer: Timer?
    private let scriptQueue = DispatchQueue(label: "pastille.applescript")

    private struct Snapshot {
        var player: MusicPlayer
        var state: String
        var track: Track?
        var position: Double
        var artworkURL: String?
    }

    func start() {
        for player in MusicPlayer.allCases {
            DistributedNotificationCenter.default().addObserver(
                forName: .init(player.notificationName), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        // Les lecteurs préviennent eux-mêmes des changements (notifications ci-dessus) ; on ne les
        // interroge en plus que pendant la lecture, pour recaler la position. Sinon, rien ne tourne.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                self.refresh()
            }
        }
        timer?.tolerance = 1
        // Lecteur quitté : il ne prévient pas toujours.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let id = app?.bundleIdentifier, MusicPlayer(rawValue: id) != nil else { return }
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    /// Position extrapolée à `date` (évite d'interroger le lecteur à chaque frame).
    func elapsed(at date: Date = Date()) -> Double {
        guard let track else { return 0 }
        let value = isPlaying ? position + date.timeIntervalSince(positionDate) : position
        return min(max(value, 0), track.duration)
    }

    // MARK: - Commandes

    func playPause() { send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }

    func seek(to seconds: Double) {
        position = seconds
        positionDate = Date()
        send("set player position to \(seconds)")
    }

    private func send(_ command: String) {
        guard let player else { return }
        let source = "tell application id \"\(player.rawValue)\" to \(command)"
        scriptQueue.async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                MainActor.assumeIsolated { self.refresh() }
            }
        }
    }

    // MARK: - Lecture de l'état

    func refresh() {
        let running = MusicPlayer.allCases.filter(\.isRunning)
        guard !running.isEmpty else {
            apply(nil)
            return
        }
        let preferred = player
        scriptQueue.async {
            let snapshots = running.compactMap(Self.query)
            let best = snapshots.first { $0.state == "playing" }
                ?? snapshots.first { $0.player == preferred && $0.track != nil }
                ?? snapshots.first { $0.track != nil }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.apply(best) }
            }
        }
    }

    private func apply(_ snapshot: Snapshot?) {
        guard let snapshot, let newTrack = snapshot.track else {
            if track != nil { track = nil }
            if isPlaying { isPlaying = false }
            artwork = nil
            artworkKey = nil
            return
        }
        player = snapshot.player
        if track != newTrack { track = newTrack }
        let playing = snapshot.state == "playing"
        if isPlaying != playing { isPlaying = playing }
        position = snapshot.position
        positionDate = Date()

        let key = "\(snapshot.player.rawValue)|\(newTrack.title)|\(newTrack.artist)|\(newTrack.album)"
        if key != artworkKey {
            artworkKey = key
            loadArtwork(for: snapshot, key: key)
        }
    }

    private func loadArtwork(for snapshot: Snapshot, key: String) {
        switch snapshot.player {
        case .spotify:
            guard let string = snapshot.artworkURL, let url = URL(string: string) else { return setArtwork(nil, key: key) }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                let image = data.flatMap(NSImage.init(data:))
                DispatchQueue.main.async { MainActor.assumeIsolated { self.setArtwork(image, key: key) } }
            }.resume()
        case .music:
            scriptQueue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track")?
                    .executeAndReturnError(&error)
                // Les titres Apple Music en streaming n'ont pas de pochette côté AppleScript.
                let image = result.flatMap { NSImage(data: $0.data) }
                    ?? Self.nowPlayingArtwork(title: snapshot.track?.title)
                DispatchQueue.main.async { MainActor.assumeIsolated { self.setArtwork(image, key: key) } }
            }
        }
    }

    /// Pochette via « À l'écoute » de macOS. Seuls les programmes d'Apple y ont accès :
    /// on passe par /usr/bin/perl, qui charge notre petite bibliothèque (Resources/NowPlaying.dylib).
    /// La pochette peut manquer pendant un changement de piste : on réessaie quelques fois.
    nonisolated private static func nowPlayingArtwork(title: String?) -> NSImage? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        for attempt in 0..<3 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.8) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [
                resources.appending(path: "now-playing.pl").path,
                resources.appending(path: "NowPlaying.dylib").path,
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { continue }
            // On ignore la réponse si elle concerne déjà une autre piste.
            if let title, info["title"] != title { continue }
            if let base64 = info["artwork"], let bytes = Data(base64Encoded: base64), let image = NSImage(data: bytes) {
                return image
            }
        }
        return nil
    }

    private func setArtwork(_ image: NSImage?, key: String) {
        guard key == artworkKey else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            artwork = image
            accentColor = image?.averageColor.map(Color.init(nsColor:)) ?? .white
        }
    }

    nonisolated private static func query(_ player: MusicPlayer) -> Snapshot? {
        let source: String
        switch player {
        case .spotify:
            source = """
            tell application id "com.spotify.client"
                set s to player state as string
                if s is "stopped" then return {s}
                set t to current track
                return {s, name of t, artist of t, album of t, (duration of t) / 1000, player position, artwork url of t}
            end tell
            """
        case .music:
            source = """
            tell application id "com.apple.Music"
                set s to player state as string
                if s is "stopped" then return {s}
                set t to current track
                return {s, name of t, artist of t, album of t, duration of t, player position, ""}
            end tell
            """
        }
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error),
              result.numberOfItems >= 1 else { return nil }
        let state = result.atIndex(1)?.stringValue ?? "stopped"
        guard result.numberOfItems >= 7 else {
            return Snapshot(player: player, state: state, track: nil, position: 0, artworkURL: nil)
        }
        let track = Track(
            title: result.atIndex(2)?.stringValue ?? "",
            artist: result.atIndex(3)?.stringValue ?? "",
            album: result.atIndex(4)?.stringValue ?? "",
            duration: result.atIndex(5)?.doubleValue ?? 0
        )
        return Snapshot(
            player: player,
            state: state,
            track: track,
            position: result.atIndex(6)?.doubleValue ?? 0,
            artworkURL: result.atIndex(7)?.stringValue
        )
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
