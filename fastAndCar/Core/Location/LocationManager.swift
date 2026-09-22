//
//  LocationManager.swift
//  fastAndCar
//
//  Thin, app-facing wrapper around CLLocationManager. Owns permission state
//  and the recording session; hands cleaned-up LocationSamples to whoever is
//  recording via `onSample`. No SwiftUI dependency — pure service layer.
//

import CoreLocation
import Foundation
import Observation

@Observable
final class LocationManager: NSObject {
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var latestSample: LocationSample?
    private(set) var isRecording = false
    /// Independent of `isRecording` — crew presence-sharing keeps location
    /// updates flowing (so `latestSample` stays fresh for
    /// CrewPresenceBroadcaster to read) even when no trip is being
    /// recorded. Coarser accuracy than recording's, since "roughly where a
    /// friend is" doesn't need navigation-grade precision.
    private(set) var isBroadcastingPresence = false

    /// Called on the main actor for every accepted, smoothed sample while recording.
    var onSample: ((LocationSample) -> Void)?

    private let manager = CLLocationManager()
    private let smoothing = LocationSmoothing()
    private var lastAcceptedTimestamp: Date?
    /// Throttles raw CoreLocation callbacks down to ~1 sample/second, per spec.
    private let minSampleInterval: TimeInterval = 1.0

    /// Fulfilled by the next `didUpdateLocations`/`didFailWithError` callback
    /// after `requestOneShotLocation` — independent of the continuous
    /// recording session (`isRecording`/`onSample`), so a "find segments
    /// near me" lookup never touches trip-recording state.
    private var oneShotCompletion: ((CLLocationCoordinate2D?) -> Void)?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.distanceFilter = kCLDistanceFilterNone
    }

    /// Call from Onboarding. Starts with When-In-Use; Always is requested lazily
    /// when the user actually starts a drive, matching Apple's recommended flow.
    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorizationIfNeeded() {
        guard authorizationStatus == .authorizedWhenInUse else { return }
        manager.requestAlwaysAuthorization()
    }

    var hasUsableAuthorization: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    func startRecording() {
        guard hasUsableAuthorization else { return }
        smoothing.reset()
        lastAcceptedTimestamp = nil
        isRecording = true
        refreshLocationUpdatesState()
    }

    func stopRecording() {
        isRecording = false
        refreshLocationUpdatesState()
    }

    /// Called from CrewPresenceBroadcaster while the Settings toggle is on
    /// and the app is foregrounded — keeps `latestSample` updating even
    /// when not recording a trip, independent of and compatible with an
    /// active recording session (recording's accuracy always wins if both
    /// are on at once).
    func startBroadcastingPresence() {
        guard hasUsableAuthorization else { return }
        isBroadcastingPresence = true
        refreshLocationUpdatesState()
    }

    func stopBroadcastingPresence() {
        isBroadcastingPresence = false
        refreshLocationUpdatesState()
    }

    private func refreshLocationUpdatesState() {
        // Presence-only accuracy was kCLLocationAccuracyHundredMeters /
        // 50m filter — coarse enough that iOS was batching background
        // updates minutes apart (confirmed live: long silent gaps between
        // crew map updates). Tightened to reduce that lag; costs more
        // battery than before, but still well short of recording's
        // navigation-grade settings.
        manager.desiredAccuracy = isRecording ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = isRecording ? kCLDistanceFilterNone : 15

        guard isRecording || isBroadcastingPresence else {
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
            return
        }
        // Presence-sharing now keeps working while backgrounded too (user
        // explicitly asked for "uygulama arkada olsa bile") — needs Always
        // authorization, requested separately when the Settings toggle is
        // switched on (see AppRootView). Falls back to foreground-only if
        // the user only granted When-In-Use, same as recording always has.
        manager.allowsBackgroundLocationUpdates = (isRecording || isBroadcastingPresence) && authorizationStatus == .authorizedAlways
        manager.showsBackgroundLocationIndicator = isRecording || isBroadcastingPresence
        manager.startUpdatingLocation()
    }

    /// A single current-location fix for "what's nearby" lookups (Global
    /// Leaderboard's segment discovery) — not a recording session, so it
    /// never flips `isRecording` or touches `onSample`.
    func requestOneShotLocation(completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        guard hasUsableAuthorization else {
            completion(nil)
            return
        }
        oneShotCompletion = completion
        manager.requestLocation()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        // Always-authorization can arrive after recording/broadcasting has
        // already started (the system prompt is async) — without this,
        // allowsBackgroundLocationUpdates stays stuck at whatever it was
        // computed as at start() time, silently breaking background
        // tracking for the rest of the session even after the user grants it.
        if isRecording || isBroadcastingPresence {
            refreshLocationUpdatesState()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        if let oneShotCompletion {
            self.oneShotCompletion = nil
            oneShotCompletion(location.coordinate)
        }

        let timestamp = location.timestamp

        if let last = lastAcceptedTimestamp, timestamp.timeIntervalSince(last) < minSampleInterval {
            return
        }
        lastAcceptedTimestamp = timestamp

        let smoothedCoordinate = smoothing.filter(
            coordinate: location.coordinate,
            horizontalAccuracy: location.horizontalAccuracy,
            at: timestamp
        )

        let sample = LocationSample(
            coordinate: smoothedCoordinate,
            timestamp: timestamp,
            speedMps: location.speed,
            altitude: location.altitude,
            heading: location.course >= 0 ? location.course : nil,
            horizontalAccuracy: location.horizontalAccuracy
        )

        latestSample = sample
        if isRecording {
            onSample?(sample)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        oneShotCompletion?(nil)
        oneShotCompletion = nil
    }
}
