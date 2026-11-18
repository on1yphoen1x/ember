import Foundation
import IOKit.ps

struct Battery: Equatable {
    let percent: Int
    let isCharging: Bool

    var symbol: String {
        switch percent {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }

    @MainActor private static var cached: (battery: Battery?, at: Date)?

    /// Reads at most once every half minute, since the lock screen redraws ten times a second.
    @MainActor static func read(at date: Date) -> Battery? {
        if let cached, date.timeIntervalSince(cached.at) < 30 { return cached.battery }
        let battery = readNow()
        cached = (battery, date)
        return battery
    }

    static func readNow() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            return Battery(percent: current * 100 / maximum, isCharging: charging)
        }
        return nil
    }
}
