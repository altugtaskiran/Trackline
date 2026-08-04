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

    /// Called on the main actor for every accepted, smoothed sample while recording.
    var onSample: ((LocationSample) -> Void)?

    private let manager = CLLocationManager()
    private let smoothing = LocationSmoothing()
    private var lastAcceptedTimestamp: Date?
    /// Throttles raw CoreLocation callbacks down to ~1 sample/second, per spec.
    private let minSampleInterval: TimeInterval = 1.0

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
        manager.allowsBackgroundLocationUpdates = authorizationStatus == .authorizedAlways
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func stopRecording() {
        isRecording = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
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
}
