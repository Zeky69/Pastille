import SwiftUI

/// Petite météo : illustration multicolore + température.
struct WeatherView: View {
    @ObservedObject private var weather = WeatherManager.shared

    var body: some View {
        if let current = weather.weather {
            HStack(spacing: 4) {
                Image(systemName: current.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 12))
                    .contentTransition(.symbolEffect(.replace))
                Text("\(current.temperature)°")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
            }
            .transition(.opacity)
        }
    }
}
