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
        case .authorizedAlways: String.appLocalized("Her zaman izinli")
        case .authorizedWhenInUse: String.appLocalized("Yalnızca uygulama kullanılırken")
        case .denied: String.appLocalized("Reddedildi")
        case .restricted: String.appLocalized("Kısıtlı")
        case .notDetermined: String.appLocalized("Belirlenmedi")
        @unknown default: String.appLocalized("Bilinmiyor")
        }
    }

    var authorizationIsGranted: Bool {
        locationManager.hasUsableAuthorization
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

