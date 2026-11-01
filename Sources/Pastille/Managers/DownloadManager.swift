import Foundation

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
        startPolling()
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

    /// Coche « terminé » pendant 2,5 s, puis plus rien.
    private func finish() {
        state = .finished
        let work = DispatchWorkItem { [weak self] in self?.state = .idle }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }
}
