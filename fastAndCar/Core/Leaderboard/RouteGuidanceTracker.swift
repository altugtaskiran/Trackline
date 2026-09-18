//
//  RouteGuidanceTracker.swift
//  fastAndCar
//
//  Live "am I still on this segment, what's the next turn" state, fed one
//  GPS sample at a time while a drive is being recorded. Progress only ever
//  moves forward along the segment's polyline (never regresses on GPS
//  jitter), which is also how it decides the segment is done — reaching
//  its last stretch, not literally touching the final point.
//

import CoreLocation
import Foundation
import Observation

@Observable
final class RouteGuidanceTracker {
    let segment: Segment

    private(set) var nextTurn: TurnInstruction?
    private(set) var distanceToNextTurnMeters: Double?
    private(set) var isCompleted = false
    /// Flips true the moment a sample lands within `startLineThresholdMeters`
    /// of the segment's own first point — this, not "Sürüşe Başla", is the
    /// clock's real zero so a comparison against the creator's own time is
    /// apples-to-apples regardless of how early the driver started recording.
    private(set) var hasStarted = false
    private(set) var startTimestamp: Date?
    /// Live while the attempt is running, frozen at the value it held the
    /// instant `isCompleted` flipped.
    private(set) var elapsedSeconds: TimeInterval?

    private let coordinates: [CLLocationCoordinate2D]
    private let turns: [TurnInstruction]
    private var progressIndex = 0

    /// How far ahead of the current progress point to look for a closer
    /// match — wide enough to absorb a GPS jump forward, narrow enough that
    /// a momentary bad fix doesn't snap progress way down the route.
    private static let searchWindow = 20
    private static let arrivalThresholdMeters = 30.0
    private static let startLineThresholdMeters = 30.0

    init(segment: Segment) {
        self.segment = segment
        coordinates = segment.polyline.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        turns = RouteGuidance.turnInstructions(for: segment)
        nextTurn = turns.first
    }

    func update(with sample: LocationSample) {
        guard !coordinates.isEmpty else { return }

        if !hasStarted, let start = coordinates.first,
           GeoMath.distanceMeters(from: sample.coordinate, to: start) <= Self.startLineThresholdMeters {
            hasStarted = true
            startTimestamp = sample.timestamp
        }

        let searchEnd = min(progressIndex + Self.searchWindow, coordinates.count)
        var bestIndex = progressIndex
        var bestDistance = GeoMath.distanceMeters(from: sample.coordinate, to: coordinates[progressIndex])
        for index in progressIndex..<searchEnd {
            let distance = GeoMath.distanceMeters(from: sample.coordinate, to: coordinates[index])
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        progressIndex = max(progressIndex, bestIndex)

        if let upcoming = turns.first(where: { $0.index > progressIndex }) {
            nextTurn = upcoming
            distanceToNextTurnMeters = GeoMath.distanceMeters(from: sample.coordinate, to: upcoming.coordinate)
        } else {
            nextTurn = nil
            distanceToNextTurnMeters = nil
        }

        if let startTimestamp, !isCompleted {
            elapsedSeconds = sample.timestamp.timeIntervalSince(startTimestamp)
        }

        if !isCompleted, progressIndex >= coordinates.count - 2 {
            isCompleted = true
        }
    }

    var instructionText: String? {
        if isCompleted { return completionText }
        guard let nextTurn, let distanceToNextTurnMeters else { return nil }
        let directionText = nextTurn.direction == .left ? String.appLocalized("soldan dön") : String.appLocalized("sağdan dön")
        if distanceToNextTurnMeters < Self.arrivalThresholdMeters {
            return String.appLocalized("Şimdi ") + directionText
        }
        return String(format: String.appLocalized("%.0fm sonra %@"), distanceToNextTurnMeters, directionText)
    }

    /// "You vs. the creator" the instant the attempt finishes — no
    /// leaderboard fetch needed, `segment.creatorDurationSeconds` was baked
    /// in when the route was created.
    private var completionText: String {
        guard let elapsedSeconds else { return String.appLocalized("Rotayı tamamladın!") }
        let elapsedText = Self.formatElapsed(elapsedSeconds)
        guard segment.creatorDurationSeconds > 0 else {
            return String(format: String.appLocalized("Rotayı tamamladın! Süren: %@"), elapsedText)
        }
        let delta = elapsedSeconds - segment.creatorDurationSeconds
        let deltaText = Self.formatElapsed(abs(delta))
        if delta <= 0 {
            return String(format: String.appLocalized("Rotayı tamamladın! Süren: %@ — %@'i %@ farkla geçtin!"), elapsedText, segment.creatorNickname, deltaText)
        }
        return String(format: String.appLocalized("Rotayı tamamladın! Süren: %@ — %@'den %@ geride"), elapsedText, segment.creatorNickname, deltaText)
    }

    private static func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
