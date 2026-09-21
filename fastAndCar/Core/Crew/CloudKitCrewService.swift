//
//  CloudKitCrewService.swift
//  fastAndCar
//
//  CKShare-backed group access: each Crew gets its own custom CKRecordZone
//  (the default zone can't be shared) in the creator's private database;
//  invited members reach that same zone through CloudKit's shared
//  database once they accept. Same activation status as
//  CloudKitSegmentService — needs the iCloud/CloudKit capability added to
//  the target (see FeatureFlags.crewEnabled) and a signed-in iCloud account.
//

import CloudKit
import Foundation

enum CrewServiceError: Error {
    case featureNotAvailable
    case notSignedIntoiCloud
    case underlying(Error)
}

enum CloudKitCrewService {
    private static let crewRecordType = "Crew"
    private static let membershipRecordType = "CrewMembership"
    private static let summaryRecordType = "CrewDriveSummary"
    // Same record type names (and the same recordName/segmentId/
    // durationSeconds indexes) as CloudKitSegmentService's public-database
    // Segment/SegmentEffort — CloudKit record type schemas aren't
    // per-database, so a crew's private zone can hold its own Segment/
    // SegmentEffort records under these same types without any new schema
    // or index work.
    private static let segmentRecordType = "Segment"
    private static let effortRecordType = "SegmentEffort"

    // MARK: - Create

    /// Creates the crew's own zone + root record + CKShare in one batch,
    /// writes the creator's own CrewMembership alongside, and hands back
    /// the CKShare so the caller can present UICloudSharingController —
    /// that controller (not this service) is what actually sends the
    /// invite via Messages/Mail/copy-link.
    static func createCrew(name: String, creatorId: String, creatorNickname: String) async throws -> (crew: Crew, share: CKShare, zoneRef: CrewZoneRef) {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }

        let database = CKContainer.default().privateCloudDatabase
        let zone = CKRecordZone(zoneName: "crew-\(UUID().uuidString)")

        do {
            _ = try await database.save(zone)

            let crewId = UUID().uuidString
            let recordID = CKRecord.ID(recordName: crewId, zoneID: zone.zoneID)
            let record = CKRecord(recordType: crewRecordType, recordID: recordID)
            record["name"] = name as CKRecordValue
            record["creatorId"] = creatorId as CKRecordValue
            record["creatorNickname"] = creatorNickname as CKRecordValue
            record["createdAt"] = Date() as CKRecordValue

            let share = CKShare(rootRecord: record)
            share[CKShare.SystemFieldKey.title] = name as CKRecordValue
            // Defaults to .none — CrewInviteView hands out share.url
            // directly via QR/WhatsApp without ever routing through
            // UICloudSharingController's own permission UI, so without this
            // explicit opt-in nobody who taps the link (any delivery
            // method) can actually join.
            share.publicPermission = .readWrite

            let membershipRecord = CKRecord(recordType: membershipRecordType, recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone.zoneID))
            membershipRecord["crewId"] = crewId as CKRecordValue
            membershipRecord["userId"] = creatorId as CKRecordValue
            membershipRecord["nickname"] = creatorNickname as CKRecordValue
            membershipRecord["joinedAt"] = Date() as CKRecordValue

            _ = try await database.modifyRecords(saving: [record, share, membershipRecord], deleting: [])

