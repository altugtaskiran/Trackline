//
//  CloudKitSegmentService.swift
//  fastAndCar
//
//  Public-database CloudKit access for user-defined Segments and their
//  SegmentEfforts (the Global Leaderboard). Needs the iCloud/CloudKit
//  capability + entitlement (not yet added to the target — see
//  FeatureFlags) and a signed-in iCloud account to actually read/write.
//

import CloudKit
import CoreLocation
import Foundation

enum SegmentServiceError: Error {
    /// The CloudKit/iCloud capability hasn't been added to the app target
    /// yet (see FeatureFlags.globalLeaderboardEnabled) — distinct from the
    /// user's own iCloud sign-in state so the UI can say the right thing.
    case featureNotAvailable
    case notSignedIntoiCloud
    case rateLimited
    case implausibleEffort
    case underlying(Error)
}

// Without this, Swift's default `.localizedDescription` bridging collapses
// every case to a useless generic "The operation couldn't be completed
// (fastAndCar.SegmentServiceError error N.)" — every silent `try?` around a
// CloudKitSegmentService call this session (Yakınımdakiler's loadNearby
// included) has been hiding the real CKError text (missing Production
// index, permission error, query-too-complex, etc.) behind "found nothing"
// for exactly this reason. Matches the same fix already applied to
// CrewServiceError earlier this session.
extension SegmentServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .featureNotAvailable: "Bu özellik bu derlemede kapalı."
        case .notSignedIntoiCloud: "iCloud hesabına giriş yapılmamış."
        case .rateLimited: "Çok sık deneme yapıldı, biraz sonra tekrar dene."
        case .implausibleEffort: "Bu sürüş verisi geçersiz görünüyor."
        case .underlying(let error): error.localizedDescription
        }
    }
}

enum CloudKitSegmentService {
    private static let segmentRecordType = "Segment"
    private static let effortRecordType = "SegmentEffort"
    private static let voteRecordType = "SegmentVote"
    private static var database: CKDatabase { CKContainer.default().publicCloudDatabase }

    // MARK: - Segments

