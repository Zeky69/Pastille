import SwiftUI

/// Code de vérification reçu (cliquer pour le copier), sinon la météo.
struct CodeOrWeatherView: View {
    @ObservedObject private var codes = VerificationCodeManager.shared
    @ObservedObject private var downloads = DownloadManager.shared
    @AppStorage(Appearance.showWeatherKey) private var showWeather = true
    @AppStorage(Appearance.codesSenderKey) private var showSender = true

    var body: some View {
        if let code = codes.current {
            Button { codes.copy() } label: {
                HStack(spacing: 5) {
                    if showSender, let service = code.service {
                        Text(service)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                        Text("·").foregroundStyle(.white.opacity(0.4))
                    }
                    Text(code.code)
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    Image(systemName: codes.copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundStyle(codes.copied ? Color.green : .white)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(Color.green.opacity(codes.copied ? 0.2 : 0.3)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(code.sender.isEmpty ? "Copier le code" : "Code reçu de \(code.sender) — cliquer pour copier")
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
