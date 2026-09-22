//
//  Geohash.swift
//  fastAndCar
//
//  Standard base32 geohash encoding. CloudKit's public database can't do a
//  native "within N meters" geo query, so segments are tagged with the
//  geohash cells their route passes through; a new trip's own cells become
//  an "ANY geohashes IN %@" predicate — a cheap index-backed pre-filter
//  before the expensive point-to-polyline matching in SegmentMatcher.
//

import CoreLocation
import Foundation
import MapKit

enum Geohash {
    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    /// Precision 6 ≈ 1.2km × 0.6km cells — tight enough to keep candidate
    /// lists small, loose enough that a segment's cells and a same-route
    /// trip's cells reliably overlap despite GPS noise.
    static let defaultPrecision = 6

    static func encode(latitude: Double, longitude: Double, precision: Int = defaultPrecision) -> String {
        var latRange = (min: -90.0, max: 90.0)
        var lonRange = (min: -180.0, max: 180.0)
        var isEvenBit = true
        var bit = 0
        var characterIndex = 0
        var hash = ""

        while hash.count < precision {
            if isEvenBit {
                let mid = (lonRange.min + lonRange.max) / 2
                if longitude >= mid {
                    characterIndex = characterIndex * 2 + 1
                    lonRange.min = mid
                } else {
                    characterIndex *= 2
                    lonRange.max = mid
                }
            } else {
                let mid = (latRange.min + latRange.max) / 2
                if latitude >= mid {
                    characterIndex = characterIndex * 2 + 1
                    latRange.min = mid
                } else {
                    characterIndex *= 2
                    latRange.max = mid
                }
            }
            isEvenBit.toggle()

            bit += 1
            if bit == 5 {
                hash.append(base32[characterIndex])
                bit = 0
                characterIndex = 0
            }
        }
        return hash
    }

    static func encode(_ coordinate: CLLocationCoordinate2D, precision: Int = defaultPrecision) -> String {
        encode(latitude: coordinate.latitude, longitude: coordinate.longitude, precision: precision)
    }

    /// Every cell a route/bounding-box touches, downsampled to keep the
    /// CloudKit record's tag list small — a segment only needs enough cells
    /// to be *findable*, not one per sample.
    static func cells(for coordinates: [CLLocationCoordinate2D], precision: Int = defaultPrecision) -> [String] {
        guard !coordinates.isEmpty else { return [] }
        let step = max(1, coordinates.count / 40)
        var seen = Set<String>()
        var result: [String] = []
        for index in Swift.stride(from: 0, to: coordinates.count, by: step) {
            let cell = encode(coordinates[index], precision: precision)
            if seen.insert(cell).inserted {
                result.append(cell)
            }
        }
        return result
    }

    /// The single point's own cell plus its ring of 8 neighbors — a rough
    /// (not bit-exact) 3×3 grid centered on the user, wide enough that
    /// "segments near me" still finds routes a couple kilometers off
    /// without needing the real geohash neighbor-cell algorithm.
    static func nearbyCells(around coordinate: CLLocationCoordinate2D, precision: Int = defaultPrecision) -> [String] {
        let cellHeightMeters = 610.0
        let cellWidthMeters = 1220.0
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = 111_320.0 * cos(coordinate.latitude * .pi / 180)
        let latDelta = cellHeightMeters / metersPerDegreeLatitude
        let lonDelta = cellWidthMeters / max(metersPerDegreeLongitude, 1)

        var seen = Set<String>()
        var result: [String] = []
        for dLat in [-1.0, 0.0, 1.0] {
            for dLon in [-1.0, 0.0, 1.0] {
                let point = CLLocationCoordinate2D(
                    latitude: coordinate.latitude + dLat * latDelta,
                    longitude: coordinate.longitude + dLon * lonDelta
                )
                let cell = encode(point, precision: precision)
                if seen.insert(cell).inserted {
                    result.append(cell)
                }
            }
        }
        return result
    }

    /// Every precision-6 cell touching the given map region — used to load
    /// nearby routes as the Home map's viewport changes (RouteDiscoveryOverlay),
    /// generalizing nearbyCells' fixed 3×3 grid to an arbitrary rectangle.
    /// Capped at `maxCells`: a zoomed-way-out region would otherwise expand
    /// to a predicate with thousands of candidates — callers should treat a
    /// nil result as "too zoomed out, ask the user to zoom in" rather than
    /// firing a giant query.
    static func cells(covering region: MKCoordinateRegion, precision: Int = defaultPrecision, maxCells: Int = 60) -> [String]? {
        let cellHeightMeters = 610.0
        let cellWidthMeters = 1220.0
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = 111_320.0 * cos(region.center.latitude * .pi / 180)
        let latStep = cellHeightMeters / metersPerDegreeLatitude
        let lonStep = cellWidthMeters / max(metersPerDegreeLongitude, 1)

        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2

        let latSteps = max(1, Int((maxLat - minLat) / latStep) + 1)
        let lonSteps = max(1, Int((maxLon - minLon) / lonStep) + 1)
        guard latSteps * lonSteps <= maxCells else { return nil }

        var seen = Set<String>()
        var result: [String] = []
        for latIndex in 0..<latSteps {
            for lonIndex in 0..<lonSteps {
                let point = CLLocationCoordinate2D(
                    latitude: minLat + Double(latIndex) * latStep,
                    longitude: minLon + Double(lonIndex) * lonStep
                )
                let cell = encode(point, precision: precision)
                if seen.insert(cell).inserted {
                    result.append(cell)
                }
            }
        }
        return result
    }
}