    static func createSegment(_ segment: Segment) async throws {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        let record = CKRecord(recordType: segmentRecordType, recordID: CKRecord.ID(recordName: segment.id))
        record["name"] = segment.name as CKRecordValue
        record["creatorId"] = segment.creatorId as CKRecordValue
        record["creatorNickname"] = segment.creatorNickname as CKRecordValue
        record["minLatitude"] = segment.minLatitude as CKRecordValue
        record["minLongitude"] = segment.minLongitude as CKRecordValue
        record["maxLatitude"] = segment.maxLatitude as CKRecordValue
        record["maxLongitude"] = segment.maxLongitude as CKRecordValue
        record["toleranceMeters"] = segment.toleranceMeters as CKRecordValue
        record["bearingDegrees"] = segment.bearingDegrees as CKRecordValue
        record["geohashes"] = segment.geohashes as CKRecordValue
        record["geohashesCoarse"] = segment.geohashesCoarse as CKRecordValue
        record["createdAt"] = segment.createdAt as CKRecordValue
        record["voteCount"] = segment.voteCount as CKRecordValue
        record["creatorDurationSeconds"] = segment.creatorDurationSeconds as CKRecordValue
        if let polylineData = try? JSONEncoder().encode(segment.polyline) {
            record["polyline"] = polylineData as CKRecordValue
        }

        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    /// Mirrors createSegment — deleting a route locally (RoutesTabView)
    /// should take it off the public Global Leaderboard too, the same
    /// best-effort way it got published there in the first place. Not an
    /// error if the record was never actually published (e.g. it predates
    /// CloudKit going live, or the toggle was off) — CKError.unknownItem is
    /// swallowed as a no-op by the caller via `try?`.
    static func deleteSegment(id: String) async throws {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        do {
            _ = try await database.deleteRecord(withID: CKRecord.ID(recordName: id))
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    /// Pre-filtered by geohash cell, not distance — the public database has
    /// no native geo query, so this is a coarse "could plausibly be nearby"
    /// pass; SegmentMatcher does the real distance/bearing check afterward.
    /// `minVoteCount`/`limit` exist for the Home map's route-discovery
    /// layer (RouteDiscoveryOverlay) — showing every low-effort/unrated
    /// segment on the map would clutter it fast, so that caller passes a
    /// real threshold. Defaults (0, unlimited) preserve every existing
    /// caller's behavior (Global Leaderboard's "nearby" search, which
    /// should still surface brand-new routes).
    static func fetchNearbySegments(candidateGeohashes: [String], minVoteCount: Int = 0, limit: Int = Int.max) async throws -> [Segment] {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        guard !candidateGeohashes.isEmpty else { return [] }
        let predicate = NSPredicate(format: "ANY geohashes IN %@", candidateGeohashes)
        let query = CKQuery(recordType: segmentRecordType, predicate: predicate)

        do {
            let (matchResults, _) = try await database.records(matching: query)
            let segments = matchResults.compactMap { _, result -> Segment? in
                guard case .success(let record) = result else { return nil }
                return mapSegment(record)
            }
            let filtered = segments.filter { $0.voteCount >= minVoteCount }.sorted { $0.voteCount > $1.voteCount }
            return Array(filtered.prefix(limit))
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    /// Whole-metro-area "nearby" — same index-backed geohash pre-filter as
    /// fetchNearbySegments, but against the coarser `geohashesCoarse` tags
    /// (precision-4, ~39km × 19.5km cells) so a real city-sized radius (a
    /// 3×3 neighbor grid around the searcher, via Geohash.nearbyCells at
    /// coarsePrecision) stays a cheap handful of candidate cells instead of
    /// thousands. This is what loadNearby (Global Leaderboard's
    /// "Yakınımdakiler") should call — fetchNearbySegments' precision-6
    /// cells only reach ~1-2km, too tight for browsing a whole city.
    static func fetchNearbySegmentsWide(candidateCoarseGeohashes: [String], minVoteCount: Int = 0, limit: Int = Int.max) async throws -> [Segment] {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        guard !candidateCoarseGeohashes.isEmpty else { return [] }
        let predicate = NSPredicate(format: "ANY geohashesCoarse IN %@", candidateCoarseGeohashes)
        let query = CKQuery(recordType: segmentRecordType, predicate: predicate)

        do {
            // Without a resultsLimit, this fetched every matching record's
            // full data (including each Segment's whole polyline) before
            // ever applying the caller's `limit` — at a wide radius (a
            // few hundred candidate cells), that's what made
            // "Yakınımdakiler" both slow and, sometimes, silently fail
            // outright (confirmed live: "çok uzun sürüyor ve bazen
            // yüklenmiyor bile"). Capping it server-side fixes both.
            let (matchResults, _) = try await database.records(matching: query, resultsLimit: limit == Int.max ? 200 : min(limit, 200))
            let segments = matchResults.compactMap { _, result -> Segment? in
                guard case .success(let record) = result else { return nil }
                return mapSegment(record)
            }
            let filtered = segments.filter { $0.voteCount >= minVoteCount }.sorted { $0.voteCount > $1.voteCount }
            return Array(filtered.prefix(limit))
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    /// Test-only widening of "nearby": the geohash grid in
    /// fetchNearbySegments is precision-6 cells (~1-2km total reach) and
    /// scaling that grid out to a real 30km radius would mean thousands of
    /// candidate cells in one predicate — impractical. This instead fetches
    /// every public Segment and filters by actual great-circle distance
    /// from each segment's bounding-box center, which is exact and fine at
    /// today's small test-data scale. Not meant to replace
    /// fetchNearbySegments once there are enough public segments that
    /// fetching all of them stops being cheap.
    static func fetchSegments(within radiusMeters: Double, of coordinate: CLLocationCoordinate2D) async throws -> [Segment] {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        let query = CKQuery(recordType: segmentRecordType, predicate: NSPredicate(value: true))
        let center = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        do {
            let (matchResults, _) = try await database.records(matching: query)
            let segments = matchResults.compactMap { _, result -> Segment? in
                guard case .success(let record) = result else { return nil }
                return mapSegment(record)
            }
            return segments.filter { segment in
                let segmentCenter = CLLocation(
                    latitude: (segment.minLatitude + segment.maxLatitude) / 2,
                    longitude: (segment.minLongitude + segment.maxLongitude) / 2
                )
                return center.distance(from: segmentCenter) <= radiusMeters
            }.sorted { $0.voteCount > $1.voteCount }
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    /// Sorted by vote count descending — the best-rated matches for the
    /// searched name surface first, not just whatever order CloudKit
    /// happened to return them in.
    static func searchSegments(nameContains text: String) async throws -> [Segment] {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        let predicate = NSPredicate(format: "name CONTAINS[cd] %@", text)
        let query = CKQuery(recordType: segmentRecordType, predicate: predicate)

        do {
            let (matchResults, _) = try await database.records(matching: query)
            let segments = matchResults.compactMap { _, result -> Segment? in
                guard case .success(let record) = result else { return nil }
                return mapSegment(record)
            }
            return segments.sorted { $0.voteCount > $1.voteCount }
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    // MARK: - Voting

    /// One vote record per (segment, user), recordName = "segmentId_userId"
    /// so it's a direct-by-ID lookup — not a CKQuery. CloudKit queries have
    /// repeatedly proven unreliable in this container (see
    /// CloudKitProfileService's header comment for the full story); a
    /// deterministic ID sidesteps that entirely for both checking and
    /// removing a vote.
    private static func voteRecordID(segmentId: String, userId: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(segmentId)_\(userId)")
    }

    static func hasVoted(segmentId: String, userId: String) async throws -> Bool {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        do {
            _ = try await database.record(for: voteRecordID(segmentId: segmentId, userId: userId))
            return true
        } catch let error as CKError where error.code == .unknownItem {
            return false
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    /// Records this device's vote, then bumps the Segment's own cached
    /// `voteCount` via a fetch-increment-save — not atomic, so a handful of
    /// simultaneous votes on the same segment could under-count by one or
    /// two, an acceptable trade for not needing a server-side function.
    static func voteForSegment(segmentId: String, userId: String) async throws {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        guard try await !hasVoted(segmentId: segmentId, userId: userId) else { return }

        do {
            let voteRecord = CKRecord(recordType: voteRecordType, recordID: voteRecordID(segmentId: segmentId, userId: userId))
            voteRecord["segmentId"] = segmentId as CKRecordValue
            voteRecord["userId"] = userId as CKRecordValue
            voteRecord["createdAt"] = Date() as CKRecordValue
            _ = try await database.save(voteRecord)
            try await adjustVoteCount(segmentId: segmentId, by: 1)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    /// Undo — deletes this device's vote record and decrements the
    /// Segment's cached voteCount (clamped at 0 inside adjustVoteCount).
    static func unvoteSegment(segmentId: String, userId: String) async throws {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        do {
            _ = try? await database.deleteRecord(withID: voteRecordID(segmentId: segmentId, userId: userId))
            try await adjustVoteCount(segmentId: segmentId, by: -1)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    /// Fetch-increment-save on a Segment's voteCount isn't atomic — two
    /// people voting on the same popular route around the same moment can
    /// race, and CloudKit's own optimistic-concurrency check
    /// (CKError.serverRecordChanged) then rejects the second save even
    /// though the vote record itself already saved fine. Without a retry,
    /// that surfaced as a scary "check your connection" failure on a vote
    /// that actually went through (confirmed as a plausible cause of the
    /// intermittent "bağlandı ama hata verdi" reports). Re-fetching and
    /// retrying a few times resolves the race instead of failing on it.
    private static func adjustVoteCount(segmentId: String, by delta: Int) async throws {
        var attempt = 0
        while true {
            do {
                let segmentRecord = try await database.record(for: CKRecord.ID(recordName: segmentId))
                let currentVotes = segmentRecord["voteCount"] as? Int ?? 0
                segmentRecord["voteCount"] = max(0, currentVotes + delta) as CKRecordValue
                _ = try await database.save(segmentRecord)
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                attempt += 1
                if attempt >= 3 { throw error }
            }
        }
    }

    static func fetchSegment(id: String) async throws -> Segment? {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: id))
            return mapSegment(record)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    // MARK: - Efforts

    /// One row per (segment, user) — recordName is deterministic so a
    /// second, better run overwrites the same row instead of piling up a
    /// duplicate leaderboard entry for the same person. "effort_" prefix
    /// keeps it from colliding with voteRecordID's own "segmentId_userId"
    /// scheme (different record type, but CloudKit record IDs are unique
    /// per database+zone regardless of type — see CloudKitProfileService's
    /// header comment for how that bit us before).
    private static func effortRecordID(segmentId: String, userId: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "effort_\(segmentId)_\(userId)")
    }

    static func submitEffort(segmentId: String, userId: String, nickname: String, match: SegmentMatcher.Match, drivingScore: Int) async throws {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        guard AntiCheat.isPlausible(topSpeedKph: match.topSpeedKph, averageSpeedKph: match.averageSpeedKph) else {
            throw SegmentServiceError.implausibleEffort
        }
        guard AntiCheat.canSubmitNow() else {
            throw SegmentServiceError.rateLimited
        }

        let recordID = effortRecordID(segmentId: segmentId, userId: userId)
        do {
            if let existing = try? await database.record(for: recordID),
               let existingDuration = existing["durationSeconds"] as? Double,
               existingDuration <= match.durationSeconds {
                // Already have an equal-or-better time on this segment —
                // nothing to do, keep the existing row as-is.
                return
            }

            let record = (try? await database.record(for: recordID)) ?? CKRecord(recordType: effortRecordType, recordID: recordID)
            record["segmentId"] = segmentId as CKRecordValue
            record["userId"] = userId as CKRecordValue
            record["nickname"] = nickname as CKRecordValue
            record["durationSeconds"] = match.durationSeconds as CKRecordValue
            record["averageSpeedKph"] = match.averageSpeedKph as CKRecordValue
            record["topSpeedKph"] = match.topSpeedKph as CKRecordValue
            record["drivingScore"] = drivingScore as CKRecordValue
            record["createdAt"] = Date() as CKRecordValue
            _ = try await database.save(record)
            AntiCheat.recordSubmission()
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    /// The `nickname` on every SegmentEffort is a denormalized copy, baked
    /// in at submission time — a later nickname change otherwise leaves old
    /// leaderboard rows showing the stale name forever (confirmed live).
    /// Called from ProfileView.saveNickname() alongside syncHandle, best-effort.
    /// NOTE: needs a queryable index on SegmentEffort.userId in Console —
    /// unlike segmentId (already queried by fetchLeaderboard above), userId
    /// has never been queried on this record type before.
    static func updateMyNicknameOnEfforts(userId: String, nickname: String) async throws {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        let predicate = NSPredicate(format: "userId == %@", userId)
        let query = CKQuery(recordType: effortRecordType, predicate: predicate)
        do {
            let (matchResults, _) = try await database.records(matching: query)
            let updates: [CKRecord] = matchResults.compactMap { _, result in
                guard case .success(let record) = result else { return nil }
                record["nickname"] = nickname as CKRecordValue
                return record
            }
            guard !updates.isEmpty else { return }
            _ = try await database.modifyRecords(saving: updates, deleting: [])
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    /// Ranked by elapsed time ascending — fastest clear of the segment wins.
    static func fetchLeaderboard(segmentId: String) async throws -> [SegmentEffort] {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        let predicate = NSPredicate(format: "segmentId == %@", segmentId)
        let query = CKQuery(recordType: effortRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "durationSeconds", ascending: true)]

        do {
            let (matchResults, _) = try await database.records(matching: query)
            return matchResults.compactMap { _, result in
                guard case .success(let record) = result else { return nil }
                return mapEffort(record)
            }
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    static func currentUserId() async throws -> String {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        do {
            return try await CKContainer.default().userRecordID().recordName
        } catch {
            throw SegmentServiceError.notSignedIntoiCloud
        }
    }

    // MARK: - Mapping

    private static func mapSegment(_ record: CKRecord) -> Segment? {
        guard let name = record["name"] as? String,
              let creatorId = record["creatorId"] as? String,
              let creatorNickname = record["creatorNickname"] as? String,
              let minLatitude = record["minLatitude"] as? Double,
              let minLongitude = record["minLongitude"] as? Double,
              let maxLatitude = record["maxLatitude"] as? Double,
              let maxLongitude = record["maxLongitude"] as? Double,
              let toleranceMeters = record["toleranceMeters"] as? Double,
              let bearingDegrees = record["bearingDegrees"] as? Double,
              let geohashes = record["geohashes"] as? [String],
              let createdAt = record["createdAt"] as? Date,
              let polylineData = record["polyline"] as? Data,
              let polyline = try? JSONDecoder().decode([RoutePolylinePoint].self, from: polylineData) else { return nil }

        return Segment(
            id: record.recordID.recordName,
            name: name,
            creatorId: creatorId,
            creatorNickname: creatorNickname,
            polyline: polyline,
            minLatitude: minLatitude,
            minLongitude: minLongitude,
            maxLatitude: maxLatitude,
            maxLongitude: maxLongitude,
            toleranceMeters: toleranceMeters,
            bearingDegrees: bearingDegrees,
            geohashes: geohashes,
            geohashesCoarse: record["geohashesCoarse"] as? [String] ?? [],
            createdAt: createdAt,
            creatorDurationSeconds: record["creatorDurationSeconds"] as? Double ?? 0,
            voteCount: record["voteCount"] as? Int ?? 0
        )
    }

    private static func mapEffort(_ record: CKRecord) -> SegmentEffort? {
        guard let segmentId = record["segmentId"] as? String,
              let userId = record["userId"] as? String,
              let nickname = record["nickname"] as? String,
              let durationSeconds = record["durationSeconds"] as? Double,
              let averageSpeedKph = record["averageSpeedKph"] as? Double,
              let topSpeedKph = record["topSpeedKph"] as? Double,
              let drivingScore = record["drivingScore"] as? Int,
              let createdAt = record["createdAt"] as? Date else { return nil }

        return SegmentEffort(
            id: record.recordID.recordName,
            segmentId: segmentId,
            userId: userId,
            nickname: nickname,
            durationSeconds: durationSeconds,
            averageSpeedKph: averageSpeedKph,
            topSpeedKph: topSpeedKph,
            drivingScore: drivingScore,
            createdAt: createdAt
        )
    }
}
