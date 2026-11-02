import AppKit
import CoreImage
import Combine
import SwiftUI

/// Interroge Musique et Spotify directement. Ils préviennent eux-mêmes à chaque lecture, pause ou
/// changement de morceau (notifications), donc rien ne tourne en continu.
@MainActor
final class LegacyPlayers {
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
    private var spotifyArtwork = BoundedCache<String, NSImage>(capacity: 30)
    /// NSAppleScript ne supporte pas deux scripts en même temps sur des fils différents :
    /// tous ceux de Pastille passent par cette file, l'un après l'autre.
    nonisolated static let appleScriptQueue = DispatchQueue(label: "pastille.applescript")
    private var queue: DispatchQueue { Self.appleScriptQueue }

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
                } else if let link = URL(string: url), link.scheme == "https",
                          let data = try? Data(contentsOf: link), let image = NSImage(data: data) {
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
