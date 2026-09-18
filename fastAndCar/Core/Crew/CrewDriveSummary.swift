//
//  CrewDriveSummary.swift
//  fastAndCar
//
//  One member's finished drive, as seen by the rest of the Crew — never the
//  live route or position, just the same headline numbers Trip Detail
//  already shows (top speed, average speed, distance, score). Written only
//  when the driver explicitly opts in for that specific trip at share time.
//

import Foundation

struct CrewDriveSummary: Identifiable, Codable {
    let id: String
    var crewId: String
    var userId: String
    var nickname: String
    var tripId: String
    var topSpeedKph: Double
    var averageSpeedKph: Double
    var distanceMeters: Double
    var drivingScore: Int
    var createdAt: Date
}
