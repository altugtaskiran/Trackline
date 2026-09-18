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
    var elevationGainMeters: Double
    var elevationLossMeters: Double
    var steepestClimbPercent: Double
    var steepestDescentPercent: Double
    var harshBrakeCount: Int
    var harshAccelCount: Int
    var corneringCount: Int
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
    /// Shared with DrivingScoreCalculator's insight text — a single
    /// threshold definition for what counts as a harsh brake/accel event.
    private static let harshAccelThresholdG = 0.35
    /// GPS/barometric altitude jitters by roughly this much even standing
    /// still; ignoring smaller deltas keeps elevation gain/loss from
    /// accumulating pure noise over a long trip.
    private static let elevationNoiseThresholdMeters = 1.5
    /// Grade (%) is undefined/unstable over near-zero horizontal distance —
    /// skip segments shorter than this rather than dividing by ~0.
    private static let minHorizontalDistanceForGradeMeters = 3.0
    /// Cornering hysteresis: enter a "turning" state above this angular
    /// rate, count one event, then require the rate to drop below the exit
    /// threshold before a new turn can be counted — so one sustained turn
    /// isn't double counted as the rate fluctuates near the boundary.
    private static let corneringEnterDegPerSecond = 25.0
    private static let corneringExitDegPerSecond = 10.0
    /// Below this speed, heading readings are noisy/meaningless (parking,
    /// stopped at a light), so they're excluded from cornering detection.
    private static let minSpeedForCorneringMps = 3.0

    static func calculate(samples: [LocationSample], stopEvents: [TripStopEvent]) -> TripStats? {
        guard let first = samples.first, let last = samples.last else { return nil }

        var distance = 0.0
        var maxAccelG = 0.0
        var maxBrakeG = 0.0
        var topSpeedKph = 0.0
        var altitudes: [Double] = []
        var accuracySum = 0.0
        var elevationGain = 0.0
        var elevationLoss = 0.0
        var steepestClimb = 0.0
        var steepestDescent = 0.0
        var harshBrakeCount = 0
        var harshAccelCount = 0
        var corneringCount = 0
        var isTurning = false

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
            if accelG <= -harshAccelThresholdG { harshBrakeCount += 1 }
            if accelG >= harshAccelThresholdG { harshAccelCount += 1 }

            let altitudeDelta = sample.altitude - previous.altitude
            if abs(altitudeDelta) >= elevationNoiseThresholdMeters {
                if altitudeDelta > 0 {
                    elevationGain += altitudeDelta
                } else {
                    elevationLoss += -altitudeDelta
                }
            }
            if segmentDistance >= minHorizontalDistanceForGradeMeters {
                let gradePercent = (altitudeDelta / segmentDistance) * 100
                if gradePercent > 0 {
                    steepestClimb = max(steepestClimb, gradePercent)
                } else {
                    steepestDescent = max(steepestDescent, -gradePercent)
                }
            }

            if let heading = sample.heading, let previousHeading = previous.heading,
               sample.speedMps >= minSpeedForCorneringMps {
                var delta = heading - previousHeading
                if delta > 180 { delta -= 360 }
                if delta < -180 { delta += 360 }
                let angularRateDegPerSecond = abs(delta) / dt
                if isTurning {
                    if angularRateDegPerSecond < corneringExitDegPerSecond { isTurning = false }
                } else if angularRateDegPerSecond > corneringEnterDegPerSecond {
                    isTurning = true
                    corneringCount += 1
                }
            }
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
            finishTime: last.timestamp,
            elevationGainMeters: elevationGain,
            elevationLossMeters: elevationLoss,
            steepestClimbPercent: steepestClimb,
            steepestDescentPercent: steepestDescent,
            harshBrakeCount: harshBrakeCount,
            harshAccelCount: harshAccelCount,
            corneringCount: corneringCount
        )
    }
}
