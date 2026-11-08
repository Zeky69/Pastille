import AppKit
import Foundation

/// Dossier temporaire propre à un test, supprimé à la fin.
final class TemporaryFolder {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("PastilleTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    /// Fichier texte quelconque.
    @discardableResult
    func file(_ name: String, contents: String = "Pastille") -> URL {
        let file = url.appendingPathComponent(name)
        try? Data(contents.utf8).write(to: file)
        return file
    }

    /// Image PNG de la taille donnée (en pixels).
    @discardableResult
    func png(_ name: String, width: Int, height: Int, screenCapture: Bool = false) -> URL {
        let file = url.appendingPathComponent(name)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        try? rep.representation(using: .png, properties: [:])?.write(to: file)
        if screenCapture { Self.markAsScreenCapture(file) }
        return file
    }

    /// Marque le fichier comme macOS marque ses captures d'écran.
    static func markAsScreenCapture(_ file: URL) {
        let value: [UInt8] = [0x62, 0x70, 0x6C, 0x69, 0x73, 0x74, 0x30, 0x30, 0x09, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                              0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                              0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x09]
        _ = value.withUnsafeBytes { setxattr(file.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, value.count, 0, 0) }
    }
}

/// Préférences jetables (rien n'est écrit dans les vraies préférences de Pastille).
final class ScratchDefaults {
    let name = "PastilleTests-\(UUID().uuidString)"
    lazy var defaults = UserDefaults(suiteName: name)!
    deinit { UserDefaults().removePersistentDomain(forName: name) }
}
