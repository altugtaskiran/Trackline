//
//  Trip.swift
//  fastAndCar
//
//  SwiftData model for a completed drive. Route samples and stop events are
//  stored as encoded JSON blobs rather than child model relationships — a
//  drive can carry thousands of samples, and a single decode-on-demand blob
//  is far cheaper than thousands of SwiftData rows. Stats/score are
//  denormalized onto the model so Home's list can render without decoding
//  the route at all.
//

import Foundation
import SwiftData

@Model
final class Trip {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var name: String?

    private var samplesData: Data = Data()
    private var stopEventsData: Data = Data()
    private var scoreInsightsData: Data = Data()

    var topSpeedKph: Double = 0
    var averageSpeedKph: Double = 0
    var distanceMeters: Double = 0
    var driveTime: TimeInterval = 0
    var movingTime: TimeInterval = 0
    var stoppedTime: TimeInterval = 0
    var maxAccelerationG: Double = 0
    var maxBrakingG: Double = 0
    var highestAltitude: Double = 0
    var lowestAltitude: Double = 0
    var stopCount: Int = 0
    var averageGpsAccuracy: Double = 0
    var startTime: Date = Date()
    var finishTime: Date = Date()
    var drivingScoreValue: Int = 0
    var elevationGainMeters: Double = 0
    var elevationLossMeters: Double = 0
    var steepestClimbPercent: Double = 0
    var steepestDescentPercent: Double = 0
    var harshBrakeCount: Int = 0
    var harshAccelCount: Int = 0
    var corneringCount: Int = 0

    /// Filled in asynchronously after save via PlaceNameResolver — nil until
    /// reverse geocoding resolves (or if it fails, e.g. offline).
    var startPlaceName: String?
    var endPlaceName: String?

    /// Set (after save, once a completed match is confirmed — see
    /// AppRootView.handleTripEnded) when this drive actually followed a
    /// specific public (global or crew) Segment through to completion —
    /// nil for a plain freeform drive, or a route-following attempt that
    /// didn't finish. Lets Sürüşlerim show that this trip was racing/
    /// following someone else's route rather than looking identical to
    /// any other recording.
    var followedSegmentId: String?
    var followedSegmentName: String?

    init(samples: [LocationSample], stopEvents: [TripStopEvent], stats: TripStats, score: DrivingScore) {
        self.id = UUID()
        self.createdAt = Date()
        self.samplesData = (try? JSONEncoder().encode(samples)) ?? Data()
        self.stopEventsData = (try? JSONEncoder().encode(stopEvents)) ?? Data()
        self.scoreInsightsData = (try? JSONEncoder().encode(score.insights)) ?? Data()

        self.topSpeedKph = stats.topSpeedKph
        self.averageSpeedKph = stats.averageSpeedKph
        self.distanceMeters = stats.distanceMeters
        self.driveTime = stats.driveTime
        self.movingTime = stats.movingTime
        self.stoppedTime = stats.stoppedTime
        self.maxAccelerationG = stats.maxAccelerationG
        self.maxBrakingG = stats.maxBrakingG
        self.highestAltitude = stats.highestAltitude
        self.lowestAltitude = stats.lowestAltitude
        self.stopCount = stats.stopCount
        self.averageGpsAccuracy = stats.averageGpsAccuracy
        self.startTime = stats.startTime
        self.finishTime = stats.finishTime
        self.drivingScoreValue = score.value
        self.elevationGainMeters = stats.elevationGainMeters
        self.elevationLossMeters = stats.elevationLossMeters
        self.steepestClimbPercent = stats.steepestClimbPercent
        self.steepestDescentPercent = stats.steepestDescentPercent
        self.harshBrakeCount = stats.harshBrakeCount
        self.harshAccelCount = stats.harshAccelCount
        self.corneringCount = stats.corneringCount
    }

    /// One-time backfill for trips saved before elevation/event stats
    /// existed — see StatsBackfill.swift. Recomputes only the new fields
    /// from the already-stored raw samples; nothing else changes.
    func applyBackfilledStats(_ stats: TripStats) {
        elevationGainMeters = stats.elevationGainMeters
        elevationLossMeters = stats.elevationLossMeters
        steepestClimbPercent = stats.steepestClimbPercent
        steepestDescentPercent = stats.steepestDescentPercent
        harshBrakeCount = stats.harshBrakeCount
        harshAccelCount = stats.harshAccelCount
        corneringCount = stats.corneringCount
    }

    var samples: [LocationSample] {
        (try? JSONDecoder().decode([LocationSample].self, from: samplesData)) ?? []
    }

    var stopEvents: [TripStopEvent] {
        (try? JSONDecoder().decode([TripStopEvent].self, from: stopEventsData)) ?? []
    }

    var scoreInsights: [String] {
        (try? JSONDecoder().decode([String].self, from: scoreInsightsData)) ?? []
    }

    var stats: TripStats {
        TripStats(
            topSpeedKph: topSpeedKph,
            averageSpeedKph: averageSpeedKph,
            distanceMeters: distanceMeters,
            driveTime: driveTime,
            movingTime: movingTime,
            stoppedTime: stoppedTime,
            maxAccelerationG: maxAccelerationG,
            maxBrakingG: maxBrakingG,
            highestAltitude: highestAltitude,
            lowestAltitude: lowestAltitude,
            stopCount: stopCount,
            averageGpsAccuracy: averageGpsAccuracy,
            startTime: startTime,
            finishTime: finishTime,
            elevationGainMeters: elevationGainMeters,
            elevationLossMeters: elevationLossMeters,
            steepestClimbPercent: steepestClimbPercent,
            steepestDescentPercent: steepestDescentPercent,
            harshBrakeCount: harshBrakeCount,
            harshAccelCount: harshAccelCount,
            corneringCount: corneringCount
        )
    }

    var drivingScore: DrivingScore {
        DrivingScore(value: drivingScoreValue, insights: scoreInsights)
    }

    /// Renames a timeline stop (e.g. "Stop" → "Fuel Stop"), the one bit of
    /// post-trip editing the timeline supports.
    func renameStopEvent(id: UUID, to label: String) {
        var events = stopEvents
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        events[index].label = label
        stopEventsData = (try? JSONEncoder().encode(events)) ?? stopEventsData
    }

    /// "Start → End" once reverse geocoding has resolved, falling back to
    /// the start date while it hasn't (or if it never does, e.g. offline).
    /// Shared by Home's trip rows and the Trip Detail title.
    var routeTitle: String {
        switch (startPlaceName, endPlaceName) {
        case let (start?, end?) where start == end:
            return start
        case let (start?, end?):
            return "\(start) → \(end)"
        case let (start?, nil):
            return start
        case let (nil, end?):
            return end
        default:
            // Not a View, so no @Environment(\.locale) to read here —
            // String.appLocalized's same AppLanguage.current lookup covers
            // the Settings > Language override for this plain model type too.
            let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
                .locale(AppLanguage.current.locale ?? .autoupdatingCurrent)
            return startTime.formatted(style)
        }
    }
}
