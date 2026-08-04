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
}
