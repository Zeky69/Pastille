import SwiftUI

/// Pochette recadrée au centre pour remplir exactement le cadre donné, quel que soit son format
/// (une miniature de vidéo 16:9 devient un carré, sans déborder).
struct ArtworkView: View {
    let image: NSImage?
    let cornerRadius: CGFloat

    var body: some View {
        // Le cadre vient du parent ; l'image remplit ce cadre et ce qui dépasse est coupé.
        Color.white.opacity(image == nil ? 0.1 : 0)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Fond du style « Immersif » : la pochette floutée sur toute la pastille ouverte.
struct ImmersiveBackground: View {
    @ObservedObject private var music = MusicManager.shared

    var body: some View {
        ZStack {
            // Image déjà floutée (voir MusicManager.blurredArtwork) : rien à recalculer pendant les animations.
            if let blurred = music.blurredArtwork {
                Image(nsImage: blurred)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .opacity(0.7)
                    .transition(.opacity)
            }
            LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.15), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
        }
        .animation(.easeInOut(duration: 0.5), value: music.blurredArtwork)
        .allowsHitTesting(false)
    }
}

/// Disque vinyle : sillons, pochette ronde au centre, rotation pendant la lecture.
struct VinylDisc: View {
    let image: NSImage?
    let isPlaying: Bool
    let accent: Color

    var body: some View {
        // 30 images par seconde suffisent pour une rotation lente (un tour en 4 s).
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            disc
                .rotationEffect(.degrees(rotation(at: context.date)))
        }
        .shadow(color: accent.opacity(0.35), radius: 12)
    }

    private var disc: some View {
        ZStack {
            Circle().fill(Color(white: 0.07))
            ForEach(0..<6, id: \.self) { ring in
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.6)
                    .padding(CGFloat(ring) * 5 + 4)
            }
            ArtworkView(image: image, cornerRadius: 999)
                .clipShape(Circle())
                .padding(28)
            Circle().fill(Color(white: 0.07)).frame(width: 7, height: 7)
        }
    }

    /// Angle tiré de la position dans le morceau : le disque s'arrête et repart avec la musique.
    private func rotation(at date: Date) -> Double {
        let elapsed = MusicManager.shared.elapsed(at: date)
        return elapsed.truncatingRemainder(dividingBy: 4) / 4 * 360
    }
}
