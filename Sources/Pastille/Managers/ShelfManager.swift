import AppKit
import QuickLookThumbnailing

struct ShelfItem: Identifiable, Equatable, Codable {
    let url: URL
    let addedAt: Date
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// Étagère : des fichiers posés sur l'encoche, gardés sous la main pour les glisser ailleurs ou
/// les envoyer par AirDrop. Les fichiers ne sont pas copiés : l'étagère garde l'emplacement de
/// l'original, et retire d'elle-même ceux qui ont été supprimés ou déplacés.
@MainActor
final class ShelfManager: ObservableObject {
    static let shared = ShelfManager()
    /// Au-delà, les plus anciens sont retirés.
    static let capacity = 30

    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var thumbnails: [URL: NSImage] = [:]

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "shelf.items") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode([ShelfItem].self, from: data) {
            items = saved
        }
        prune()
    }

    // MARK: - Contenu

    /// Ajoute des fichiers (le plus récent en tête). Un fichier déjà présent remonte en tête au lieu
    /// d'être doublé ; ce qui n'existe pas (ou n'est pas un fichier) est ignoré. Renvoie le nombre ajouté.
    @discardableResult
    func add(_ urls: [URL], now: Date = Date()) -> Int {
        let fresh = urls
            .filter(\.isFileURL)
            .map(\.standardizedFileURL)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .reduce(into: [URL]()) { if !$0.contains($1) { $0.append($1) } }
        guard !fresh.isEmpty else { return 0 }
        items.removeAll { fresh.contains($0.url) }
        items.insert(contentsOf: fresh.map { ShelfItem(url: $0, addedAt: now) }, at: 0)
        if items.count > Self.capacity { items.removeLast(items.count - Self.capacity) }
        save()
        fresh.forEach(loadThumbnail)
        return fresh.count
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0 == item }
        thumbnails[item.url] = nil
        save()
    }

    func removeAll() {
        items.removeAll()
        thumbnails.removeAll()
        save()
    }

    /// Retire les fichiers qui n'existent plus à leur emplacement.
    func prune() {
        let kept = items.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        guard kept != items else { return }
        items = kept
        save()
    }

    /// Taille d'un fichier (« 2,4 Mo ») ou nombre d'éléments d'un dossier.
    static func detail(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isPackageKey])
        if values?.isDirectory == true, values?.isPackage != true {
            let count = (try? FileManager.default.contentsOfDirectory(atPath: url.path).filter { !$0.hasPrefix(".") }.count) ?? 0
            return count == 1 ? "1 élément" : "\(count) éléments"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)
    }

    // MARK: - Actions

    func open(_ item: ShelfItem) { NSWorkspace.shared.open(item.url) }

    func reveal(_ item: ShelfItem) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }

    /// Envoie par AirDrop (le panneau d'Apple s'ouvre pour choisir l'appareil).
    func airDrop(_ items: [ShelfItem]) {
        let urls = items.map(\.url)
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }

    // MARK: - Miniatures

    func thumbnail(for item: ShelfItem) -> NSImage {
        if let image = thumbnails[item.url] { return image }
        loadThumbnail(item.url)
        return NSWorkspace.shared.icon(forFile: item.url.path)
    }

    private var loading: Set<URL> = []

    private func loadThumbnail(_ url: URL) {
        guard thumbnails[url] == nil, !loading.contains(url) else { return }
        loading.insert(url)
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 128, height: 128),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .all
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            let image = rep?.nsImage
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.loading.remove(url)
                    if let image, self.items.contains(where: { $0.url == url }) { self.thumbnails[url] = image }
                }
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) }
    }
}
