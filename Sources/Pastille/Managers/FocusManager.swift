import AppKit
import Combine
import SwiftUI

/// Mode Concentration (Ne pas déranger, Sommeil, Travail…).
struct FocusMode: Equatable {
    let id: String
    let name: String
    let symbol: String
    /// Nom de la couleur système choisie dans Réglages (« systemIndigoColor »…).
    let tint: String

    var color: Color {
        let colors: [String: NSColor] = [
            "systemRedColor": .systemRed, "systemOrangeColor": .systemOrange, "systemYellowColor": .systemYellow,
            "systemGreenColor": .systemGreen, "systemMintColor": .systemMint, "systemTealColor": .systemTeal,
            "systemCyanColor": .systemCyan, "systemBlueColor": .systemBlue, "systemIndigoColor": .systemIndigo,
            "systemPurpleColor": .systemPurple, "systemPinkColor": .systemPink, "systemBrownColor": .systemBrown,
            "systemGrayColor": .systemGray,
        ]
        return Color(nsColor: colors[tint] ?? .systemIndigo)
    }
}

/// Suit le mode Concentration actif. macOS n'a pas d'API publique pour ça : on lit les fichiers où il
/// l'enregistre (~/Library/DoNotDisturb/DB), lisibles avec l'accès complet au disque, déjà demandé
/// pour les codes reçus par SMS. Sans cet accès, rien ne s'affiche.
@MainActor
final class FocusManager: ObservableObject {
    static let shared = FocusManager()

    @Published private(set) var active: FocusMode?
    /// Mode qui s'active (true) ou se termine (false).
    let changed = PassthroughSubject<(FocusMode, Bool), Never>()

    private let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")
    private var source: DispatchSourceFileSystemObject?
    private var readWork: DispatchWorkItem?

    func start() {
        active = Self.readActive(in: folder)
        let fd = Darwin.open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        // Les fichiers sont remplacés d'un bloc : on surveille le dossier.
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scheduleRead() } }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func scheduleRead() {
        readWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.read() }
        readWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func read() {
        let new = Self.readActive(in: folder)
        guard new != active else { return }
        let old = active
        active = new
        if let new {
            changed.send((new, true))
        } else if let old {
            changed.send((old, false))
        }
    }

    // MARK: - Lecture des fichiers

    private static func readActive(in folder: URL) -> FocusMode? {
        guard let assertions = try? Data(contentsOf: folder.appendingPathComponent("Assertions.json")),
              let id = activeModeID(assertions: assertions) else { return nil }
        let configurations = try? Data(contentsOf: folder.appendingPathComponent("ModeConfigurations.json"))
        return mode(id: id, configurations: configurations)
    }

    /// Identifiant du mode activé (« com.apple.donotdisturb.mode.default »…), s'il y en a un.
    nonisolated static func activeModeID(assertions: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: assertions) as? [String: Any],
              let data = json["data"] as? [[String: Any]] else { return nil }
        for store in data {
            for record in store["storeAssertionRecords"] as? [[String: Any]] ?? [] {
                let details = record["assertionDetails"] as? [String: Any]
                if let id = details?["assertionDetailsModeIdentifier"] as? String { return id }
            }
        }
        return nil
    }

    /// Nom, symbole et couleur du mode ; les modes d'Apple sont nommés en français.
    nonisolated static func mode(id: String, configurations: Data?) -> FocusMode {
        var name: String?
        var symbol = "moon.fill"
        var tint = "systemIndigoColor"
        if let configurations,
           let json = try? JSONSerialization.jsonObject(with: configurations) as? [String: Any],
           let data = json["data"] as? [[String: Any]] {
            for store in data {
                guard let mode = (store["modeConfigurations"] as? [String: Any])?[id] as? [String: Any],
                      let details = mode["mode"] as? [String: Any] else { continue }
                name = details["name"] as? String
                if let s = details["symbolImageName"] as? String, NSImage(systemSymbolName: s, accessibilityDescription: nil) != nil {
                    symbol = s
                }
                tint = details["tintColorName"] as? String ?? tint
            }
        }
        return FocusMode(id: id, name: frenchName(id: id) ?? name ?? "Concentration", symbol: symbol, tint: tint)
    }

    nonisolated private static func frenchName(id: String) -> String? {
        let names: [(String, String)] = [
            ("com.apple.donotdisturb.mode.default", "Ne pas déranger"),
            ("sleep", "Sommeil"),
            ("com.apple.focus.work", "Travail"),
            ("com.apple.focus.personal-time", "Temps personnel"),
            ("com.apple.focus.reduce-interruptions", "Moins d'interruptions"),
            ("driving", "En voiture"),
            ("fitness", "Sport"),
            ("gaming", "Jeux"),
            ("mindfulness", "Pleine conscience"),
            ("reading", "Lecture"),
        ]
        return names.first { id == $0.0 || (!$0.0.contains(".") && id.contains($0.0)) }?.1
    }
}
