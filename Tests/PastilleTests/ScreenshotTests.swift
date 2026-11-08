import AppKit
import Foundation
import Testing
@testable import Pastille

/// Captures d'écran : détection, proportions, copie, et aperçu animé dans l'encoche.
@MainActor
@Suite struct ScreenshotTests {
    init() { registerAppDefaults() }
    let folder = TemporaryFolder()

    @Test func findsOnlyRealScreenCaptures() {
        folder.png("Capture.png", width: 40, height: 25, screenCapture: true)
        folder.png("Photo.png", width: 40, height: 25)              // image ordinaire
        folder.file("Notes.txt")                                      // pas une image
        let found = ScreenshotManager.captures(in: folder.url, since: .distantPast,
                                               extensions: ScreenshotManager.imageExtensions)
        #expect(found.map(\.url.lastPathComponent) == ["Capture.png"])
    }

    @Test func ignoresCapturesTakenBeforeTracking() {
        folder.png("Ancienne.png", width: 10, height: 10, screenCapture: true)
        let found = ScreenshotManager.captures(in: folder.url, since: Date().addingTimeInterval(60),
                                               extensions: ScreenshotManager.imageExtensions)
        #expect(found.isEmpty)
    }

    @Test func missingFolderGivesNothing() {
        let found = ScreenshotManager.captures(in: folder.url.appendingPathComponent("absent"), since: .distantPast,
                                               extensions: ScreenshotManager.imageExtensions)
        #expect(found.isEmpty)
    }

    @Test func readsTheImageProportions() {
        let wide = folder.png("Large.png", width: 1600, height: 1000)
        let tall = folder.png("Haute.png", width: 500, height: 1000)
        #expect(abs(ScreenshotManager.aspectRatio(of: wide) - 0.625) < 0.001)
        #expect(abs(ScreenshotManager.aspectRatio(of: tall) - 2) < 0.001)
        // Illisible : proportions d'un écran.
        #expect(abs(ScreenshotManager.aspectRatio(of: folder.file("x.png")) - 0.625) < 0.001)
    }

    @Test func copyPutsTheImageAndTheFileOnThePasteboard() {
        let file = folder.png("Capture.png", width: 30, height: 20, screenCapture: true)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PastilleTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        ScreenshotManager.shared.copy(Screenshot(url: file, date: Date()), to: pasteboard)
        let types = pasteboard.types ?? []
        #expect(types.contains(.png))
        #expect(types.contains(.fileURL))
        #expect(types.contains(.tiff))
        #expect(pasteboard.data(forType: .png) == (try? Data(contentsOf: file)))
        // Le TIFF n'est produit qu'à la demande, et il est bien lisible.
        #expect(NSImage(data: pasteboard.data(forType: .tiff) ?? Data()) != nil)
    }

    // MARK: - Aperçu dans l'encoche

    private let shot = Screenshot(url: URL(fileURLWithPath: "/tmp/Capture.png"), date: Date(timeIntervalSince1970: 0))

    @Test func previewDropsAfterTheWidening() async throws {
        let model = PillViewModel()
        model.enqueue(.screenshot(shot, 0.625))
        #expect(!model.screenshotDropped)
        try await Task.sleep(for: .milliseconds(800))
        #expect(model.screenshotDropped)
        #expect(model.extraHeight > 0)
    }

    @Test func previewStaysProportionate() {
        let model = PillViewModel()
        for ratio in [0.2, 0.4, 0.625, 1, 2, 5] as [CGFloat] {
            model.enqueue(.screenshot(shot, ratio))
            model.dropScreenshot()
            let size = model.screenshotPreviewSize
            #expect(size.height <= PillViewModel.screenshotMaxHeight + 0.01)
            #expect(size.width <= PillViewModel.screenshotMaxWidth + 0.01)
            #expect(size.width + 24 <= model.compactSize.width + 0.01)
            #expect(model.compactSize.width > model.cutoutSize.width)
            #expect(model.compactSize.height <= model.canvasSize.height)
        }
    }

    @Test func secondScreenshotReplacesTheFirst() {
        let model = PillViewModel()
        let other = Screenshot(url: URL(fileURLWithPath: "/tmp/Autre.png"), date: Date(timeIntervalSince1970: 1))
        model.enqueue(.screenshot(shot, 0.625))
        model.enqueue(.screenshot(other, 0.5))
        #expect(model.moment == .screenshot(other, 0.5))
        #expect(model.queuedMoments.isEmpty)
    }

    @Test func otherMomentsWaitForThePreview() {
        let model = PillViewModel()
        model.enqueue(.screenshot(shot, 0.625))
        model.enqueue(.charging)
        #expect(model.liveActivity == .screenshot)
        #expect(model.queuedMoments == [.charging])
    }

    @Test func windowGrowsOnlyDuringThePreview() {
        let model = PillViewModel()
        let normal = model.canvasSize
        model.enqueue(.screenshot(shot, 0.625))
        #expect(model.canvasSize.height >= normal.height)
        #expect(model.canvasSize.height >= model.cutoutSize.height + PillViewModel.screenshotMaxHeight)
        model.state = .expanded   // l'aperçu s'en va
        #expect(model.canvasSize == model.expandedSize)
    }
}
