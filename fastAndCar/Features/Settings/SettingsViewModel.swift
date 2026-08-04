//
//  SettingsViewModel.swift
//  fastAndCar
//

import CoreLocation
import Observation

@Observable
final class SettingsViewModel {
    private let locationManager: LocationManager

    init(locationManager: LocationManager) {
        self.locationManager = locationManager
    }

    var authorizationStatusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways: "Her zaman izinli"
        case .authorizedWhenInUse: "Yalnızca uygulama kullanılırken"
        case .denied: "Reddedildi"
        case .restricted: "Kısıtlı"
        case .notDetermined: "Belirlenmedi"
        @unknown default: "Bilinmiyor"
        }
    }

    var authorizationIsGranted: Bool {
        locationManager.hasUsableAuthorization
    }

    var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
