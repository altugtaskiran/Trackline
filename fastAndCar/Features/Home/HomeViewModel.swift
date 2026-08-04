//
//  HomeViewModel.swift
//  fastAndCar
//

import Observation

@Observable
final class HomeViewModel {
    private let locationManager: LocationManager
    var showsPermissionAlert = false

    init(locationManager: LocationManager) {
        self.locationManager = locationManager
    }

    func startTripTapped(onAuthorized: () -> Void) {
        guard locationManager.hasUsableAuthorization else {
            showsPermissionAlert = true
            return
        }
        Haptics.tripStarted()
        onAuthorized()
    }
}
