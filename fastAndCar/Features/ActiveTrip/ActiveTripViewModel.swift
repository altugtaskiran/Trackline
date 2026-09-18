//
//  ActiveTripViewModel.swift
//  fastAndCar
//
//  Owns the live recording session: accumulates samples from LocationManager,
//  feeds TripAutoDetector, and derives the live speed/distance/time readout.
//  On End Drive it hands back a fully-computed result; the view is
//  responsible for persisting it (keeps SwiftData at the navigation boundary).
//

import Foundation
import Observation

@Observable
final class ActiveTripViewModel {
    struct TripResult {
        let samples: [LocationSample]
        let stopEvents: [TripStopEvent]
        let stats: TripStats
        let score: DrivingScore
    }

    private let locationManager: LocationManager
    private let autoDetector = TripAutoDetector()
    private var timer: Timer?
    private var startDate: Date?

    private(set) var samples: [LocationSample] = []
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var distanceMeters: Double = 0
    private(set) var currentSpeedKph: Double = 0
    private(set) var isStopped = false
    private(set) var showsEndSuggestion = false

    /// Set before `start()` (via DashboardView, when arriving from a
    /// Segment's "Bu Rotayı Sür" button) to draw a ghost route + surface
    /// simple turn hints while recording. nil for a normal free drive.
    var guidanceTracker: RouteGuidanceTracker?

    init(locationManager: LocationManager, guidanceSegment: Segment? = nil) {
        self.locationManager = locationManager
        if let guidanceSegment {
            guidanceTracker = RouteGuidanceTracker(segment: guidanceSegment)
        }
    }

    func start() {
        // Idempotent: a redundant call (e.g. a duplicate trigger from the
        // view layer) must never wipe samples already recorded this session.
        guard timer == nil else { return }
        samples = []
        distanceMeters = 0
        elapsedTime = 0
        currentSpeedKph = 0
        startDate = Date()
        autoDetector.reset()

        locationManager.requestAlwaysAuthorizationIfNeeded()
        locationManager.onSample = { [weak self] sample in
            self?.ingest(sample)
        }
        locationManager.startRecording()
        Haptics.tripStarted()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    /// Ends recording and computes the final result. Returns nil if the trip
    /// was too short to produce meaningful stats.
    func end() -> TripResult? {
        timer?.invalidate()
        timer = nil
        locationManager.stopRecording()
        locationManager.onSample = nil

        guard samples.count > 1,
              let stats = TripStatsCalculator.calculate(samples: samples, stopEvents: autoDetector.stopEvents) else {
            return nil
        }
        let score = DrivingScoreCalculator.calculate(samples: samples, stats: stats)
        Haptics.tripEnded()
        return TripResult(samples: samples, stopEvents: autoDetector.stopEvents, stats: stats, score: score)
    }

    private func tick() {
        guard let startDate else { return }
        elapsedTime = Date().timeIntervalSince(startDate)
    }

    private func ingest(_ sample: LocationSample) {
        if let last = samples.last {
            distanceMeters += GeoMath.distanceMeters(from: last.coordinate, to: sample.coordinate)
        }
        samples.append(sample)
        currentSpeedKph = sample.speedKph
        guidanceTracker?.update(with: sample)

        autoDetector.ingest(sample)
        isStopped = autoDetector.isStopped
        showsEndSuggestion = autoDetector.shouldSuggestEnd
    }
}
