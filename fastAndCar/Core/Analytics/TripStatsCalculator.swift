//
//  TripStatsCalculator.swift
//  fastAndCar
//
//  Derives every stat-tile number from the raw sample stream. Pure function,
//  no persistence or UI concerns — easy to unit test in isolation.
//

import Foundation

struct TripStats: Codable, Equatable {
    var topSpeedKph: Double
    var averageSpeedKph: Double
    var distanceMeters: Double
    var driveTime: TimeInterval
    var movingTime: TimeInterval
    var stoppedTime: TimeInterval
    var maxAccelerationG: Double
    var maxBrakingG: Double
    var highestAltitude: Double
    var lowestAltitude: Double
    var stopCount: Int
    var averageGpsAccuracy: Double
    var startTime: Date
    var finishTime: Date
}

enum TripStatsCalculator {
    /// Standard gravity, used to express accel/braking in g-force.
    private static let gravity = 9.80665
    /// Anything implying a faster speed than this between two consecutive
    /// samples (~300 km/h) is a GPS glitch/teleport, not real driving — a
    /// single bad fix (tunnel exit, cold start, urban canyon) would otherwise
    /// blow up distance/average-speed without bound. Excluded, not clamped,
    /// so it doesn't skew accel/braking either.
    private static let maxPlausibleSpeedMps = 83.0

    static func calculate(samples: [LocationSample], stopEvents: [TripStopEvent]) -> TripStats? {
        guard let first = samples.first, let last = samples.last else { return nil }

        var distance = 0.0
        var maxAccelG = 0.0
        var maxBrakeG = 0.0
        var topSpeedKph = 0.0
        var altitudes: [Double] = []
        var accuracySum = 0.0

        for (index, sample) in samples.enumerated() {
            topSpeedKph = max(topSpeedKph, sample.speedKph)
            altitudes.append(sample.altitude)
            accuracySum += sample.horizontalAccuracy

            guard index > 0 else { continue }
            let previous = samples[index - 1]
            let dt = sample.timestamp.timeIntervalSince(previous.timestamp)
            guard dt > 0 else { continue }

            let segmentDistance = GeoMath.distanceMeters(from: previous.coordinate, to: sample.coordinate)
            guard segmentDistance / dt <= maxPlausibleSpeedMps else { continue }
            distance += segmentDistance

            let accelG = ((sample.speedMps - previous.speedMps) / dt) / gravity
            maxAccelG = max(maxAccelG, accelG)
            maxBrakeG = min(maxBrakeG, accelG)
        }

        let stoppedTime = stopEvents.reduce(0.0) { $0 + ($1.duration ?? 0) }
        let driveTime = last.timestamp.timeIntervalSince(first.timestamp)
        let movingTime = max(driveTime - stoppedTime, 0)
        let averageSpeedKph = movingTime > 0 ? (distance / movingTime) * 3.6 : 0

        return TripStats(
            topSpeedKph: topSpeedKph,
            averageSpeedKph: averageSpeedKph,
            distanceMeters: distance,
            driveTime: driveTime,
            movingTime: movingTime,
            stoppedTime: stoppedTime,
            maxAccelerationG: maxAccelG,
            maxBrakingG: maxBrakeG,
            highestAltitude: altitudes.max() ?? 0,
            lowestAltitude: altitudes.min() ?? 0,
            stopCount: stopEvents.count,
            averageGpsAccuracy: samples.isEmpty ? 0 : accuracySum / Double(samples.count),
            startTime: first.timestamp,
            finishTime: last.timestamp
        )
    }
}
