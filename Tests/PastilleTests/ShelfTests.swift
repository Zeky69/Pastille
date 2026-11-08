import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Pastille

/// Étagère : fichiers posés sur l'encoche.
@MainActor
@Suite struct ShelfTests {
    let folder = TemporaryFolder()
    let store = ScratchDefaults()

    private func makeShelf() -> ShelfManager { ShelfManager(defaults: store.defaults, key: "shelf") }

    @Test func startsEmpty() {
        #expect(makeShelf().items.isEmpty)
    }

    @Test func addsFilesNewestFirst() {
        let shelf = makeShelf()
        let a = folder.file("a.txt"), b = folder.file("b.txt")
        #expect(shelf.add([a]) == 1)
        #expect(shelf.add([b]) == 1)
        #expect(shelf.items.map(\.name) == ["b.txt", "a.txt"])
    }

    @Test func addingTwiceMovesToTheTopWithoutDuplicating() {
        let shelf = makeShelf()
        let a = folder.file("a.txt"), b = folder.file("b.txt")
        shelf.add([a, b])
        shelf.add([b])
        shelf.add([a])
        #expect(shelf.items.map(\.name) == ["a.txt", "b.txt"])
        // Le même fichier deux fois dans un seul dépôt ne compte qu'une fois.
        #expect(shelf.add([a, a]) == 1)
        #expect(shelf.items.count == 2)
    }

    @Test func ignoresMissingFilesAndWebLinks() {
        let shelf = makeShelf()
        let missing = folder.url.appendingPathComponent("absent.txt")
        #expect(shelf.add([missing, URL(string: "https://example.com")!]) == 0)
        #expect(shelf.items.isEmpty)
    }

    @Test func acceptsFolders() {
        let shelf = makeShelf()
        let sub = folder.url.appendingPathComponent("Dossier")
        try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try? Data().write(to: sub.appendingPathComponent("un.txt"))
        try? Data().write(to: sub.appendingPathComponent("deux.txt"))
        #expect(shelf.add([sub]) == 1)
        #expect(ShelfManager.detail(for: sub) == "2 éléments")
    }

    @Test func keepsItsContentAfterARelaunch() {
        let a = folder.file("a.txt"), b = folder.file("b.txt")
        makeShelf().add([a, b])
        // Nouvelle instance = Pastille relancée.
        #expect(makeShelf().items.map(\.url) == [a, b].map(\.standardizedFileURL))
    }

    @Test func forgetsFilesDeletedOrMovedMeanwhile() {
        let a = folder.file("a.txt"), b = folder.file("b.txt")
        makeShelf().add([a, b])
        try? FileManager.default.removeItem(at: a)
        let reopened = makeShelf()
        #expect(reopened.items.map(\.name) == ["b.txt"])
        // Et pendant que Pastille tourne.
        try? FileManager.default.moveItem(at: b, to: folder.url.appendingPathComponent("c.txt"))
        reopened.prune()
        #expect(reopened.items.isEmpty)
    }

    @Test func removeAndClearDoNotTouchTheFiles() {
        let shelf = makeShelf()
        let a = folder.file("a.txt"), b = folder.file("b.txt")
        shelf.add([a, b])   // un seul dépôt : l'ordre est gardé
        shelf.remove(shelf.items[0])
        #expect(shelf.items.map(\.name) == ["b.txt"])
        shelf.removeAll()
        #expect(shelf.items.isEmpty)
        #expect(makeShelf().items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: a.path))
        #expect(FileManager.default.fileExists(atPath: b.path))
    }

    @Test func dropsTheOldestBeyondCapacity() {
        let shelf = makeShelf()
        for i in 0..<(ShelfManager.capacity + 5) { shelf.add([folder.file("f\(i).txt")]) }
        #expect(shelf.items.count == ShelfManager.capacity)
        #expect(shelf.items.first?.name == "f\(ShelfManager.capacity + 4).txt")
        #expect(!shelf.items.contains { $0.name == "f0.txt" })
    }

    @Test func showsTheFileSize() {
        let file = folder.file("gros.txt", contents: String(repeating: "x", count: 2_000))
        #expect(ShelfManager.detail(for: file).contains("2"))
    }

    @Test func providesAnIconForEveryFile() {
        let shelf = makeShelf()
        shelf.add([folder.file("a.txt")])
        #expect(shelf.thumbnail(for: shelf.items[0]).size.width > 0)
    }
}

/// Ce qui arrive quand on lâche des fichiers sur la page, et son rendu.
@MainActor
@Suite struct ShelfDropTests {
    let folder = TemporaryFolder()

    @Test func droppedFilesAreDecoded() async {
        let a = folder.file("a.txt"), b = folder.file("b.pdf")
        let providers = [a, b].map { NSItemProvider(object: $0 as NSURL) } + [NSItemProvider(object: "texte" as NSString)]
        let urls: [URL] = await withCheckedContinuation { done in
            ShelfView.loadURLs(from: providers) { done.resume(returning: $0) }
        }
        #expect(Set(urls.map(\.standardizedFileURL)) == Set([a, b].map(\.standardizedFileURL)))
    }

    @Test func pageRendersEmptyAndFull() throws {
        let empty = ImageRenderer(content: ShelfView().frame(width: 600).background(.black))
        #expect(empty.nsImage != nil)
        ShelfManager.shared.add([folder.file("Rapport final.txt"), folder.png("Image.png", width: 200, height: 120)])
        defer { ShelfManager.shared.removeAll() }
        let full = ImageRenderer(content: ShelfView().frame(width: 600).background(.black).environment(\.colorScheme, .dark))
        full.scale = 2
        let image = try #require(full.nsImage)
        #expect(image.size.height > 60)
        // Pour regarder le rendu : PASTILLE_SNAPSHOTS=/un/dossier swift test
        if let dir = ProcessInfo.processInfo.environment["PASTILLE_SNAPSHOTS"],
           let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("shelf.png"))
        }
    }
}
