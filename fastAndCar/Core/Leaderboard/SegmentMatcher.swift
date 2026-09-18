//
//  SegmentMatcher.swift
//  fastAndCar
//
//  Decides whether a completed trip actually drove a given Segment's
//  corridor, and if so, which contiguous sub-range of the trip's samples
//  covers it — the effort's time/speed are computed from just that
//  sub-range, not the whole drive, so a segment on a longer trip still
//  gets a fair (short) time.
//

import CoreLocation
import Foundation

enum SegmentMatcher {
    struct Match {
        let startIndex: Int
        let endIndex: Int
        let durationSeconds: TimeInterval
        let averageSpeedKph: Double
        let topSpeedKph: Double
    }

    /// A segment point counts as "covered" once some trip sample passes
    /// within `tolerance` of it — resampling the segment's own polyline
    /// (rather than walking every trip sample against every segment point)
    /// keeps this O(segment points × trip samples) instead of quadratic in
    /// the trip's full 1Hz sample count.
    private static let coverageThreshold = 0.85
    private static let bearingToleranceDegrees = 45.0

    static func match(trip samples: [LocationSample], against segment: Segment) -> Match? {
        guard samples.count > 1, segment.polyline.count > 1 else { return nil }

        let segmentCoordinates = segment.polyline.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        var firstTripIndex: Int?
        var lastTripIndex: Int?
        var coveredCount = 0

        for segmentPoint in segmentCoordinates {
            guard let (nearestIndex, distance) = nearestSample(to: segmentPoint, in: samples) else { continue }
            guard distance <= segment.toleranceMeters else { continue }
            coveredCount += 1
            if firstTripIndex == nil || nearestIndex < firstTripIndex! { firstTripIndex = nearestIndex }
            if lastTripIndex == nil || nearestIndex > lastTripIndex! { lastTripIndex = nearestIndex }
        }

        let coverage = Double(coveredCount) / Double(segmentCoordinates.count)
        guard coverage >= coverageThreshold,
              let startIndex = firstTripIndex, let endIndex = lastTripIndex,
              startIndex < endIndex else { return nil }

        let tripBearing = GeoMath.bearingDegrees(from: samples[startIndex].coordinate, to: samples[endIndex].coordinate)
        guard angularDifference(tripBearing, segment.bearingDegrees) <= bearingToleranceDegrees else { return nil }

        let duration = samples[endIndex].timestamp.timeIntervalSince(samples[startIndex].timestamp)
        guard duration > 0 else { return nil }

        let subRange = samples[startIndex...endIndex]
        let topSpeedKph = subRange.map(\.speedKph).max() ?? 0
        var distanceMeters = 0.0
        for index in (startIndex + 1)...endIndex {
            distanceMeters += GeoMath.distanceMeters(from: samples[index - 1].coordinate, to: samples[index].coordinate)
        }
        let averageSpeedKph = duration > 0 ? (distanceMeters / duration) * 3.6 : 0

        return Match(
            startIndex: startIndex,
            endIndex: endIndex,
            durationSeconds: duration,
            averageSpeedKph: averageSpeedKph,
            topSpeedKph: topSpeedKph
        )
    }

    private static func nearestSample(to point: CLLocationCoordinate2D, in samples: [LocationSample]) -> (index: Int, distanceMeters: Double)? {
        var best: (index: Int, distance: Double)?
        for (index, sample) in samples.enumerated() {
            let distance = GeoMath.distanceMeters(from: point, to: sample.coordinate)
            if best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        return best.map { ($0.index, $0.distance) }
    }

    private static func angularDifference(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(diff, 360 - diff)
    }
}
