import AppKit
import SwiftUI

/// Fenêtre « Une mise à jour est disponible » : version, notes de version, bouton Installer.
@MainActor
final class UpdateWindowController: NSObject, NSWindowDelegate {
    static let shared = UpdateWindowController()
    private var window: NSWindow?

    func show(_ release: AppRelease) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Mise à jour de Pastille"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }
        window?.contentView = NSHostingView(rootView: UpdateView(release: release) { [weak self] in self?.window?.close() })
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private struct UpdateView: View {
    let release: AppRelease
    let close: () -> Void
    @ObservedObject private var updates = UpdateManager.shared

    private var installing: Bool {
        if case .installing = updates.state { true } else { false }
    }
    private var failure: String? {
        if case let .failed(message) = updates.state { message } else { nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pastille \(release.version) est disponible")
                        .font(.title2.weight(.semibold))
                    Text("Vous avez la version \(UpdateManager.currentVersion).")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, 16)

            ScrollView {
                ReleaseNotesView(blocks: ReleaseNotes.blocks(from: release.notes))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 24)

            HStack(spacing: 10) {
                if let failure {
                    Text(failure)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if installing {
                    ProgressView().controlSize(.small)
                    Text("Installation… Pastille va redémarrer.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if failure != nil {
                    Button("Voir sur GitHub") { NSWorkspace.shared.open(release.page) }
                } else {
                    Button("Plus tard", action: close)
                        .keyboardShortcut(.cancelAction)
                        .disabled(installing)
                    Button("Installer la mise à jour") { updates.install() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(installing)
                }
            }
            .padding(24)
        }
        .frame(width: 520, height: 460)
    }
}

/// Notes de version découpées en titres, paragraphes et puces, pour un affichage natif.
enum ReleaseNotes {
    enum Block: Equatable {
        case heading(String)
        case paragraph(String)
        case bullet(String)
        case numbered(Int, String)
        case code(String)
    }

    /// Sections qui expliquent comment installer à la main : inutiles quand on installe d'un clic.
    private static let installSections = ["mise à jour", "nouvelle installation", "installation"]

    static func blocks(from markdown: String) -> [Block] {
        var blocks: [Block] = []
        var inCode = false
        var code: [String] = []
        var skipping = false
        for raw in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if inCode, !skipping { blocks.append(.code(code.joined(separator: "\n"))) }
                inCode.toggle()
                code = []
                continue
            }
            if inCode { code.append(line); continue }
            if line.hasPrefix("#") {
                let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                skipping = installSections.contains(title.lowercased())
                if !skipping, !title.isEmpty { blocks.append(.heading(title)) }
                continue
            }
            guard !skipping, !line.isEmpty else { continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if let dot = line.firstIndex(of: "."), let number = Int(line[..<dot]),
                      line[line.index(after: dot)...].hasPrefix(" ") {
                blocks.append(.numbered(number, line[line.index(after: dot)...].trimmingCharacters(in: .whitespaces)))
            } else if case let .paragraph(previous)? = blocks.last {
                blocks[blocks.count - 1] = .paragraph(previous + " " + line)  // même paragraphe sur plusieurs lignes
            } else {
                blocks.append(.paragraph(line))
            }
        }
        return blocks
    }
}

private struct ReleaseNotesView: View {
    let blocks: [ReleaseNotes.Block]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if blocks.isEmpty {
                Text("Pas de notes pour cette version.").foregroundStyle(.secondary)
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case let .heading(title):
                    Text(title)
                        .font(.headline)
                        .padding(.top, index == 0 ? 0 : 8)
                case let .paragraph(text):
                    inline(text)
                case let .bullet(text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        inline(text)
                    }
                case let .numbered(number, text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(number).").foregroundStyle(.secondary).monospacedDigit()
                        inline(text)
                    }
                case let .code(text):
                    Text(text)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// Gras, italique, `code` et liens du Markdown.
    private func inline(_ text: String) -> some View {
        let attributed = (try? AttributedString(markdown: text)) ?? AttributedString(text)
        return Text(attributed).fixedSize(horizontal: false, vertical: true)
    }
}
