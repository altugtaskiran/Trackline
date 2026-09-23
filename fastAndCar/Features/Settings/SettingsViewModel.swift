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

    /// True once the user has already answered the permission prompt with
    /// "While Using" — iOS only shows its own "upgrade to Always" system
    /// dialog once per app; after that, requestAlwaysAuthorization() is a
    /// silent no-op forever, so this case can only be corrected from the
    /// system Settings app, not from anywhere in-app.
    var needsAlwaysUpgrade: Bool {
        locationManager.authorizationStatus == .authorizedWhenInUse
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

