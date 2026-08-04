//
//  LocationSample.swift
//  fastAndCar
//
//  A single, app-level GPS reading. Decoupled from CLLocation so the rest of
//  the app never has to import CoreLocation.
//

import CoreLocation
import Foundation

struct LocationSample: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    /// Meters per second. Already normalized to >= 0 (invalid CoreLocation readings become 0).
    var speedMps: Double
    var altitude: Double
    /// Degrees from true north, 0..<360. Nil when unavailable.
    var heading: Double?
    var horizontalAccuracy: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var speedKph: Double { speedMps * 3.6 }

    init(coordinate: CLLocationCoordinate2D, timestamp: Date, speedMps: Double, altitude: Double, heading: Double?, horizontalAccuracy: Double) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.timestamp = timestamp
        self.speedMps = max(speedMps, 0)
        self.altitude = altitude
        self.heading = heading
        self.horizontalAccuracy = horizontalAccuracy
    }
}
