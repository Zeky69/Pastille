import Combine
import ServiceManagement
import SwiftUI

/// Carte de préréglage : mini-aperçu de la pastille ouverte + nom.
struct PresetCard: View {
    let preset: Appearance.Preset
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                PresetPreview(preset: preset)
                    .frame(height: 54)
                Text(preset.label)
                    .font(.callout.weight(.semibold))
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(preset.summary)
    }
}

/// Dessin schématique de chaque préréglage.
struct PresetPreview: View {
    let preset: Appearance.Preset

    var body: some View {
        ZStack {
            UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
                .fill(.black)
            content
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 6)
        }
        .frame(width: preset == .minimal ? 92 : preset == .music ? 118 : 106)
    }

    private let block = Color.white.opacity(0.25)
    private let line = Color.white.opacity(0.18)

    @ViewBuilder
    private var content: some View {
        switch preset {
        case .classic, .custom:
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(Color.pink.opacity(0.7)).frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(line).frame(width: 26, height: 3)
                    Capsule().fill(Color.pink.opacity(0.7)).frame(width: 30, height: 2)
                }
                Spacer(minLength: 0)
                VStack(spacing: 3) {
                    HStack(spacing: 2) { ForEach(0..<4, id: \.self) { _ in Circle().fill(line).frame(width: 4, height: 4) } }
                    Capsule().fill(line).frame(width: 22, height: 3)
                }
            }
        case .minimal:
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(block).frame(width: 12, height: 12)
                Capsule().fill(line).frame(width: 30, height: 3)
                Spacer(minLength: 0)
                Image(systemName: "play.fill").font(.system(size: 6)).foregroundStyle(.white.opacity(0.6))
            }
        case .music:
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.85)).frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(.white.opacity(0.5)).frame(width: 34, height: 3)
                    Capsule().fill(Color.orange.opacity(0.9)).frame(width: 46, height: 2)
                }
                Spacer(minLength: 0)
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [.orange.opacity(0.45), .purple.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
            )
        case .agenda:
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    HStack(spacing: 3) {
                        Capsule().fill(index == 0 ? Color.blue : line).frame(width: 2, height: 7)
                        Capsule().fill(line).frame(width: CGFloat(40 - index * 8), height: 3)
                        Spacer(minLength: 0)
                        Capsule().fill(line).frame(width: 10, height: 3)
                    }
                }
            }
        }
    }
}

/// Carte d'un style de lecteur, avec son mini-aperçu.
struct MusicStyleCard: View {
    let style: Appearance.MusicStyle
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                MusicStylePreview(style: style)
                    .frame(width: 84, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(style.label).font(.caption.weight(.semibold))
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(hovering ? 0.08 : 0.04)))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct MusicStylePreview: View {
    let style: Appearance.MusicStyle

    private let art = LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
    private let line = Color.white.opacity(0.3)

    var body: some View {
        ZStack {
            Color.black
            switch style {
            case .artwork:
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(art).frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Capsule().fill(line).frame(width: 30, height: 3)
                        Capsule().fill(Color.pink).frame(width: 40, height: 2)
                        HStack(spacing: 4) { ForEach(0..<3, id: \.self) { _ in Circle().fill(line).frame(width: 4, height: 4) } }
                    }
                }
            case .poster:
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 4).fill(art).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Capsule().fill(.white.opacity(0.7)).frame(width: 30, height: 5)
                        Capsule().fill(Color.pink).frame(width: 22, height: 3)
                        Spacer().frame(height: 6)
                        Capsule().fill(line).frame(width: 34, height: 2)
                    }
                }
            case .compact:
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(art).frame(width: 12, height: 12)
                    Capsule().fill(line).frame(width: 30, height: 3)
                    Spacer(minLength: 0)
                    Image(systemName: "play.fill").font(.system(size: 6)).foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .frame(height: 20)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .padding(.horizontal, 6)
            case .immersive:
                ZStack {
                    LinearGradient(colors: [.pink.opacity(0.8), .orange.opacity(0.6), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .blur(radius: 6)
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3).fill(art).frame(width: 16, height: 16).shadow(radius: 2)
                            Capsule().fill(.white.opacity(0.8)).frame(width: 30, height: 3)
                        }
                        HStack(spacing: 7) { ForEach(0..<3, id: \.self) { i in Circle().fill(.white.opacity(0.85)).frame(width: i == 1 ? 6 : 4, height: i == 1 ? 6 : 4) } }
                    }
                }
            case .vinyl:
                HStack(spacing: 6) {
                    ZStack {
                        Circle().fill(Color(white: 0.12))
                        Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.5).padding(4)
                        Circle().fill(art).padding(10)
                        Circle().fill(Color(white: 0.12)).frame(width: 3, height: 3)
                    }
                    .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Capsule().fill(line).frame(width: 28, height: 3)
                        Capsule().fill(Color.pink).frame(width: 22, height: 2)
                    }
                }
            }
        }
    }
}
