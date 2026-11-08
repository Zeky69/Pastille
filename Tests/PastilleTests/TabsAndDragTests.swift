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
