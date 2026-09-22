//
//  Segment.swift
//  fastAndCar
//
//  A user-defined stretch of road, named and bounded by the creator (not
//  auto-derived the way the older start/end-rounding leaderboard is) — the
//  CloudKit-facing shape mirrors LeaderboardEntry's pattern of staying a
//  plain Codable struct so nothing outside CloudKitSegmentService needs to
//  import CloudKit.
//

import CoreLocation
import Foundation

struct Segment: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var creatorId: String
    var creatorNickname: String
    var polyline: [RoutePolylinePoint]
    var minLatitude: Double
    var minLongitude: Double
    var maxLatitude: Double
    var maxLongitude: Double
    /// How far (meters) a candidate trip's samples may stray from this
    /// segment's line and still count as "drove it" — wide enough to
    /// absorb GPS drift and lane choice, tight enough that a parallel
    /// service road doesn't match.
    var toleranceMeters: Double
    /// Average compass heading along the segment, start to end — a trip
    /// covering the same coordinates in the *opposite* direction (or on a
    /// crossing road) must not match.
    var bearingDegrees: Double
    var geohashes: [String]
    var createdAt: Date
    /// How long the creator's own recorded pass took, start to end — the
    /// baseline every later "Bu Rotayı Sür" attempt races against. Baked in
    /// at creation time (not derived from SegmentEffort) so a live guided
    /// drive can show "you vs. the creator" the instant it finishes, with no
    /// CloudKit leaderboard fetch required.
    var creatorDurationSeconds: Double
    /// Upvotes from other drivers — "this is a good/popular route", not a
    /// SegmentEffort ranking. Search/nearby results sort by this so the
    /// routes people actually rate highly surface first.
    var voteCount: Int

    static func == (lhs: Segment, rhs: Segment) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var startCoordinate: CLLocationCoordinate2D? {
        polyline.first.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    var endCoordinate: CLLocationCoordinate2D? {
        polyline.last.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    /// Where the Home map's discovery layer places this route's tap
    /// target (RouteDiscoveryOverlay) — the geometric middle of the
    /// recorded points, not a true midpoint-by-distance, but close enough
    /// to land visually on the line for any reasonably-shaped route.
    var midpointCoordinate: CLLocationCoordinate2D? {
        guard !polyline.isEmpty else { return nil }
        let point = polyline[polyline.count / 2]
        return CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
    }

    var lengthMeters: Double {
        guard polyline.count > 1 else { return 0 }
        var total = 0.0
        for index in 1..<polyline.count {
            let a = CLLocationCoordinate2D(latitude: polyline[index - 1].lat, longitude: polyline[index - 1].lon)
            let b = CLLocationCoordinate2D(latitude: polyline[index].lat, longitude: polyline[index].lon)
            total += GeoMath.distanceMeters(from: a, to: b)
        }
        return total
    }

    /// Builds a new segment from a sub-range of an existing trip's samples —
    /// the shape produced by the "Bu rotadan segment oluştur" flow, where
    /// the user picks a start/end index on their own recorded route rather
    /// than drawing one from scratch.
    static func fromTripRange(
        samples: [LocationSample],
        startIndex: Int,
        endIndex: Int,
        name: String,
        creatorId: String,
        creatorNickname: String,
        toleranceMeters: Double = 25
    ) -> Segment? {
        guard startIndex < endIndex, endIndex < samples.count else { return nil }
        let range = samples[startIndex...endIndex]
        guard range.count > 1 else { return nil }

        let points = range.map { RoutePolylinePoint(lat: $0.latitude, lon: $0.longitude) }
        let coordinates = range.map(\.coordinate)
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        guard let first = coordinates.first, let last = coordinates.last,
              let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else { return nil }

        return Segment(
            id: UUID().uuidString,
            name: name,
            creatorId: creatorId,
            creatorNickname: creatorNickname,
            polyline: points,
            minLatitude: minLat,
            minLongitude: minLon,
            maxLatitude: maxLat,
            maxLongitude: maxLon,
            toleranceMeters: toleranceMeters,
            bearingDegrees: GeoMath.bearingDegrees(from: first, to: last),
            geohashes: Geohash.cells(for: coordinates),
            createdAt: Date(),
            creatorDurationSeconds: samples[endIndex].timestamp.timeIntervalSince(samples[startIndex].timestamp),
            voteCount: 0
        )
    }
}
