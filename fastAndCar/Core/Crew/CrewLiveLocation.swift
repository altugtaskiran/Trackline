//
//  CrewLiveLocation.swift
//  fastAndCar
//

import CoreLocation
import Foundation

struct CrewLiveLocation: Identifiable, Equatable {
    let userId: String
    let latitude: Double
    let longitude: Double
    let updatedAt: Date

    var id: String { userId }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Presence is derived from freshness, not a separate flag — a stale
    /// write just ages out on its own instead of needing an explicit
    /// "offline" write when the app backgrounds or the toggle turns off.
    var isActive: Bool {
        Date().timeIntervalSince(updatedAt) < 60
    }
}

/// A crewmate's position + display name, ready to render on the driving
/// map (DashboardView) — trimmed down from CrewLiveLocation + the roster
/// lookup that supplies the nickname it doesn't carry on its own.
struct CrewMapMarker: Identifiable, Equatable {
    let userId: String
    let nickname: String
    let coordinate: CLLocationCoordinate2D

    var id: String { userId }

    static func == (lhs: CrewMapMarker, rhs: CrewMapMarker) -> Bool {
        lhs.userId == rhs.userId && lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}
