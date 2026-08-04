//
//  SegmentKey.swift
//  fastAndCar
//
//  Automatic route-segment grouping: trips are matched into the same
//  leaderboard segment purely by rounding their start/end coordinates to a
//  shared grid — no manual naming. ~3 decimal places is roughly a 110m
//  cell, forgiving enough that GPS noise or a slightly different parking
//  spot still matches the same real-world drive, tight enough that
//  distinct routes don't collide.
//

import CoreLocation
import Foundation

enum SegmentKey {
    static func make(startCoordinate: CLLocationCoordinate2D, endCoordinate: CLLocationCoordinate2D) -> String {
        func rounded(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }
        let startLat = rounded(startCoordinate.latitude)
        let startLon = rounded(startCoordinate.longitude)
        let endLat = rounded(endCoordinate.latitude)
        let endLon = rounded(endCoordinate.longitude)
        return "\(startLat),\(startLon)-\(endLat),\(endLon)"
    }

    static func make(for trip: Trip) -> String? {
        guard let start = trip.samples.first, let end = trip.samples.last else { return nil }
        return make(startCoordinate: start.coordinate, endCoordinate: end.coordinate)
    }
}
