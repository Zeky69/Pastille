import SwiftUI

/// Code de vérification reçu (cliquer pour le copier), sinon la météo.
struct CodeOrWeatherView: View {
    @ObservedObject private var codes = VerificationCodeManager.shared
    @ObservedObject private var downloads = DownloadManager.shared
    @AppStorage(Appearance.showWeatherKey) private var showWeather = true
    @State private var hovering = false

    var body: some View {
        if let code = codes.current {
            // Juste la clé et le code, lisibles ; la provenance est dans l'infobulle.
            Button { codes.copy() } label: {
                HStack(spacing: 5) {
                    Image(systemName: codes.copied ? "checkmark" : "key.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                        .contentTransition(.symbolEffect(.replace))
                    Text(code.spaced)
                        .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                        .kerning(0.8)
                        .foregroundStyle(codes.copied ? Color.green : .white)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(hovering ? 0.18 : 0.1)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(codes.copied ? "Copié" : "\(code.caption)\(code.sender.isEmpty ? "" : " — " + code.sender) · cliquer pour copier")
            .transition(.blurReplace)
        } else if case .downloading(nil) = downloads.state, let measure = downloads.measure {
            // Téléchargement sans pourcentage : total déjà reçu et vitesse.
            // Le total à gauche ; la vitesse est de l'autre côté de l'encoche (voir DownloadSpeedView).
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 11))
                Text(measure.total)
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(.blue)
            .lineLimit(1)
            .transition(.blurReplace)
        } else if showWeather {
            WeatherView()
                .transition(.blurReplace)
        }
    }
}

/// Vitesse d'un téléchargement sans pourcentage, collée à droite de l'encoche (le total est à gauche).
struct DownloadSpeedView: View {
    @ObservedObject private var downloads = DownloadManager.shared

    var body: some View {
        if case .downloading(nil) = downloads.state, let speed = downloads.measure?.speed {
            Text(speed)
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(.blue)
                .lineLimit(1)
                .fixedSize()
                .transition(.blurReplace)
        }
    }
}
