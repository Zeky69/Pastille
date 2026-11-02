import CoreLocation
import Foundation

struct Weather: Equatable {
    var temperature: Int
    /// Code météo WMO (0 = ciel clair, 61 = pluie…).
    var code: Int
    var isDay: Bool
}

/// Météo à la position du Mac : CoreLocation (précision au kilomètre) + Open-Meteo (gratuit, sans compte).
/// Seules des coordonnées arrondies (~1 km) quittent le Mac.
@MainActor
final class WeatherManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherManager()

    @Published private(set) var weather: Weather?

    private let location = CLLocationManager()
    private var coordinate: CLLocationCoordinate2D?
    private var lastFetch: Date?
    private var poll: Timer?
    private var unit: String?
    private static let refreshInterval: TimeInterval = 30 * 60

    func start() {
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyKilometer
        // Changement d'unité (°C / °F) : nouvelle lecture tout de suite.
        unit = UserDefaults.standard.string(forKey: Appearance.weatherUnitKey)
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let manager = WeatherManager.shared
                let unit = UserDefaults.standard.string(forKey: Appearance.weatherUnitKey)
                if unit != manager.unit { manager.unit = unit; manager.fetch() }
            }
        }
        location.requestWhenInUseAuthorization()
        // Position demandée une fois par mise à jour (pas de suivi continu) ; la météo suit.
        location.requestLocation()
        poll = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { _ in
            MainActor.assumeIsolated { WeatherManager.shared.location.requestLocation() }
        }
        poll?.tolerance = 60
    }

    /// À l'ouverture de la pastille : on ne recharge que si la météo date de plus de 30 min.
    func refreshIfStale() {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < Self.refreshInterval { return }
        lastFetch = Date()
        location.requestLocation()
    }

    private func fetch() {
        guard let coordinate else { return }
        lastFetch = Date()
        guard var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast") else { return }
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.2f", coordinate.latitude)),
            .init(name: "longitude", value: String(format: "%.2f", coordinate.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "temperature_unit", value: UserDefaults.standard.string(forKey: Appearance.weatherUnitKey) ?? "celsius"),
        ]
        guard let url = components.url else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any],
                  let temperature = current["temperature_2m"] as? Double,
                  let code = current["weather_code"] as? Int else { return }
            let weather = Weather(
                temperature: Int(temperature.rounded()),
                code: code,
                isDay: (current["is_day"] as? Int ?? 1) == 1
            )
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if WeatherManager.shared.weather != weather { WeatherManager.shared.weather = weather }
                }
            }
        }.resume()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                WeatherManager.shared.coordinate = coordinate
                WeatherManager.shared.fetch()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { WeatherManager.shared.location.requestLocation() }
        }
    }

    /// Position indisponible : on garde la dernière connue pour la météo.
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { WeatherManager.shared.fetch() }
        }
    }
}

extension Weather {
    /// Symbole SF multicolore d'après le code WMO.
    var symbol: String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 66, 80, 81: return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 65, 67, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}
