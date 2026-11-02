import AppKit
import CoreImage
import Combine
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
    /// Pochette floutée une fois pour toutes (fond du style Immersif), au lieu d'un flou recalculé à chaque image.
    @Published private(set) var blurredArtwork: NSImage?
    /// Un autre morceau commence (pas au lancement de Pastille) : bref affichage du titre.
    let trackChanged = PassthroughSubject<Track, Never>()
    private let startedAt = Date()

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
    private var artworkCache = BoundedCache<String, NSImage>(capacity: 30)

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

    // MARK: - Ouvrir l'app qui joue

    /// Navigateurs dont on sait retrouver l'onglet qui joue (d'après son titre).
    private static let chromiumBrowsers: Set<String> = [
        "com.brave.Browser", "com.google.Chrome", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
    ]

    /// Texte placé entre guillemets dans un AppleScript : le titre vient d'une page web, il ne doit
    /// jamais pouvoir sortir de sa chaîne (et exécuter autre chose).
    nonisolated static func appleScriptEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Ouvre l'app d'où vient le son ; pour un navigateur, va directement sur l'onglet qui joue.
    func openSource() {
        guard let bundleID = source?.bundleID else { return }
        let title = Self.appleScriptEscaped(String((track?.title ?? "").prefix(40)))
        let script: String?
        if Self.chromiumBrowsers.contains(bundleID), !title.isEmpty {
            script = """
            tell application id "\(bundleID)"
                repeat with w in windows
                    set i to 0
                    repeat with t in tabs of w
                        set i to i + 1
                        if title of t contains "\(title)" then
                            set active tab index of w to i
                            set index of w to 1
                            exit repeat
                        end if
                    end repeat
                end repeat
                activate
            end tell
            """
        } else if bundleID == "com.apple.Safari", !title.isEmpty {
            script = """
            tell application id "com.apple.Safari"
                repeat with w in windows
                    repeat with t in tabs of w
                        if name of t contains "\(title)" then
                            set current tab of w to t
                            set index of w to 1
                            exit repeat
                        end if
                    end repeat
                end repeat
                activate
            end tell
            """
        } else {
            script = nil
        }

        guard let script else {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
            return
        }
        LegacyPlayers.appleScriptQueue.async {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            // Refus d'automatisation ou onglet introuvable : on ouvre au moins l'app.
            if error != nil {
                DispatchQueue.main.async {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }
                }
            }
        }
    }

    // MARK: - Commandes (envoyées à l'app affichée)

    func playPause() {
        // Réponse immédiate à l'écran ; la source confirmera.
        position = elapsed()
        positionDate = Date()
        isPlaying.toggle()
        send("toggle")
    }

    func next() { skippedFromPill = Date(); send("next") }
    func previous() { skippedFromPill = Date(); send("previous") }

    /// Changement de morceau demandé depuis la pastille : on ne l'annonce pas (c'est l'utilisateur qui l'a choisi).
    private var skippedFromPill: Date?

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
                // Pendant un changement de morceau, macOS envoie des mises à jour sans image entre deux
                // avec image : on garde celle déjà reçue pour ce morceau (sinon la pochette clignote).
                nowPlayingArtwork = artworkCache[Self.key(info)]
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
        if has(nowPlaying), let bundle = nowPlaying["bundle"] as? String, bundle == players["bundle"] as? String {
            // Les deux sources parlent de la même app : « À l'écoute » est toujours la plus à jour
            // (AppleScript a souvent un temps de retard pendant un changement de morceau).
            usePlayers = false
        } else if !Appearance.bool(Appearance.musicPriorityKey) {
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
        if newTrack != track {
            let previous = track
            // Où en était le morceau précédent (position pas encore remplacée par celle du nouveau) ?
            let skipped = previous.map { Self.wasSkipped(duration: $0.duration, elapsed: elapsed()) } ?? false
            track = newTrack
            if previous != nil, Date().timeIntervalSince(startedAt) > 3 { scheduleAnnouncement(of: newTrack, skipped: skipped) }
        }

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

    /// Annonce d'un nouveau morceau : seulement quand le titre est stable depuis 0,3 s (pendant un
    /// changement, les sources font parfois des allers-retours), qu'il joue, et jamais deux fois de suite.
    private var announcementWork: DispatchWorkItem?
    private var lastAnnounced: Track?

    private func scheduleAnnouncement(of newTrack: Track, skipped: Bool) {
        announcementWork?.cancel()
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                let manager = MusicManager.shared
                guard manager.track == newTrack, manager.isPlaying, manager.lastAnnounced != newTrack else { return }
                manager.lastAnnounced = newTrack
                if let skipped = manager.skippedFromPill, Date().timeIntervalSince(skipped) < 4 { return }
                // Option « seulement quand je change de morceau » : la chanson qui s'enchaîne n'est pas annoncée.
                if Appearance.bool(Appearance.newTrackManualOnlyKey), !skipped { return }
                manager.trackChanged.send(newTrack)
            }
        }
        announcementWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Le morceau a-t-il été coupé avant sa fin (« Suivant », « Précédent »…) plutôt que joué jusqu'au bout ?
    /// 10 s de marge : fondu enchaîné de Musique et mises à jour de position un peu en retard.
    /// Durée inconnue : on considère qu'il s'est enchaîné tout seul.
    nonisolated static func wasSkipped(duration: Double, elapsed: Double) -> Bool {
        duration > 0 && duration - elapsed > 10
    }

    private func setArtwork(_ image: NSImage?) {
        guard image !== artwork else { return }
        let blurred = image?.blurredBackground()
        withAnimation(.easeInOut(duration: 0.3)) {
            artwork = image
            blurredArtwork = blurred
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
