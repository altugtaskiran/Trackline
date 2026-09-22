//
//  NearbySearchRadius.swift
//  fastAndCar
//
//  Settings preference for how far GlobalLeaderboardListView's
//  "Yakınımdakiler" search looks — the underlying coarse-geohash query
//  (CloudKitSegmentService.fetchNearbySegmentsWide) always fetches the same
//  ~100km-wide candidate set (a fixed 3x3 coarse-cell grid), so narrowing
//  this just applies a real-distance filter on top of those candidates —
//  cheap, no extra CloudKit round-trip for a smaller radius.
//

import Foundation

enum NearbySearchRadius: Int, CaseIterable, Identifiable {
    case km10 = 10
    case km25 = 25
    case km50 = 50
    case km100 = 100

    var id: Int { rawValue }
    var meters: Double { Double(rawValue) * 1000 }
    var label: String { "\(rawValue) km" }
}
