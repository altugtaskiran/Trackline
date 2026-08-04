//
//  TripAutoDetector.swift
//  fastAndCar
//
//  Watches the live sample stream to detect stationary periods (timeline
//  "Stop" entries) and to suggest ending a trip after a long stop, without
//  ever forcing it — the user always has a manual End Drive control.
//

import Foundation
import Observation

struct TripStopEvent: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var startTime: Date
    var endTime: Date?
    var label: String = "Stop"

    var duration: TimeInterval? {
        guard let endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
}

@Observable
final class TripAutoDetector {
    private(set) var isStopped = false
    private(set) var stopEvents: [TripStopEvent] = []
    private(set) var shouldSuggestEnd = false

    /// Below ~5 km/h counts as stationary — filters out red-light creep and GPS noise.
    private let stopSpeedThresholdMps: Double = 1.4
    /// Must be stationary this long before it's logged as a real stop.
    private let stopConfirmDuration: TimeInterval = 15
    /// Stationary this long and we gently suggest ending the trip.
    private let suggestEndAfterStopped: TimeInterval = 240

    private var stoppedSince: Date?

    func reset() {
        isStopped = false
        stopEvents = []
        shouldSuggestEnd = false
        stoppedSince = nil
    }

    func ingest(_ sample: LocationSample) {
        let stationary = sample.speedMps < stopSpeedThresholdMps

        guard stationary else {
            if isStopped, let lastIndex = stopEvents.indices.last, stopEvents[lastIndex].endTime == nil {
                stopEvents[lastIndex].endTime = sample.timestamp
            }
            isStopped = false
            shouldSuggestEnd = false
            stoppedSince = nil
            return
        }

        let since = stoppedSince ?? sample.timestamp
        stoppedSince = since
        let elapsedStopped = sample.timestamp.timeIntervalSince(since)

        if elapsedStopped >= stopConfirmDuration, !isStopped {
            isStopped = true
            stopEvents.append(TripStopEvent(startTime: since, endTime: nil))
        }
        if elapsedStopped >= suggestEndAfterStopped {
            shouldSuggestEnd = true
        }
    }
}
