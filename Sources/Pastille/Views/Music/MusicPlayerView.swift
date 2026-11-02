import SwiftUI

/// Lecteur, en cinq styles bien distincts. « Classique » est l'affichage d'origine.
struct MusicPlayerView: View {
    @ObservedObject private var music = MusicManager.shared
    @AppStorage(Appearance.musicStyleKey) private var styleRaw = Appearance.MusicStyle.artwork.rawValue
    @AppStorage(Appearance.accentKey) private var accentRaw = Appearance.AccentChoice.artwork.rawValue

    private var style: Appearance.MusicStyle { .init(rawValue: styleRaw) ?? .artwork }
    private var accent: Color { Appearance.AccentChoice.resolve(accentRaw, artwork: music.accentColor) }

    var body: some View {
        switch style {
        case .artwork: classic
        case .poster: poster
        case .compact: compact
        case .immersive: immersive
        case .vinyl: vinyl
        }
    }

    // MARK: Classique (d'origine)

    private var classic: some View {
        HStack(spacing: 14) {
            ArtworkView(image: music.artwork, cornerRadius: 12)
                    .opensSource()
                .frame(width: 96, height: 96)
                .overlay(alignment: .bottomTrailing) { SourceBadge(size: 22) }
                .shadow(color: accent.opacity(0.35), radius: 10)
            VStack(alignment: .leading, spacing: 6) {
                // Sans lecture : pas de texte, juste la place réservée, une barre vide et les boutons.
                HStack(alignment: .top) {
                    titles(titleSize: 14, artistSize: 12)
                    Spacer(minLength: 4)
                    visualizer
                }
                ProgressBar(duration: music.track?.duration ?? 0, accent: accent)
                controls(main: 22, side: 15, spacing: 22)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pochette

    /// La pochette occupe toute la hauteur ; titre en gros, commandes discrètes en bas.
    private var poster: some View {
        GeometryReader { geo in
            HStack(spacing: 16) {
                ArtworkView(image: music.artwork, cornerRadius: 14)
                    .opensSource()
                    .frame(width: geo.size.height, height: geo.size.height)
                    .overlay(alignment: .bottomTrailing) { SourceBadge(size: 26) }
                    .shadow(color: accent.opacity(0.45), radius: 14)
                VStack(alignment: .leading, spacing: 4) {
                    Text(music.track?.title ?? " ")
                        .font(.system(size: 19, weight: .bold))
                        .lineLimit(2)
                    Text(music.track?.artist ?? " ")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                    if let album = music.track?.album, !album.isEmpty {
                        Text(album)
                            .font(.system(size: 11))
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    ProgressBar(duration: music.track?.duration ?? 0, accent: accent)
                    controls(main: 18, side: 13, spacing: 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(height: 124)
    }

    // MARK: Compact

    /// Une ligne : petite pochette, titre, commandes ; barre fine dessous.
    private var compact: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ArtworkView(image: music.artwork, cornerRadius: 7)
                    .opensSource()
                    .frame(width: 38, height: 38)
                    .overlay(alignment: .bottomTrailing) { SourceBadge(size: 15) }
                titles(titleSize: 13, artistSize: 11)
                Spacer(minLength: 6)
                visualizer
                controls(main: 16, side: 12, spacing: 4)
                    .fixedSize()
            }
            ProgressBar(duration: music.track?.duration ?? 0, accent: accent, showsTimes: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: Immersif

    /// Le fond flouté est posé sur toute la pastille (voir `ImmersiveBackground`) ; ici, tout est centré.
    private var immersive: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                ArtworkView(image: music.artwork, cornerRadius: 10)
                    .opensSource()
                    .frame(width: 70, height: 70)
                    .overlay(alignment: .bottomTrailing) { SourceBadge(size: 20) }
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(music.track?.title ?? " ")
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(1)
                    Text(music.track?.artist ?? " ")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            ProgressBar(duration: music.track?.duration ?? 0, accent: .white)
            controls(main: 26, side: 18, spacing: 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Vinyle

    /// Un disque (pochette au centre) qui tourne pendant la lecture.
    private var vinyl: some View {
        GeometryReader { geo in
            HStack(spacing: 18) {
                VinylDisc(image: music.artwork, isPlaying: music.isPlaying, accent: accent)
                    .opensSource()
                    .frame(width: geo.size.height, height: geo.size.height)
                VStack(alignment: .leading, spacing: 6) {
                    Spacer(minLength: 0)
                    titles(titleSize: 16, artistSize: 13)
                    ProgressBar(duration: music.track?.duration ?? 0, accent: accent)
                    controls(main: 22, side: 15, spacing: 20)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: 116)
    }

    // MARK: Éléments communs

    private func titles(titleSize: CGFloat, artistSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(music.track?.title ?? " ")
                .font(.system(size: titleSize, weight: .semibold))
                .lineLimit(1)
            Text(music.track?.artist ?? " ")
                .font(.system(size: artistSize))
                .foregroundStyle(.gray)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var visualizer: some View {
        if music.track != nil {
            AudioVisualizer(isPlaying: music.isPlaying, color: accent)
                .frame(width: 18, height: 12)
                .padding(.top, 3)
        }
    }

    private func controls(main: CGFloat, side: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ControlButton(symbol: "backward.fill", size: side) { music.previous() }
            ControlButton(symbol: music.isPlaying ? "pause.fill" : "play.fill", size: main) { music.playPause() }
            ControlButton(symbol: "forward.fill", size: side) { music.next() }
        }
        .frame(maxWidth: .infinity)
        .disabled(music.track == nil)
        .opacity(music.track == nil ? 0.4 : 1)
    }
}

private struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: 30)
                .background(Circle().fill(.white.opacity(hovering ? 0.12 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Barre de progression interpolée + glisser pour chercher.
private struct ProgressBar: View {
    let duration: Double
    let accent: Color
    var showsTimes = true
    @ObservedObject private var music = MusicManager.shared
    @State private var dragValue: Double?

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !music.isPlaying)) { context in
            let elapsed = dragValue ?? music.elapsed(at: context.date)
            VStack(spacing: 3) {
                GeometryReader { geo in
                    let fraction = duration > 0 ? elapsed / duration : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(accent).frame(width: geo.size.width * fraction)
                    }
                    .frame(height: dragValue == nil ? 5 : 7)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                dragValue = min(max(v.location.x / geo.size.width, 0), 1) * duration
                            }
                            .onEnded { _ in
                                if let dragValue { music.seek(to: dragValue) }
                                dragValue = nil
                            }
                    )
                }
                .frame(height: 9)
                if showsTimes {
                    HStack {
                        Text(format(elapsed))
                        Spacer()
                        Text("-" + format(duration - elapsed))
                    }
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.gray)
                    .opacity(duration > 0 ? 1 : 0)
                }
            }
        }
    }

    private func format(_ seconds: Double) -> String {
        let s = Int(max(seconds, 0))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
