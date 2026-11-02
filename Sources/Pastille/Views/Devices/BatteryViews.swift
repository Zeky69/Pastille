import SwiftUI

struct BatteryStatusView: View {
    @ObservedObject private var battery = BatteryManager.shared
    @AppStorage(Settings.showBatteryPercentKey) private var showPercent = true

    var body: some View {
        if battery.hasBattery {
            BatteryIcon(
                level: battery.level,
                isCharging: battery.isCharging || battery.isPluggedIn,
                showsPercent: showPercent
            )
        }
    }
}

/// Icône de batterie. Avec `showsPercent`, le pourcentage est écrit dans la batterie (comme sur iPhone) :
/// noir sur la partie remplie, blanc sur la partie vide, pour rester lisible à tous les niveaux.
struct BatteryIcon: View {
    let level: Int
    let isCharging: Bool
    var showsPercent = false

    private var fill: Color {
        if isCharging { return .green }
        if level <= 20 { return .red }
        return .white
    }

    private var size: CGSize { showsPercent ? CGSize(width: 25, height: 13) : CGSize(width: 24, height: 12) }
    private var fraction: CGFloat { CGFloat(min(max(level, 0), 100)) / 100 }

    var body: some View {
        HStack(spacing: 1) {
            // Avec le pourcentage, l'éclair de charge passe à gauche pour laisser respirer le chiffre.
            if showsPercent, isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.green)
                    .padding(.trailing, 2)
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5)
                    .stroke(.white.opacity(0.45), lineWidth: 1)
                RoundedRectangle(cornerRadius: 2)
                    .fill(fill)
                    .frame(width: max(2, (size.width - 4) * fraction))
                    .padding(2)
                if showsPercent {
                    percent
                } else if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: size.width, height: size.height)
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.45))
                .frame(width: 1.5, height: 4)
        }
        .animation(.easeInOut(duration: 0.3), value: level)
    }

    /// Le même texte deux fois : noir, découpé sur la partie remplie ; blanc, découpé sur le reste.
    private var percent: some View {
        let label = Text("\(level)")
            .font(.system(size: 8.5, weight: .semibold, design: .rounded).monospacedDigit())
            .tracking(-0.2)
            .frame(maxWidth: .infinity)

        let filledWidth = 2 + (size.width - 4) * fraction
        return ZStack {
            label
                .foregroundStyle(.white)
                .mask(alignment: .trailing) { Rectangle().frame(width: max(size.width - filledWidth, 0)) }
            label
                .foregroundStyle(.black)
                .mask(alignment: .leading) { Rectangle().frame(width: filledWidth) }
        }
        .frame(width: size.width, height: size.height)
    }
}
