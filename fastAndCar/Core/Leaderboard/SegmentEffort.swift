//
//  SegmentEffort.swift
//  fastAndCar
//
//  One completed pass through a Segment's corridor — the leaderboard row.
//  Ranked by elapsed time (fastest clear wins), the standard segment-
//  leaderboard semantic, rather than top speed (which rewards a single
//  fast moment, not actually covering the segment quickly).
//

import Foundation

struct SegmentEffort: Identifiable, Codable, Equatable {
    let id: String
    var segmentId: String
    var userId: String
    var nickname: String
    var durationSeconds: TimeInterval
    var averageSpeedKph: Double
    var topSpeedKph: Double
    var drivingScore: Int
    var createdAt: Date

    static func == (lhs: SegmentEffort, rhs: SegmentEffort) -> Bool { lhs.id == rhs.id }
}
