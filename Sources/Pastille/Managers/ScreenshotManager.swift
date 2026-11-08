import AppKit
import Combine
import ImageIO
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
    /// Capture qui vient d'être prise (et son rapport hauteur / largeur), pour l'aperçu dans l'encoche.
    let captured = PassthroughSubject<(Screenshot, CGFloat), Never>()

    private let sinceKey = "screenshotsTrackingSince"
    private let hiddenKey = "screenshotsHidden"
    nonisolated static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "pdf"]
    private var imageExtensions: Set<String> { Self.imageExtensions }

    private let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    private var folder: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    private var sources: [DispatchSourceFileSystemObject] = []
    private var scanWork: DispatchWorkItem?
    /// Captures déjà vues : seules les autres sont annoncées (rien au premier passage, au lancement).
    private var seen: Set<URL> = []
    private var hasScanned = false
    private var settingsWatch: AnyCancellable?
    /// Fournit l'image en TIFF seulement si une app la demande au collage (la conversion est lente).
    private var tiffProvider: TIFFProvider?
    private var markupDelegate: MarkupDelegate?

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
        settingsWatch = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in Settings.screenshotPreview }
            .prepend(Settings.screenshotPreview)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] preview in self?.syncSystemThumbnail(hidden: preview) }
    }

    // MARK: - Actions

    /// Copie l'image et le fichier : on peut coller dans une conversation comme dans le Finder.
    /// Le PNG est copié tel quel ; le TIFF (lourd à produire) seulement si l'app où l'on colle le demande.
    func copy(_ shot: Screenshot, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if shot.url.pathExtension.lowercased() == "png", let data = try? Data(contentsOf: shot.url) {
            item.setData(data, forType: .png)
        }
        let provider = TIFFProvider(url: shot.url)
        tiffProvider = provider
        item.setDataProvider(provider, forTypes: [.tiff])
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

    /// Ouvre l'outil Annoter d'Apple (celui de la vignette des captures et du Finder) : dessin, texte,
    /// recadrage, signature, partage. À la validation, la capture est remplacée par la version annotée.
    func markup(_ shot: Screenshot) {
        guard let service = NSSharingService(named: NSSharingService.Name("com.apple.MarkupUI.Markup")),
              service.canPerform(withItems: [shot.url]) else {
            open(shot)
            return
        }
        let delegate = MarkupDelegate(original: shot.url) { [weak self] in self?.annotated(shot) }
        markupDelegate = delegate
        service.delegate = delegate
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: [shot.url])
    }

    /// Version annotée enregistrée : nouvelle miniature, et recopiée si la copie automatique est active.
    private func annotated(_ shot: Screenshot) {
        thumbnails[shot.url] = nil
        loadThumbnail(shot.url)
        if Settings.screenshotAutoCopy { copy(shot) }
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
            func captures(in directory: URL) -> [Screenshot] {
                Self.captures(in: directory, since: since, extensions: extensions)
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
        announceNewest(in: found)
        guard found != screenshots else { return }
        screenshots = found
        let urls = Set(found.map(\.url))
        thumbnails = thumbnails.filter { urls.contains($0.key) }
        for shot in found where thumbnails[shot.url] == nil {
            loadThumbnail(shot.url)
        }
    }

    /// La plus récente des captures jamais vues, si elle date de quelques secondes : copiée et annoncée.
    private func announceNewest(in found: [Screenshot]) {
        let fresh = found.filter { !seen.contains($0.url) }
        seen.formUnion(found.map(\.url))
        defer { hasScanned = true }
        guard hasScanned, let shot = fresh.max(by: { $0.date < $1.date }),
              Date().timeIntervalSince(shot.date) < 30 else { return }
        if Settings.screenshotAutoCopy { copy(shot) }
        captured.send((shot, Self.aspectRatio(of: shot.url)))
    }

    /// Hauteur / largeur de l'image, lue dans son en-tête (sans la décoder).
    nonisolated static func aspectRatio(of url: URL) -> CGFloat {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? CGFloat, width > 0,
              let height = props[kCGImagePropertyPixelHeight] as? CGFloat, height > 0 else { return 10.0 / 16 }
        return height / width
    }

    // MARK: - Vignette d'Apple en bas à droite

    /// Avec l'aperçu dans l'encoche, la vignette flottante d'Apple est coupée : sinon elle ferait doublon,
    /// et macOS n'écrit le fichier qu'une fois la vignette partie (≈ 5 s de retard).
    /// L'option coupée, on remet le réglage que la personne avait avant.
    private static let captureDomain = "com.apple.screencapture" as CFString
    private static let thumbnailKey = "show-thumbnail" as CFString
    private let savedThumbnailKey = "screenshots.systemThumbnailBefore"

    private func syncSystemThumbnail(hidden: Bool) {
        let defaults = UserDefaults.standard
        let current = CFPreferencesCopyAppValue(Self.thumbnailKey, Self.captureDomain) as? Bool
        if hidden {
            if defaults.string(forKey: savedThumbnailKey) == nil {
                defaults.set(current.map { $0 ? "shown" : "hidden" } ?? "default", forKey: savedThumbnailKey)
            }
            guard current != false else { return }
            CFPreferencesSetAppValue(Self.thumbnailKey, kCFBooleanFalse, Self.captureDomain)
        } else {
            guard let saved = defaults.string(forKey: savedThumbnailKey) else { return }
            defaults.removeObject(forKey: savedThumbnailKey)
            let value: CFBoolean? = saved == "shown" ? kCFBooleanTrue : saved == "hidden" ? kCFBooleanFalse : nil
            CFPreferencesSetAppValue(Self.thumbnailKey, value, Self.captureDomain)
        }
        CFPreferencesAppSynchronize(Self.captureDomain)
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

    /// Captures d'écran d'un dossier prises depuis `since` (images marquées comme captures par macOS).
    nonisolated static func captures(in directory: URL, since: Date, extensions: Set<String>) -> [Screenshot] {
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap { url in
            guard extensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let date = values.creationDate, date >= since,
                  isScreenCapture(url) else { return nil }
            return Screenshot(url: url, date: date)
        }
    }

    /// macOS marque chaque capture avec l'attribut étendu kMDItemIsScreenCapture.
    nonisolated static func isScreenCapture(_ url: URL) -> Bool {
        let name = "com.apple.metadata:kMDItemIsScreenCapture"
        return getxattr(url.path, name, nil, 0, 0, 0) > 0
    }
}

/// Produit le TIFF d'une capture à la demande, au moment du collage.
private final class TIFFProvider: NSObject, NSPasteboardItemDataProvider {
    let url: URL
    init(url: URL) { self.url = url }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: type)
        }
    }
}

