import SwiftUI

/// Onglet Captures : les captures d'écran récentes, de la plus récente à la plus ancienne.
struct ScreenshotsView: View {
    @ObservedObject private var manager = ScreenshotManager.shared

    var body: some View {
        if manager.screenshots.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "camera.viewfinder")
                    .font(.title)
                    .foregroundStyle(Color(white: 0.65))
                Text("Aucune capture d'écran")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Text("Elles apparaîtront ici dès que tu en prendras une")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.65))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(manager.screenshots) { shot in
                        ScreenshotCard(shot: shot, thumbnail: manager.thumbnails[shot.url])
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .padding(.vertical, 4)
            }
            .animation(.spring(duration: 0.4, bounce: 0.2), value: manager.screenshots)
        }
    }
}

private struct ScreenshotCard: View {
    let shot: Screenshot
    let thumbnail: NSImage?
    @State private var hovering = false
    @State private var copied = false

    private let manager = ScreenshotManager.shared

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.08))
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: 140, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(hovering ? 0.35 : 0.12), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                // Petites actions discrètes dans le coin, visibles au survol.
                HStack(spacing: 3) {
                    ActionButton(symbol: copied ? "checkmark" : "doc.on.doc", help: "Copier") { copy() }
                    ActionButton(symbol: "folder", help: "Afficher dans le Finder") { manager.reveal(shot) }
                    ActionButton(symbol: "xmark", help: "Mettre à la corbeille") {
                        withAnimation(.spring(duration: 0.35)) { manager.delete(shot) }
                    }
                }
                .padding(5)
                .opacity(hovering || copied ? 1 : 0)
                .scaleEffect(hovering || copied ? 1 : 0.85, anchor: .topTrailing)
            }

            Text(shot.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.gray)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { self.hovering = hovering }
        }
        .onTapGesture(count: 2) { manager.open(shot) }
        .onDrag { NSItemProvider(contentsOf: shot.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Copier") { copy() }
            Button("Ouvrir") { manager.open(shot) }
            Button("Afficher dans le Finder") { manager.reveal(shot) }
            Divider()
            Button("Mettre à la corbeille") { manager.delete(shot) }
            Button("Retirer de la liste") { manager.remove(shot) }
            Button("Tout retirer") { manager.removeAll() }
        }
    }

    private func copy() {
        manager.copy(shot)
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.2)) { copied = false }
        }
    }
}

private struct ActionButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 18, height: 18)
                .background(Circle().fill(.black.opacity(hovering ? 0.8 : 0.6)))
                .background(Circle().fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}
