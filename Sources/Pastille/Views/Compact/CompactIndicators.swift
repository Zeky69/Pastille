import SwiftUI

/// Anneau de batterie qui se remplit à l'apparition, avec le pourcentage à côté.
/// Niveau inconnu (-1) : « Connecté », le temps que la batterie arrive.
struct ConnectedRing: View {
    let level: Int
    @State private var filled = false

    private var color: Color { level <= 20 ? .red : .green }

    var body: some View {
        if level < 0 {
            Text("Connecté")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize()
                .transition(.opacity)
        } else {
            HStack(spacing: 5) {
                Text("\(level)%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .fixedSize()
                ZStack {
                    Circle().stroke(color.opacity(0.25), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: filled ? CGFloat(level) / 100 : 0)
                        .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 15, height: 15)
            }
            .transition(.opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8).delay(0.15)) { filled = true }
            }
        }
    }
}

// MARK: - Minuteur terminé

/// Anneau orange plein qui pulse doucement, comme une sonnerie silencieuse.
struct TimerDoneRing: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .stroke(Color.orange, lineWidth: 2.5)
            .overlay(Image(systemName: "bell.fill").font(.system(size: 7, weight: .bold)).foregroundStyle(.orange))
            .scaleEffect(pulse ? 1.12 : 0.92)
            .opacity(pulse ? 1 : 0.6)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

// MARK: - Débranchement

/// Éclair qui s'éteint : vert au départ, il se barre et devient gris.
struct UnpluggedIcon: View {
    @State private var off = false

    var body: some View {
        Image(systemName: off ? "bolt.slash.fill" : "bolt.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(off ? Color.white.opacity(0.7) : .green)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: off)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.spring(duration: 0.4, bounce: 0.3)) { off = true }
                }
            }
    }
}

// MARK: - Minuteur

/// Anneau orange qui se vide au fil du temps.
struct TimerRing: View {
    let timer: ClockTimer

    var body: some View {
        // Une image par seconde suffit : l'anneau bouge de moins de 2 % par seconde dès 1 min.
        TimelineView(.periodic(from: .now, by: timer.duration < 60 ? 0.25 : 1)) { context in
            ZStack {
                Circle().stroke(Color.orange.opacity(0.25), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: timer.progress(at: context.date))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

struct TimerLabel: View {
    let timer: ClockTimer

    var body: some View {
        // Calé juste après chaque changement de seconde, sans animation, comme Horloge.
        TimelineView(.periodic(from: tickStart, by: 1)) { context in
            Text(format(timer.remaining(at: context.date)))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.orange)
                .opacity(timer.isPaused ? 0.6 : 1)
                .transaction { $0.animation = nil }
        }
    }

    /// Un changement de seconde passé (à chaque « ,5 » restant), plus 20 ms pour tomber sûrement après.
    private var tickStart: Date {
        guard let fireDate = timer.fireDate else { return .now }
        let remaining = fireDate.timeIntervalSinceNow
        return fireDate.addingTimeInterval(-((remaining - 0.5).rounded(.up) + 0.5) + 0.02)
    }

    private func format(_ seconds: Double) -> String {
        // Horloge arrondit à la seconde la plus proche (850,88 s s'affiche 14:11).
        let s = Int(seconds.rounded())
        let (hours, minutes, secs) = (s / 3600, (s % 3600) / 60, s % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Téléchargement

/// Anneau de progression ; s'il n'y a pas de pourcentage, un arc qui tourne.
struct DownloadRing: View {
    let state: DownloadManager.State
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.blue.opacity(0.25), lineWidth: 2.5)
            switch state {
            case .downloading(let fraction?):
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: fraction)
            case .downloading(nil):
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
            case .finished:
                Circle().stroke(Color.green, lineWidth: 2.5)
            case .idle:
                EmptyView()
            }
        }
    }
}

// MARK: - Chronomètre

struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule()
                    .fill(.white)
                    .frame(width: geo.size.width * CGFloat(min(max(level, 0), 1)))
            }
        }
        .animation(.spring(duration: 0.25, bounce: 0.1), value: level)
    }
}

extension HUDValue {
    var symbol: String {
        switch kind {
        case .brightness:
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            // Casque ou AirPods : leur icône (la barre montre le niveau, vide si coupé).
            switch output {
            case .headphones: return "headphones"
            case .airpods: return "airpods"
            case .airpodsPro: return "airpodspro"
            case .airpodsMax: return "airpodsmax"
            case .speaker: break
            }
            if muted || level == 0 { return "speaker.slash.fill" }
            if level < 0.33 { return "speaker.wave.1.fill" }
            if level < 0.66 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }
}