/// Reçoit l'image annotée et l'écrit à la place de la capture d'origine.
private final class MarkupDelegate: NSObject, NSSharingServiceDelegate {
    let original: URL
    let onSaved: @MainActor () -> Void

    init(original: URL, onSaved: @escaping @MainActor () -> Void) {
        self.original = original
        self.onSaved = onSaved
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        for item in items {
            if let url = item as? URL {
                guard url.standardizedFileURL != original.standardizedFileURL else { continue }
                replace(with: try? Data(contentsOf: url))
            } else if let image = item as? NSImage {
                replace(with: Self.pngData(image))
            } else if let provider = item as? NSItemProvider {
                provider.loadFileRepresentation(forTypeIdentifier: "public.image") { [weak self] url, _ in
                    let data = url.flatMap { try? Data(contentsOf: $0) }
                    DispatchQueue.main.async { self?.replace(with: data) }
                }
            }
        }
        // L'outil peut aussi avoir enregistré directement dans le fichier.
        DispatchQueue.main.async { [onSaved] in MainActor.assumeIsolated { onSaved() } }
    }

    private func replace(with data: Data?) {
        guard let data, !data.isEmpty else { return }
        // Écrit dans le fichier existant (pas de remplacement atomique) : il garde l'attribut
        // « capture d'écran » de macOS, sans lequel il sortirait de la liste.
        try? data.write(to: original)
        DispatchQueue.main.async { [onSaved] in MainActor.assumeIsolated { onSaved() } }
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