            let crew = Crew(id: crewId, name: name, creatorId: creatorId, creatorNickname: creatorNickname, createdAt: record["createdAt"] as? Date ?? Date())
            let zoneRef = CrewZoneRef(zoneName: zone.zoneID.zoneName, ownerName: nil)
            return (crew, share, zoneRef)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CrewServiceError.notSignedIntoiCloud
        } catch {
            throw CrewServiceError.underlying(error)
        }
    }

    // MARK: - Accept invite

    /// Called from the app's CKShare-acceptance entry point (see
    /// fastAndCarApp's scene delegate hook) once the system has resolved a
    /// tapped invite link into share metadata. Accepts the share, then
    /// writes this device's own CrewMembership into the now-accessible zone.
    static func acceptShare(metadata: CKShare.Metadata, userId: String, nickname: String) async throws -> (crew: Crew, zoneRef: CrewZoneRef) {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }

        do {
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.acceptSharesResultBlock = { result in
                    switch result {
                    case .success: continuation.resume()
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
                CKContainer.default().add(operation)
            }

            let sharedDatabase = CKContainer.default().sharedCloudDatabase
            let rootRecordID = metadata.hierarchicalRootRecordID ?? metadata.share.recordID
            let rootRecord = try await sharedDatabase.record(for: rootRecordID)
            guard let crew = mapCrew(rootRecord) else { throw CrewServiceError.underlying(URLError(.cannotParseResponse)) }

            let zoneRef = CrewZoneRef(zoneName: rootRecordID.zoneID.zoneName, ownerName: rootRecordID.zoneID.ownerName)

            let membershipRecord = CKRecord(recordType: membershipRecordType, recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: rootRecordID.zoneID))
            membershipRecord["crewId"] = crew.id as CKRecordValue
            membershipRecord["userId"] = userId as CKRecordValue
            membershipRecord["nickname"] = nickname as CKRecordValue
            membershipRecord["joinedAt"] = Date() as CKRecordValue
            _ = try await sharedDatabase.save(membershipRecord)

            return (crew, zoneRef)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CrewServiceError.notSignedIntoiCloud
        } catch {
            throw CrewServiceError.underlying(error)
        }
    }

    // MARK: - Membership management

    /// Leaving is just deleting this device's own view of the crew's zone —
    /// CloudKit's documented way for a participant to drop a share. For the
    /// owner, deleting their own (private) zone deletes the crew for
    /// everyone, since it's the zone every participant's access is rooted in.
    static func leaveCrew(zoneRef: CrewZoneRef) async throws {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }
        do {
            _ = try await zoneRef.database.deleteRecordZone(withID: zoneRef.zoneID)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CrewServiceError.notSignedIntoiCloud
        } catch {
            throw CrewServiceError.underlying(error)
        }
    }

    /// Owner-only: revokes a specific participant's access to the CKShare,
    /// then removes their CrewMembership record so the roster reflects it
    /// immediately rather than waiting for them to notice they lost access.
    static func removeMember(crewId: String, userId: String, zoneRef: CrewZoneRef) async throws {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }
        guard zoneRef.isOwnedByThisDevice else { throw CrewServiceError.underlying(URLError(.badServerResponse)) }
        let privateDatabase = CKContainer.default().privateCloudDatabase
        do {
            let rootRecord = try await privateDatabase.record(for: CKRecord.ID(recordName: crewId, zoneID: zoneRef.zoneID))
            guard let shareReference = rootRecord.share else { return }
            let shareRecord = try await privateDatabase.record(for: shareReference.recordID)
            guard let share = shareRecord as? CKShare else { return }

            if let participant = share.participants.first(where: { $0.userIdentity.userRecordID?.recordName == userId }) {
                share.removeParticipant(participant)
                _ = try await privateDatabase.modifyRecords(saving: [share], deleting: [])
            }

            let membershipQuery = CKQuery(recordType: membershipRecordType, predicate: NSPredicate(format: "userId == %@", userId))
            let (matchResults, _) = try await privateDatabase.records(matching: membershipQuery, inZoneWith: zoneRef.zoneID)
            let idsToDelete = matchResults.compactMap { recordID, result -> CKRecord.ID? in
                guard case .success = result else { return nil }
                return recordID
            }
            if !idsToDelete.isEmpty {
                _ = try await privateDatabase.modifyRecords(saving: [], deleting: idsToDelete)
            }
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CrewServiceError.notSignedIntoiCloud
        } catch {
            throw CrewServiceError.underlying(error)
        }
    }

    static func deleteDriveSummary(id: String, zoneRef: CrewZoneRef) async throws {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }
        do {
            _ = try await zoneRef.database.deleteRecord(withID: CKRecord.ID(recordName: id, zoneID: zoneRef.zoneID))
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CrewServiceError.notSignedIntoiCloud
        } catch {
            throw CrewServiceError.underlying(error)
        }
    }

    // MARK: - Crew routes (Segment/SegmentEffort in the crew's own zone)

    /// Shares a route with this crew — writes it into the crew's own
    /// private zone (same zone Crew/CrewMembership live in), reachable by
    /// every participant through their own copy of the share, not the
    /// public Global Leaderboard.
    static func createSegment(_ segment: Segment, zoneRef: CrewZoneRef) async throws {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }
        let record = CKRecord(recordType: segmentRecordType, recordID: CKRecord.ID(recordName: segment.id, zoneID: zoneRef.zoneID))
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
            _ = try await zoneRef.database.save(record)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CrewServiceError.notSignedIntoiCloud
        } catch {
            throw CrewServiceError.underlying(error)
        }
    }

    static func fetchSegments(zoneRef: CrewZoneRef) async throws -> [Segment] {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }
        let query = CKQuery(recordType: segmentRecordType, predicate: NSPredicate(value: true))
        do {
            let (matchResults, _) = try await zoneRef.database.records(matching: query, inZoneWith: zoneRef.zoneID)
            return matchResults.compactMap { _, result in
                guard case .success(let record) = result else { return nil }
                return mapSegment(record)
            }
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CrewServiceError.notSignedIntoiCloud
        } catch {
            throw CrewServiceError.underlying(error)
        }
    }

    static func submitEffort(segmentId: String, userId: String, nickname: String, match: SegmentMatcher.Match, drivingScore: Int, zoneRef: CrewZoneRef) async throws {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }
        guard AntiCheat.isPlausible(topSpeedKph: match.topSpeedKph, averageSpeedKph: match.averageSpeedKph) else {
            throw CrewServiceError.underlying(URLError(.badServerResponse))
        }
        let record = CKRecord(recordType: effortRecordType, recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneRef.zoneID))
        record["segmentId"] = segmentId as CKRecordValue
        record["userId"] = userId as CKRecordValue
        record["nickname"] = nickname as CKRecordValue
        record["durationSeconds"] = match.durationSeconds as CKRecordValue
        record["averageSpeedKph"] = match.averageSpeedKph as CKRecordValue
        record["topSpeedKph"] = match.topSpeedKph as CKRecordValue
        record["drivingScore"] = drivingScore as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        do {
            _ = try await zoneRef.database.save(record)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CrewServiceError.notSignedIntoiCloud
        } catch {
            throw CrewServiceError.underlying(error)
        }
    }

    /// Ranked by elapsed time ascending, same as the Global Leaderboard's
    /// per-segment ranking — just scoped to this crew's own zone.
    static func fetchSegmentLeaderboard(segmentId: String, zoneRef: CrewZoneRef) async throws -> [SegmentEffort] {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }
        let predicate = NSPredicate(format: "segmentId == %@", segmentId)
        let query = CKQuery(recordType: effortRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "durationSeconds", ascending: true)]
        do {
            let (matchResults, _) = try await zoneRef.database.records(matching: query, inZoneWith: zoneRef.zoneID)
            return matchResults.compactMap { _, result in
                guard case .success(let record) = result else { return nil }
                return mapEffort(record)
            }
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CrewServiceError.notSignedIntoiCloud
        } catch {
            throw CrewServiceError.underlying(error)
        }
    }

    // MARK: - Members & summaries

    static func fetchMembers(zoneRef: CrewZoneRef) async throws -> [CrewMembership] {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }
        let query = CKQuery(recordType: membershipRecordType, predicate: NSPredicate(value: true))
        do {
            let (matchResults, _) = try await zoneRef.database.records(matching: query, inZoneWith: zoneRef.zoneID)
            return matchResults.compactMap { _, result in
                guard case .success(let record) = result else { return nil }
                return mapMembership(record)
            }
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CrewServiceError.notSignedIntoiCloud
        } catch {
            throw CrewServiceError.underlying(error)
        }
    }

    static func submitDriveSummary(_ summary: CrewDriveSummary, zoneRef: CrewZoneRef) async throws {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }
        let record = CKRecord(recordType: summaryRecordType, recordID: CKRecord.ID(recordName: summary.id, zoneID: zoneRef.zoneID))
        record["crewId"] = summary.crewId as CKRecordValue
        record["userId"] = summary.userId as CKRecordValue
        record["nickname"] = summary.nickname as CKRecordValue
        record["tripId"] = summary.tripId as CKRecordValue
        record["topSpeedKph"] = summary.topSpeedKph as CKRecordValue
        record["averageSpeedKph"] = summary.averageSpeedKph as CKRecordValue
        record["distanceMeters"] = summary.distanceMeters as CKRecordValue
        record["drivingScore"] = summary.drivingScore as CKRecordValue
        record["createdAt"] = summary.createdAt as CKRecordValue

        do {
            _ = try await zoneRef.database.save(record)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CrewServiceError.notSignedIntoiCloud
        } catch {
            throw CrewServiceError.underlying(error)
        }
    }

    /// Ranked by driving score descending — a Crew is comparing *how you
    /// drove*, not a race, so the score (which already penalizes harsh
    /// braking/erratic speed) is the fairer ranking than raw top speed.
    static func fetchDriveSummaries(zoneRef: CrewZoneRef) async throws -> [CrewDriveSummary] {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }
        let query = CKQuery(recordType: summaryRecordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        do {
            let (matchResults, _) = try await zoneRef.database.records(matching: query, inZoneWith: zoneRef.zoneID)
            return matchResults.compactMap { _, result in
                guard case .success(let record) = result else { return nil }
                return mapSummary(record)
            }
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CrewServiceError.notSignedIntoiCloud
        } catch {
            throw CrewServiceError.underlying(error)
        }
    }

    static func currentUserId() async throws -> String {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }
        do {
            return try await CKContainer.default().userRecordID().recordName
        } catch {
            throw CrewServiceError.notSignedIntoiCloud
        }
    }

    // MARK: - Mapping

    private static func mapCrew(_ record: CKRecord) -> Crew? {
        guard let name = record["name"] as? String,
              let creatorId = record["creatorId"] as? String,
              let creatorNickname = record["creatorNickname"] as? String,
              let createdAt = record["createdAt"] as? Date else { return nil }
        return Crew(id: record.recordID.recordName, name: name, creatorId: creatorId, creatorNickname: creatorNickname, createdAt: createdAt)
    }

    private static func mapMembership(_ record: CKRecord) -> CrewMembership? {
        guard let crewId = record["crewId"] as? String,
              let userId = record["userId"] as? String,
              let nickname = record["nickname"] as? String,
              let joinedAt = record["joinedAt"] as? Date else { return nil }
        return CrewMembership(id: record.recordID.recordName, crewId: crewId, userId: userId, nickname: nickname, joinedAt: joinedAt)
    }

    /// Mirrors CloudKitSegmentService's own mapSegment — same record shape,
    /// just read out of a crew's private zone instead of the public
    /// database.
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

    private static func mapSummary(_ record: CKRecord) -> CrewDriveSummary? {
        guard let crewId = record["crewId"] as? String,
              let userId = record["userId"] as? String,
              let nickname = record["nickname"] as? String,
              let tripId = record["tripId"] as? String,
              let topSpeedKph = record["topSpeedKph"] as? Double,
              let averageSpeedKph = record["averageSpeedKph"] as? Double,
              let distanceMeters = record["distanceMeters"] as? Double,
              let drivingScore = record["drivingScore"] as? Int,
              let createdAt = record["createdAt"] as? Date else { return nil }
        return CrewDriveSummary(
            id: record.recordID.recordName,
            crewId: crewId,
            userId: userId,
            nickname: nickname,
            tripId: tripId,
            topSpeedKph: topSpeedKph,
            averageSpeedKph: averageSpeedKph,
            distanceMeters: distanceMeters,
            drivingScore: drivingScore,
            createdAt: createdAt
        )
    }
}
