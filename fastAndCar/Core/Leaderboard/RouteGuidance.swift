//
//  RouteGuidance.swift
//  fastAndCar
//
//  Turns a Segment's stored polyline into a short list of turn instructions
//  — no MapKit routing/rerouting, no voice: just "the bearing changed by
//  enough, here, and here's which way" markers a live tracker can compare
//  against the driver's actual position. Text-only, simple-navigation-cue
//  guidance, not a real turn-by-turn nav engine.
//

import CoreLocation
import Foundation

enum TurnDirection {
    case left
    case right
}

struct TurnInstruction: Identifiable {
    let id = UUID()
    let index: Int
    let coordinate: CLLocationCoordinate2D
    let direction: TurnDirection
    let distanceFromStartMeters: Double
}

enum RouteGuidance {
    /// Below this bearing change (degrees), a bend in the road isn't worth
    /// calling out — it'd fire constantly on every gentle curve.
    private static let turnAngleThresholdDegrees = 25.0
    /// Minimum spacing between called-out turns — avoids flagging every
    /// point of a tight, winding stretch as its own separate instruction.
    private static let minGapMeters = 80.0

    static func turnInstructions(for segment: Segment) -> [TurnInstruction] {
        let coordinates = segment.polyline.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        guard coordinates.count > 2 else { return [] }

        var result: [TurnInstruction] = []
        var cumulativeDistance = 0.0
        var lastTurnDistance = -Double.greatestFiniteMagnitude

        for index in 1..<(coordinates.count - 1) {
            cumulativeDistance += GeoMath.distanceMeters(from: coordinates[index - 1], to: coordinates[index])

            let bearingIn = GeoMath.bearingDegrees(from: coordinates[index - 1], to: coordinates[index])
            let bearingOut = GeoMath.bearingDegrees(from: coordinates[index], to: coordinates[index + 1])
            var diff = (bearingOut - bearingIn).truncatingRemainder(dividingBy: 360)
            if diff > 180 { diff -= 360 }
            if diff < -180 { diff += 360 }

            guard abs(diff) >= turnAngleThresholdDegrees else { continue }
            guard cumulativeDistance - lastTurnDistance >= minGapMeters else { continue }

            result.append(TurnInstruction(
                index: index,
                coordinate: coordinates[index],
                direction: diff > 0 ? .right : .left,
                distanceFromStartMeters: cumulativeDistance
            ))
            lastTurnDistance = cumulativeDistance
        }
        return result
    }
}
