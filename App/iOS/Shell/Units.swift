import Foundation

/// Display units (Settings → Units). UserDefaults key "tempUnit": "c" (default, like the prototype) or "f".
enum TwinUnits {
    static let temperatureKey = "tempUnit"

    static var usesFahrenheit: Bool { UserDefaults.standard.string(forKey: temperatureKey) == "f" }

    /// "11°C" or "52°F" from a Celsius value.
    static func temperature(_ celsius: Double) -> String {
        usesFahrenheit ? "\(Int((celsius * 9 / 5 + 32).rounded()))°F" : "\(Int(celsius.rounded()))°C"
    }
}
