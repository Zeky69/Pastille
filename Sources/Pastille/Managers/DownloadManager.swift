import AppKit

/// Téléchargements en cours dans ~/Téléchargements.
/// Les navigateurs publient la progression de leurs fichiers pour le Finder (NSProgress) : on s'y abonne.
/// En secours, on repère leurs fichiers temporaires (.crdownload, .download, .part).
@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    enum State: Equatable {
        case idle
        /// Progression entre 0 et 1, ou nil si le navigateur ne la donne pas.
        case downloading(Double?)
        case finished
    }

    @Published private(set) var state: State = .idle
    /// Fichier qui vient d'arriver, ouvert d'un clic sur la coche verte.
    private(set) var finishedFile: URL?
    /// Sans pourcentage (l'app ne donne pas la taille finale, ex. IPTVnator) : vitesse et quantité
    /// déjà reçue, mesurées sur les fichiers temporaires.
    struct Measure: Equatable {
        /// « 812 Mo », « 1,2 Go » : court, pour tenir sans être coupé.
        var total: String
        /// « 2,5 Mo/s », « 850 Ko/s ».
        var speed: String?
    }
    @Published private(set) var measure: Measure?
    private var sizeSamples: [(date: Date, bytes: Int64)] = []
    private var detailUpdatedAt = Date.distantPast

    private let folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
    private static let partialExtensions: Set<String> = ["crdownload", "download", "part", "partial"]

    private var progresses: [ObjectIdentifier: Progress] = [:]
    private var subscriber: Any?
    private var watcher: DispatchSourceFileSystemObject?
    private var hasPartialFiles = false
    private var poll: Timer?
    private var finishWork: DispatchWorkItem?

    func start() {
        // Les rappels peuvent arriver sur n'importe quel fil : on repasse sur le principal.
        subscriber = Progress.addSubscriber(forFileURL: folder) { progress in
            DispatchQueue.main.async { MainActor.assumeIsolated { DownloadManager.shared.track(progress) } }
            return {
                DispatchQueue.main.async { MainActor.assumeIsolated { DownloadManager.shared.untrack(progress) } }
            }
        }
        watchFolder()
        scanPartialFiles()
    }

    private func track(_ progress: Progress) {
        progresses[ObjectIdentifier(progress)] = progress
        update()
    }

    private func untrack(_ progress: Progress) {
        progresses[ObjectIdentifier(progress)] = nil
        update()
    }

    // MARK: - Fichiers temporaires des navigateurs

    private func watchFolder() {
        let fd = Darwin.open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { DownloadManager.shared.scanPartialFiles() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func scanPartialFiles() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        hasPartialFiles = names.contains { Self.partialExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
        update()
    }

    // MARK: - État

    private func update() {
        let active = progresses.values.filter { !$0.isFinished && !$0.isCancelled }
        if active.isEmpty && !hasPartialFiles {
            stopPolling()
            if case .downloading = state { finish() }
            return
        }
        finishWork?.cancel()
        let known = active.filter { $0.totalUnitCount > 0 }
        let fraction = known.isEmpty ? nil : known.map(\.fractionCompleted).reduce(0, +) / Double(known.count)
        let new = State.downloading(fraction.map { min(max($0, 0), 1) })
        if new != state { state = new }
        if fraction == nil { measurePartialFiles() } else if measure != nil { measure = nil }
        startPolling()
    }

    /// Taille cumulée des fichiers temporaires, et vitesse sur les 3 dernières secondes.
    /// Le texte n'est rafraîchi qu'une fois par seconde, pour rester lisible.
    private func measurePartialFiles() {
        let now = Date()
        let bytes = partialBytes()
        sizeSamples.append((now, bytes))
        sizeSamples.removeAll { now.timeIntervalSince($0.date) > 3 }
        guard bytes > 0, now.timeIntervalSince(detailUpdatedAt) >= 1 else { return }
        detailUpdatedAt = now

        var new = Measure(total: Self.short(Double(bytes)))
        if let first = sizeSamples.first, now.timeIntervalSince(first.date) >= 1 {
            let speed = Double(bytes - first.bytes) / now.timeIntervalSince(first.date)
            if speed > 0 { new.speed = Self.short(speed) + "/s" }
        }
        if new != measure { measure = new }
    }

    /// Taille la plus courte possible : une décimale sous 10 (« 2,5 Mo », « 1,2 Go »), sinon un entier (« 812 Mo »).
    private static func short(_ bytes: Double) -> String {
        let units = ["o", "Ko", "Mo", "Go", "To"]
        var value = bytes
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        let number = value < 10 && index >= 2
            ? String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
            : String(Int(value.rounded()))
        return "\(number) \(units[index])"
    }

    private func partialBytes() -> Int64 {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
        var total: Int64 = 0
        for name in names where Self.partialExtensions.contains((name as NSString).pathExtension.lowercased()) {
            let url = folder.appending(path: name)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            // Safari range ses téléchargements dans un paquet « .download » : on additionne son contenu.
            let files = isDirectory.boolValue
                ? ((try? manager.contentsOfDirectory(atPath: url.path)) ?? []).map { url.appending(path: $0) }
                : [url]
            for file in files {
                total += (try? manager.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
            }
        }
        return total
    }

    /// Pendant un téléchargement, la progression est relue deux fois par seconde.
    private func startPolling() {
        guard poll == nil else { return }
        poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { DownloadManager.shared.update() }
        }
        poll?.tolerance = 0.1
    }

    private func stopPolling() {
        poll?.invalidate()
        poll = nil
    }

    /// Coche « terminé » pendant 4 s (le temps de cliquer dessus), puis plus rien.
    private func finish() {
        measure = nil
        sizeSamples.removeAll()
        finishedFile = newestDownload()
        state = .finished
        scheduleIdle(after: 4)
    }

    private func scheduleIdle(after delay: TimeInterval) {
        finishWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.state = .idle }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Tant que la souris est sur la coche, elle reste affichée ; elle part 1,5 s après.
    func setFinishedHovered(_ hovered: Bool) {
        guard state == .finished else { return }
        if hovered {
            finishWork?.cancel()
        } else {
            scheduleIdle(after: 1.5)
        }
    }

    /// Clic sur la coche : ouvre le fichier (⌥ : le montre dans le Finder).
    func openFinished(reveal: Bool) {
        guard let file = finishedFile, FileManager.default.fileExists(atPath: file.path) else {
            NSWorkspace.shared.open(folder)
            return
        }
        if reveal {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            NSWorkspace.shared.open(file)
        }
        finishWork?.cancel()
        state = .idle
    }

    /// Le fichier le plus récemment arrivé dans Téléchargements (hors fichiers temporaires), s'il date de moins de 2 min.
    private func newestDownload() -> URL? {
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .creationDateKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        func date(_ url: URL) -> Date {
            let values = try? url.resourceValues(forKeys: Set(keys))
            return values?.addedToDirectoryDate ?? values?.creationDate ?? .distantPast
        }
        return items
            .filter { !Self.partialExtensions.contains($0.pathExtension.lowercased()) }
            .max { date($0) < date($1) }
            .flatMap { Date().timeIntervalSince(date($0)) < 120 ? $0 : nil }
    }
}
