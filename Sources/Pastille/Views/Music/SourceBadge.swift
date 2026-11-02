import SwiftUI

extension View {
    /// Un clic ouvre l'app d'où vient le son (l'onglet YouTube pour un navigateur).
    func opensSource() -> some View {
        modifier(OpensSource())
    }
}

struct OpensSource: ViewModifier {
    @ObservedObject private var music = MusicManager.shared

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { music.openSource() }
            .help(music.source.map { "Ouvrir dans \($0.name)" } ?? "")
    }
}

/// Icône de l'app qui joue le son (Brave pour YouTube, Spotify, Musique…), en coin de pochette.
struct SourceBadge: View {
    let size: CGFloat
    @ObservedObject private var music = MusicManager.shared
    @AppStorage(Appearance.musicSourceBadgeKey) private var enabled = true

    var body: some View {
        if enabled, music.track != nil, let source = music.source, let icon = source.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
                // Déborde un peu à droite de la pochette, mais pas en dessous (il toucherait le bord de la pastille).
                .offset(x: size * 0.25, y: -2)
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                .help(source.name)
                .transition(.scale.combined(with: .opacity))
        }
    }
}
