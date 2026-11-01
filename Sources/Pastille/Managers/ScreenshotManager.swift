import AppKit
import QuickLookThumbnailing

struct Screenshot: Identifiable, Equatable {
    let url: URL
    let date: Date
    var id: URL { url }
}

/// Surveille le dossier des captures d'écran et liste celles prises depuis le premier lancement.
/// Retirer une capture la masque seulement : le fichier reste sur le disque.
@MainActor
final class ScreenshotManager: ObservableObject {
    static let shared = ScreenshotManager()

    @Published private(set) var screenshots: [Screenshot] = []
    @Published private(set) var thumbnails: [URL: NSImage] = [:]

    private let sinceKey = "screenshotsTrackingSince"
    private let hiddenKey = "screenshotsHidden"
    private let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "pdf"]

    private let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    private var folder: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    private var sources: [DispatchSourceFileSystemObject] = []
    private var scanWork: DispatchWorkItem?

    private var trackingSince: Date {
        if let date = UserDefaults.standard.object(forKey: sinceKey) as? Date { return date }
        let now = Date()
        UserDefaults.standard.set(now, forKey: sinceKey)
        return now
    }

    private var hidden: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: hiddenKey) }
    }

    func start() {
        _ = trackingSince
        folder = Self.screenshotFolder()
        sources.forEach { $0.cancel() }
        sources = [folder, desktop].reduce(into: [URL]()) { if !$0.contains($1) { $0.append($1) } }
            .compactMap(watch)
        scan()
    }

    // MARK: - Actions

    /// Copie l'image et le fichier : on peut coller dans une conversation comme dans le Finder.
    func copy(_ shot: Screenshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if let image = NSImage(contentsOf: shot.url), let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        if shot.url.pathExtension.lowercased() == "png", let data = try? Data(contentsOf: shot.url) {
            item.setData(data, forType: .png)
        }
        item.setString(shot.url.absoluteString, forType: .fileURL)
        pasteboard.writeObjects([item])
    }

    /// Met la capture à la corbeille (récupérable depuis le Finder) et la retire de la liste.
    func delete(_ shot: Screenshot) {
        guard (try? FileManager.default.trashItem(at: shot.url, resultingItemURL: nil)) != nil else { return }
        screenshots.removeAll { $0 == shot }
        thumbnails[shot.url] = nil
    }

    /// Retire de la liste sans toucher au fichier.
    func remove(_ shot: Screenshot) {
        hidden.insert(shot.url.path)
        screenshots.removeAll { $0 == shot }
        thumbnails[shot.url] = nil
    }

    func removeAll() {
        hidden.formUnion(screenshots.map(\.url.path))
        screenshots.removeAll()
        thumbnails.removeAll()
    }

    /// Nom du dossier des captures (réglé dans macOS : ⌘⇧5 › Options), pour les réglages.
    var folderName: String {
        folder.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    func revealFolder() {
        NSWorkspace.shared.open(folder)
    }

    func reveal(_ shot: Screenshot) {
        NSWorkspace.shared.activateFileViewerSelecting([shot.url])
    }

    func open(_ shot: Screenshot) {
        NSWorkspace.shared.open(shot.url)
    }

    // MARK: - Surveillance du dossier

    /// Dossier choisi dans l'outil Capture d'écran, sinon le Bureau.
    private static func screenshotFolder() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return home.appendingPathComponent("Desktop")
    }

    private func watch(_ directory: URL) -> DispatchSourceFileSystemObject? {
        let fd = Darwin.open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleScan() }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        return src
    }

    /// macOS écrit d'abord un fichier temporaire puis le renomme : on attend que ça se stabilise.
    private func scheduleScan() {
        scanWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        scanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func scan() {
        let folder = folder
        let desktop = desktop
        let since = trackingSince
        let hidden = hidden
        let extensions = imageExtensions
        let tidy = Settings.tidyDesktopScreenshots
        DispatchQueue.global(qos: .utility).async {
            let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
            func captures(in directory: URL) -> [Screenshot] {
                let urls = (try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
                )) ?? []
                return urls.compactMap { url in
                    guard extensions.contains(url.pathExtension.lowercased()),
                          let values = try? url.resourceValues(forKeys: Set(keys)),
                          values.isRegularFile == true,
                          let date = values.creationDate, date >= since,
                          Self.isScreenCapture(url) else { return nil }
                    return Screenshot(url: url, date: date)
                }
            }

            // Une capture tombée sur le Bureau malgré le réglage est rangée dans le bon dossier.
            if tidy, desktop != folder {
                for shot in captures(in: desktop) {
                    let target = folder.appendingPathComponent(shot.url.lastPathComponent)
                    try? FileManager.default.moveItem(at: shot.url, to: target)
                }
            }

            let found = captures(in: folder)
                .filter { !hidden.contains($0.url.path) }
                .sorted { $0.date > $1.date }

            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.apply(found) }
            }
        }
    }

    private func apply(_ found: [Screenshot]) {
        guard found != screenshots else { return }
        screenshots = found
        let urls = Set(found.map(\.url))
        thumbnails = thumbnails.filter { urls.contains($0.key) }
        for shot in found where thumbnails[shot.url] == nil {
            loadThumbnail(shot.url)
        }
    }

    private func loadThumbnail(_ url: URL) {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 240, height: 160),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let image = rep?.nsImage else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.thumbnails[url] = image }
            }
        }
    }

    /// macOS marque chaque capture avec l'attribut étendu kMDItemIsScreenCapture.
    nonisolated private static func isScreenCapture(_ url: URL) -> Bool {
        let name = "com.apple.metadata:kMDItemIsScreenCapture"
        return getxattr(url.path, name, nil, 0, 0, 0) > 0
    }
}
