import CoreLocation
import Foundation

/// Current conditions from Open-Meteo, which needs no account. The location is
/// rounded to about a kilometre before it leaves the Mac.
@MainActor
final class Weather: NSObject, ObservableObject {
    struct Conditions: Equatable {
        let temperature: Double
        let code: Int

        var symbol: String {
            switch code {
            case 0: "sun.max.fill"
            case 1, 2: "cloud.sun.fill"
            case 3: "cloud.fill"
            case 45, 48: "cloud.fog.fill"
            case 51...57: "cloud.drizzle.fill"
            case 61...67, 80...82: "cloud.rain.fill"
            case 71...77, 85, 86: "cloud.snow.fill"
            case 95...99: "cloud.bolt.rain.fill"
            default: "cloud.fill"
            }
        }

        var temperatureText: String {
            Measurement(value: temperature, unit: UnitTemperature.celsius)
                .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
        }
    }

    @Published private(set) var conditions: Conditions?

    private let manager = CLLocationManager()
    private var lastFetch = Date.distantPast
    private var timer: Timer?

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.showsWeather, default: true)
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        guard isEnabled else {
            conditions = nil
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorized:
            manager.requestLocation()
        default:
            break
        }
    }

    private func fetch(for location: CLLocation) {
        guard Date().timeIntervalSince(lastFetch) > 600 else { return }
        lastFetch = Date()
        let latitude = (location.coordinate.latitude * 100).rounded() / 100
        let longitude = (location.coordinate.longitude * 100).rounded() / 100
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,weather_code") else { return }

        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = root["current"] as? [String: Any],
                  let temperature = (current["temperature_2m"] as? NSNumber)?.doubleValue,
                  let code = (current["weather_code"] as? NSNumber)?.intValue else { return }
            conditions = Conditions(temperature: temperature, code: code)
        }
    }
}

extension Weather: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { refresh() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated { fetch(for: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
