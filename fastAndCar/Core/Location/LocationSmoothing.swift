//
//  LocationSmoothing.swift
//  fastAndCar
//
//  Lightweight scalar Kalman filter that removes GPS jitter from raw
//  coordinates before they're used for route drawing and speed math.
//  Not a full sensor-fusion filter — just enough to smooth consumer-grade
//  GPS noise without introducing perceptible lag.
//

import CoreLocation
import Foundation

final class LocationSmoothing {
    /// Meters of position uncertainty gained per second with no new reading.
    private let processNoise: Double = 3.0

    private var variance: Double = -1
    private var filteredCoordinate = CLLocationCoordinate2D()
    private var lastTimestamp: Date?

    func reset() {
        variance = -1
        lastTimestamp = nil
    }

    func filter(coordinate: CLLocationCoordinate2D, horizontalAccuracy: Double, at date: Date) -> CLLocationCoordinate2D {
        let measurementNoise = max(horizontalAccuracy, 1)

        guard variance >= 0 else {
            filteredCoordinate = coordinate
            variance = measurementNoise * measurementNoise
            lastTimestamp = date
            return coordinate
        }

        let elapsed = lastTimestamp.map { date.timeIntervalSince($0) } ?? 0
        lastTimestamp = date
        if elapsed > 0 {
            variance += elapsed * processNoise * processNoise
        }

        let gain = variance / (variance + measurementNoise * measurementNoise)
        let newLatitude = filteredCoordinate.latitude + gain * (coordinate.latitude - filteredCoordinate.latitude)
        let newLongitude = filteredCoordinate.longitude + gain * (coordinate.longitude - filteredCoordinate.longitude)
        filteredCoordinate = CLLocationCoordinate2D(latitude: newLatitude, longitude: newLongitude)
        variance = (1 - gain) * variance
        return filteredCoordinate
    }
}
