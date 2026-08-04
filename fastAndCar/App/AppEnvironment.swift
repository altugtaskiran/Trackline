//
//  AppEnvironment.swift
//  fastAndCar
//
//  Shared, app-lifetime services. One LocationManager instance so a trip
//  recording in progress survives navigation between screens.
//

import Foundation
import Observation

@Observable
final class AppEnvironment {
    let locationManager = LocationManager()

    private static let onboardingKey = "hasCompletedOnboarding"

    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.onboardingKey) }
    }

    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
    }
}
