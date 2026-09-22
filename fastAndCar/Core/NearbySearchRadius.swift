//
//  NearbySearchRadius.swift
//  fastAndCar
//
//  Settings preference for how far GlobalLeaderboardListView's
//  "Yakınımdakiler" search looks. The coarse-geohash candidate grid
//  (CloudKitSegmentService.fetchNearbySegmentsWide) is sized to match
//  whichever radius is selected (see loadNearby), then a real-distance
//  filter is applied on top of those candidates.
//

import Foundation

enum NearbySearchRadius: Int, CaseIterable, Identifiable {
    case km25 = 25
    case km50 = 50
    case km100 = 100
    case km200 = 200

    var id: Int { rawValue }
    var meters: Double { Double(rawValue) * 1000 }
    var label: String { "\(rawValue) km" }
}
