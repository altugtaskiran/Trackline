//
//  DistanceUnit.swift
//  fastAndCar
//
//  Was previously just a Picker in Settings with nothing reading it back —
//  every stat display hardcoded km/km-h regardless of what was selected.
//  Now the single shared source for both the preference (still the same
//  "distanceUnit" @AppStorage key Settings already used) and the actual
//  km↔mi / km/h↔mph / m↔ft conversion + formatting, so every screen that
//  shows a distance, speed, or altitude reads the same value the same way.
//

import Foundation

enum DistanceUnit: String, CaseIterable, Identifiable {
    case kilometers
    case miles
    var id: String { rawValue }

    /// First-run default — a US/Liberia/Myanmar device (the only places
    /// still on imperial) starts on miles, everyone else on kilometers.
    /// Only used to seed the @AppStorage default; once the driver picks in
    /// Settings, that choice sticks regardless of region.
    static var systemDefault: DistanceUnit {
        Locale.current.measurementSystem == .us ? .miles : .kilometers
    }

    /// For non-View call sites (ShareCardRenderer and similar plain
    /// services) that can't hold an @AppStorage property wrapper — reads
    /// the same UserDefaults key Settings' @AppStorage writes to.
    static var current: DistanceUnit {
        guard let raw = UserDefaults.standard.string(forKey: "distanceUnit") else { return systemDefault }
        return DistanceUnit(rawValue: raw) ?? systemDefault
    }

    var label: String {
        switch self {
        case .kilometers: String.appLocalized("Kilometre")
        case .miles: String.appLocalized("Mil")
        }
    }

    var distanceSymbol: String { self == .kilometers ? "km" : "mi" }
    var speedSymbol: String { self == .kilometers ? "km/h" : "mph" }
    var altitudeSymbol: String { self == .kilometers ? "m" : "ft" }

    private var metersToDistanceUnit: Double { self == .kilometers ? 1000 : 1609.344 }
    private var kphToSpeedUnit: Double { self == .kilometers ? 1 : 0.621371 }
    private var metersToAltitudeUnit: Double { self == .kilometers ? 1 : 3.28084 }

    func distanceString(meters: Double, fractionDigits: Int = 1) -> String {
        String(format: "%.\(fractionDigits)f %@", meters / metersToDistanceUnit, distanceSymbol)
    }

    func speedString(kph: Double, fractionDigits: Int = 0) -> String {
        String(format: "%.\(fractionDigits)f %@", kph * kphToSpeedUnit, speedSymbol)
    }

    /// No unit suffix — for the few spots (e.g. "Zirih 122 km/h" style
    /// inline sentences) that already append the symbol themselves.
    func speedValue(kph: Double) -> Int {
        Int((kph * kphToSpeedUnit).rounded())
    }

    func altitudeString(meters: Double) -> String {
        String(format: "%.0f %@", meters * metersToAltitudeUnit, altitudeSymbol)
    }
}
