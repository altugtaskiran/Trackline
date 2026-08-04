//
//  LeaderboardModels.swift
//  fastAndCar
//
//  App-facing leaderboard types, decoupled from CloudKit's CKRecord so nothing
//  outside CloudKitLeaderboardService needs to import CloudKit directly.
//

import Foundation

struct LeaderboardPolylinePoint: Codable {
    let lat: Double
    let lon: Double
}

enum LeaderboardPolylineCodec {
    /// Downsampled to keep the CloudKit record small — a leaderboard route
    /// thumbnail doesn't need every 1Hz sample, just its shape.
    static let maxPoints = 120

    static func encode(samples: [LocationSample]) -> Data? {
        guard !samples.isEmpty else { return nil }
        let step = max(1, samples.count / maxPoints)
        let downsampled = Swift.stride(from: 0, to: samples.count, by: step).map { samples[$0] }
        let points = downsampled.map { LeaderboardPolylinePoint(lat: $0.latitude, lon: $0.longitude) }
        return try? JSONEncoder().encode(points)
    }

    static func decode(_ data: Data) -> [LeaderboardPolylinePoint] {
        (try? JSONDecoder().decode([LeaderboardPolylinePoint].self, from: data)) ?? []
    }
}

struct LeaderboardEntry: Identifiable, Equatable {
    let id: String
    let nickname: String
    let topSpeedKph: Double
    let averageSpeedKph: Double
    let driveTime: TimeInterval
    let distanceMeters: Double
    let polyline: [LeaderboardPolylinePoint]
    let createdAt: Date

    static func == (lhs: LeaderboardEntry, rhs: LeaderboardEntry) -> Bool { lhs.id == rhs.id }
}
