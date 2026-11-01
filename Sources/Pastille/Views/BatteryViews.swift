import SwiftUI

struct BatteryStatusView: View {
    @ObservedObject private var battery = BatteryManager.shared
    @AppStorage(Settings.showBatteryPercentKey) private var showPercent = true

    var body: some View {
        if battery.hasBattery {
            HStack(spacing: 5) {
                if showPercent {
                    Text("\(battery.level)%")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.gray)
                }
                BatteryIcon(level: battery.level, isCharging: battery.isCharging || battery.isPluggedIn)
            }
        }
    }
}

struct BatteryIcon: View {
    let level: Int
    let isCharging: Bool

    private var fill: Color {
        if isCharging { return .green }
        if level <= 20 { return .red }
        return .white
    }

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5)
                    .stroke(.white.opacity(0.45), lineWidth: 1)
                RoundedRectangle(cornerRadius: 2)
                    .fill(fill)
                    .frame(width: max(2, 18 * CGFloat(level) / 100))
                    .padding(2)
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 24, height: 12)
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.45))
                .frame(width: 1.5, height: 4)
        }
    }
}
