import AppKit
import Foundation
import Testing
@testable import Pastille

/// Onglets de la pastille ouverte et glisser de fichiers sur l'encoche.
@MainActor
@Suite(.serialized) struct TabsAndDragTests {
    init() { registerAppDefaults() }

    @Test func tabsFollowTheSettings() {
        #expect(PillViewModel.tabs(screenshots: true, shelf: true) == [.home, .screenshots, .shelf])
        #expect(PillViewModel.tabs(screenshots: false, shelf: true) == [.home, .shelf])
        #expect(PillViewModel.tabs(screenshots: true, shelf: false) == [.home, .screenshots])
        #expect(PillViewModel.tabs(screenshots: false, shelf: false) == [.home])
    }

    @Test func everyTabHasAnIcon() {
        for tab in PillTab.allCases {
            #expect(NSImage(systemSymbolName: tab.icon, accessibilityDescription: nil) != nil)
        }
    }

    @Test func shelfIsOnByDefault() {
        #expect(Appearance.bool(Appearance.showShelfTabKey))
        #expect(PillViewModel().availableTabs.contains(.shelf))
    }

    @Test func swipingWalksThroughTheThreePages() {
        let model = PillViewModel()
        model.state = .expanded
        #expect(model.moveTab(by: 1))
        #expect(model.tab == .screenshots)
        #expect(model.moveTab(by: 1))
        #expect(model.tab == .shelf)
        #expect(!model.moveTab(by: 1))       // au bout
        #expect(model.moveTab(by: -2))
        #expect(model.tab == .home)
    }

    @Test func draggingFilesOpensTheShelf() {
        let model = PillViewModel()
        model.showShelf()
        #expect(model.tab == .shelf)
    }

    @Test func recognizesFileDrags() {
        #expect(PillWindowController.carriesFiles([.fileURL]))
        #expect(PillWindowController.carriesFiles([.string, .fileURL]))
        #expect(PillWindowController.carriesFiles([NSPasteboard.PasteboardType("NSFilenamesPboardType")]))
        // Texte ou lien glissé depuis une page web : l'étagère ne s'ouvre pas.
        #expect(!PillWindowController.carriesFiles([.string, .URL]))
        #expect(!PillWindowController.carriesFiles([]))
    }

    @Test func everyPresetKeepsTheShelf() {
        for preset in Appearance.Preset.allCases where preset != .custom {
            #expect(preset.values[Appearance.showShelfTabKey] as? Bool == true)
        }
    }
}

/// Zone où un fichier glissé ouvre l'étagère.
@Suite struct ShelfDropZoneTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let cutout = CGSize(width: 185, height: 32)

    @Test func closedZoneIsAWideBandAroundTheNotch() {
        let zone = PillWindowController.shelfDropZone(screen: screen, cutout: cutout, open: nil)
        // Pile sur l'encoche.
        #expect(zone.contains(CGPoint(x: 756, y: 970)))
        // À côté de l'encoche, ou juste en dessous : pas besoin de viser la découpe.
        #expect(zone.contains(CGPoint(x: 756 - 200, y: 975)))
        #expect(zone.contains(CGPoint(x: 756 + 200, y: 975)))
        #expect(zone.contains(CGPoint(x: 756, y: 982 - 75)))
        // Mais pas au milieu de l'écran ni dans les coins de la barre des menus.
        #expect(!zone.contains(CGPoint(x: 756, y: 500)))
        #expect(!zone.contains(CGPoint(x: 40, y: 975)))
        #expect(!zone.contains(CGPoint(x: 1480, y: 975)))
    }

    @Test func zoneStaysCentredOnTheScreen() {
        let zone = PillWindowController.shelfDropZone(screen: screen, cutout: cutout, open: nil)
        #expect(abs(zone.midX - screen.midX) < 0.01)
        #expect(abs(zone.maxY - screen.maxY) < 0.01)
    }

    @Test func openPillIsEntirelyAZone() {
        let open = CGSize(width: 640, height: 190)
        let zone = PillWindowController.shelfDropZone(screen: screen, cutout: cutout, open: open)
        #expect(zone.width >= open.width)
        #expect(zone.height >= open.height)
        #expect(zone.contains(CGPoint(x: 756 - 310, y: 982 - 180)))
    }

    @Test func secondScreenUsesItsOwnFrame() {
        // Écran à encoche placé à droite d'un écran externe.
        let laptop = CGRect(x: 1920, y: 0, width: 1512, height: 982)
        let zone = PillWindowController.shelfDropZone(screen: laptop, cutout: cutout, open: nil)
        #expect(zone.contains(CGPoint(x: 1920 + 756, y: 970)))
        #expect(!zone.contains(CGPoint(x: 756, y: 970)))
    }
}
