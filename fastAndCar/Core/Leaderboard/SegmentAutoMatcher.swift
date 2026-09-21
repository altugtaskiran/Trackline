//
//  SegmentAutoMatcher.swift
//  fastAndCar
//
//  Runs once per saved trip: pre-filters nearby Segments by geohash, checks
//  each with SegmentMatcher, and submits a SegmentEffort for every match.
//  Best-effort and silent — no-op when the feature flag is off, no nickname
//  has been set yet (that's the real "opted in" signal: nothing goes out
//  under your name until you've actually picked one, no separate hidden
//  Settings toggle to find first), or CloudKit isn't reachable (offline,
//  not signed into iCloud). Never blocks or surfaces errors to the
//  trip-save flow that calls it.
import Foundation

enum SegmentAutoMatcher {
    static func run(for trip: Trip) async {
        guard FeatureFlags.globalLeaderboardEnabled else { return }

        let samples = trip.samples
        guard samples.count > 1 else { return }

        let nickname = UserDefaults.standard.string(forKey: "leaderboardNickname") ?? ""
        guard !nickname.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        LocalNotifier.requestAuthorizationIfNeeded()

        do {
            let candidateCells = Geohash.cells(for: samples.map(\.coordinate))
            let candidates = try await CloudKitSegmentService.fetchNearbySegments(candidateGeohashes: candidateCells)
            guard !candidates.isEmpty else { return }

            let userId = try await CloudKitSegmentService.currentUserId()
            var matchedNames: [String] = []
            for segment in candidates {
                guard let match = SegmentMatcher.match(trip: samples, against: segment) else { continue }
                do {
                    try await CloudKitSegmentService.submitEffort(
                        segmentId: segment.id,
                        userId: userId,
                        nickname: nickname,
                        match: match,
                        drivingScore: trip.drivingScoreValue
                    )
                    matchedNames.append(segment.name)
                    DrivenSegmentsStore().record(id: segment.id, name: segment.name)
                } catch {
                    continue
                }
            }
            LocalNotifier.notifySegmentMatches(names: matchedNames)
        } catch {
            // Offline / not signed into iCloud / feature not yet activated
            // for this build — none of that should interrupt saving a trip.
        }
    }
}
