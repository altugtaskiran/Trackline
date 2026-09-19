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
    static func fetchNearbySegments(candidateGeohashes: [String]) async throws -> [Segment] {
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
            return segments.sorted { $0.voteCount > $1.voteCount }
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

    static func hasVoted(segmentId: String, userId: String) async throws -> Bool {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        let predicate = NSPredicate(format: "segmentId == %@ AND userId == %@", segmentId, userId)
        let query = CKQuery(recordType: voteRecordType, predicate: predicate)
        do {
            let (matchResults, _) = try await database.records(matching: query)
            return !matchResults.isEmpty
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
            let voteRecord = CKRecord(recordType: voteRecordType)
            voteRecord["segmentId"] = segmentId as CKRecordValue
            voteRecord["userId"] = userId as CKRecordValue
            voteRecord["createdAt"] = Date() as CKRecordValue
            _ = try await database.save(voteRecord)

            let segmentRecord = try await database.record(for: CKRecord.ID(recordName: segmentId))
            let currentVotes = segmentRecord["voteCount"] as? Int ?? 0
            segmentRecord["voteCount"] = (currentVotes + 1) as CKRecordValue
            _ = try await database.save(segmentRecord)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
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

    static func submitEffort(segmentId: String, userId: String, nickname: String, match: SegmentMatcher.Match, drivingScore: Int) async throws {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        guard AntiCheat.isPlausible(topSpeedKph: match.topSpeedKph, averageSpeedKph: match.averageSpeedKph) else {
            throw SegmentServiceError.implausibleEffort
        }
        guard AntiCheat.canSubmitNow() else {
            throw SegmentServiceError.rateLimited
        }

        let record = CKRecord(recordType: effortRecordType)
        record["segmentId"] = segmentId as CKRecordValue
        record["userId"] = userId as CKRecordValue
        record["nickname"] = nickname as CKRecordValue
        record["durationSeconds"] = match.durationSeconds as CKRecordValue
        record["averageSpeedKph"] = match.averageSpeedKph as CKRecordValue
        record["topSpeedKph"] = match.topSpeedKph as CKRecordValue
        record["drivingScore"] = drivingScore as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue

        do {
            _ = try await database.save(record)
            AntiCheat.recordSubmission()
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
