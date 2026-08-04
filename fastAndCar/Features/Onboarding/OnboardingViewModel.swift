//
//  OnboardingViewModel.swift
//  fastAndCar
//

import CoreLocation
import Observation

@Observable
final class OnboardingViewModel {
    private let locationManager: LocationManager
    private let onFinished: () -> Void

    var authorizationStatus: CLAuthorizationStatus { locationManager.authorizationStatus }

    init(locationManager: LocationManager, onFinished: @escaping () -> Void) {
        self.locationManager = locationManager
        self.onFinished = onFinished
    }

    func requestPermission() {
        Haptics.light()
        locationManager.requestWhenInUseAuthorization()
    }

    func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        guard status != .notDetermined else { return }
        onFinished()
    }
}
