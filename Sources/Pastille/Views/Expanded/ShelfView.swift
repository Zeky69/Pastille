import SwiftUI
import UniformTypeIdentifiers

/// Onglet Étagère : les fichiers posés sur l'encoche, du plus récent au plus ancien.
/// On y dépose des fichiers, on les en sort en les glissant, on les envoie par AirDrop.
struct ShelfView: View {
    @ObservedObject private var shelf = ShelfManager.shared
    @State private var targeted = false

    var body: some View {
        Group {
            if shelf.items.isEmpty {
                emptyZone
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(shelf.items) { item in
                                ShelfCard(item: item)
                                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .animation(.spring(duration: 0.4, bounce: 0.2), value: shelf.items)
                    actions
                }
            }
        }
        .overlay {
            // Fichier en train d'être glissé au-dessus : la page entière l'accueille.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor.opacity(0.12)))
                .opacity(targeted && !shelf.items.isEmpty ? 1 : 0)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.15), value: targeted)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            Self.loadURLs(from: providers) { urls in
                if ShelfManager.shared.add(urls) > 0, Settings.haptics {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                }
            }
            return true
        }
        .onAppear { shelf.prune() }
    }

    private var emptyZone: some View {
        VStack(spacing: 6) {
            Image(systemName: targeted ? "tray.and.arrow.down.fill" : "tray")
                .font(.title)
                .foregroundStyle(targeted ? Color.accentColor : Color(white: 0.65))
                .contentTransition(.symbolEffect(.replace))
            Text(targeted ? "Lâche pour poser ici" : "Étagère vide")
                .font(.subheadline)
                .foregroundStyle(.white)
            Text("Glisse des fichiers sur l'encoche pour les garder sous la main")
                .font(.caption)
                .foregroundStyle(Color(white: 0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(targeted ? Color.accentColor : Color.white.opacity(0.18),
                              style: StrokeStyle(lineWidth: targeted ? 2 : 1.2, dash: [6, 4]))
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(targeted ? Color.accentColor.opacity(0.12) : .clear))
        )
    }

    /// Envoyer tout par AirDrop, tout retirer.
    private var actions: some View {
        VStack(spacing: 8) {
            ShelfRoundButton(symbol: "dot.radiowaves.up.forward", help: "Tout envoyer par AirDrop") {
                shelf.airDrop(shelf.items)
            }
            ShelfRoundButton(symbol: "xmark", help: "Vider l'étagère (les fichiers restent sur le disque)") {
                withAnimation(.spring(duration: 0.35)) { shelf.removeAll() }
            }
            Text("\(shelf.items.count)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.gray)
        }
        .padding(.top, 6)
    }

    /// URL des fichiers glissés (chacun arrive à part, de façon asynchrone).
    static func loadURLs(from providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated { completion(urls) }
        }
    }
}

private struct ShelfCard: View {
    let item: ShelfItem
    @ObservedObject private var shelf = ShelfManager.shared
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: shelf.thumbnail(for: item))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 58, height: 58)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .frame(width: 84, height: 64)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(hovering ? 0.12 : 0.06)))
                .overlay(alignment: .topTrailing) {
                    Button { withAnimation(.spring(duration: 0.35)) { shelf.remove(item) } } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(.black.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    .help("Retirer de l'étagère")
                    .padding(4)
                    .opacity(hovering ? 1 : 0)
                }
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 84)
            Text(ShelfManager.detail(for: item.url))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.gray)
        }
        .contentShape(Rectangle())
        .help(item.url.path)
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .onTapGesture(count: 2) { shelf.open(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Ouvrir") { shelf.open(item) }
            Button("Afficher dans le Finder") { shelf.reveal(item) }
            Button("Envoyer par AirDrop") { shelf.airDrop([item]) }
            Divider()
            Button("Retirer de l'étagère") { shelf.remove(item) }
            Button("Vider l'étagère") { shelf.removeAll() }
        }
    }
}

private struct ShelfRoundButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(hovering ? 0.2 : 0.1)))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}
