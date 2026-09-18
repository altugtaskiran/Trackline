//
//  LeaderboardModels.swift
//  fastAndCar
//
//  Shared polyline point type — used wherever a route needs to travel over
//  CloudKit as plain, decoupled data (Segment's stored route, CrewDriveSummary
//  in future, etc.) without every call site importing CloudKit directly.
//

import Foundation

struct RoutePolylinePoint: Codable {
    let lat: Double
    let lon: Double
}
