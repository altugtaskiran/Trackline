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
    private static let inviteRequestRecordType = "CrewInviteRequest"
    private static var publicDatabase: CKDatabase { CKContainer.default().publicCloudDatabase }

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
            // Without a parent link to the Crew record, this membership
            // record isn't part of the shared hierarchy — invited
            // participants querying the zone via their own shared database
            // can't see it (they only see records that ARE linked), even
            // though the owner always has full, unconditional access to
            // their own private zone regardless of parent.
            membershipRecord.parent = CKRecord.Reference(recordID: recordID, action: .none)
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
            let rootRecord: CKRecord
            do {
                rootRecord = try await sharedDatabase.record(for: rootRecordID)
            } catch {
                throw CrewServiceError.underlying(NSError(domain: "AcceptShare.readRoot", code: 0, userInfo: [NSUnderlyingErrorKey: error]))
            }
            guard let crew = mapCrew(rootRecord) else { throw CrewServiceError.underlying(URLError(.cannotParseResponse)) }

            let zoneRef = CrewZoneRef(zoneName: rootRecordID.zoneID.zoneName, ownerName: rootRecordID.zoneID.ownerName)

            let membershipRecord = CKRecord(recordType: membershipRecordType, recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: rootRecordID.zoneID))
            // Without this, CloudKit doesn't recognize the new record as
            // part of the shared hierarchy rooted at the Crew record — a
            // readWrite participant's CREATE gets rejected for anything
            // that isn't linked to the share root, even though the zone
            // itself is shared to them with write access.
            membershipRecord.parent = CKRecord.Reference(recordID: rootRecordID, action: .none)
            membershipRecord["crewId"] = crew.id as CKRecordValue
            membershipRecord["userId"] = userId as CKRecordValue
            membershipRecord["nickname"] = nickname as CKRecordValue
            membershipRecord["joinedAt"] = Date() as CKRecordValue
            do {
                _ = try await sharedDatabase.save(membershipRecord)
            } catch {
                throw CrewServiceError.underlying(NSError(domain: "AcceptShare.writeMembership", code: 0, userInfo: [NSUnderlyingErrorKey: error]))
            }

            return (crew, zoneRef)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CrewServiceError.notSignedIntoiCloud
        } catch {
            throw CrewServiceError.underlying(error)
        }
    }

    // MARK: - Invite by name

    /// Explicitly adds a known user (by their CloudKit userId, found via
    /// CloudKitProfileService.findUser) as a real, named CKShare.Participant
    /// with readWrite — rather than relying on them "walking in" through
    /// share.publicPermission when they accept the link. That publicPermission
    /// path turned out to grant read access but NOT create/write access to
    /// new records in the shared zone (confirmed live: CrewMembership writes
    /// failed with "CREATE operation not permitted" even after a successful
    /// accept). An explicitly named participant with .readWrite is the
    /// standard, fully-supported CloudKit sharing pattern and doesn't have
    /// that gap. Must run on the crew owner's device (only the share's
    /// owner/manager can add participants) — called right before sending
    /// the CrewInviteRequest, so by the time it's accepted, real write
    /// access is already in place.
    static func addParticipant(userId: String, to share: CKShare) async throws {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }
        let lookupInfo = CKUserIdentity.LookupInfo(userRecordID: CKRecord.ID(recordName: userId))

        do {
            let participant: CKShare.Participant = try await withCheckedThrowingContinuation { continuation in
                let operation = CKFetchShareParticipantsOperation(userIdentityLookupInfos: [lookupInfo])
                var found: CKShare.Participant?
                operation.perShareParticipantResultBlock = { _, result in
                    if case .success(let participant) = result { found = participant }
                }
                operation.fetchShareParticipantsResultBlock = { result in
                    switch result {
                    case .success:
                        if let found { continuation.resume(returning: found) }
                        else { continuation.resume(throwing: URLError(.cannotParseResponse)) }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                CKContainer.default().add(operation)
            }
            participant.permission = .readWrite
            share.addParticipant(participant)
            _ = try await CKContainer.default().privateCloudDatabase.save(share)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CrewServiceError.notSignedIntoiCloud
        } catch {
            throw CrewServiceError.underlying(error)
        }
    }

    /// Looks up the CKShare a given crew's members already join through —
    /// same lookup CrewDetailView.presentInvite does for the QR/link sheet,
    /// factored out so the by-name invite flow can attach its own
    /// CrewInviteRequest to the exact same share.url.
    static func fetchShare(crewId: String, zoneRef: CrewZoneRef) async throws -> CKShare {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }
        do {
            let rootRecord = try await zoneRef.database.record(for: CKRecord.ID(recordName: crewId, zoneID: zoneRef.zoneID))
            guard let shareReference = rootRecord.share else { throw CrewServiceError.underlying(URLError(.badServerResponse)) }
            let shareRecord = try await zoneRef.database.record(for: shareReference.recordID)
            guard let share = shareRecord as? CKShare else { throw CrewServiceError.underlying(URLError(.badServerResponse)) }
            return share
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CrewServiceError.notSignedIntoiCloud
        } catch let error as CrewServiceError {
            throw error
        } catch {
            throw CrewServiceError.underlying(error)
        }
    }

    /// Sent to a specific person by their known CloudKit userId (found via
    /// CloudKitProfileService.findUser) rather than handing out share.url
    /// as a raw link — the recipient sees this as a "Kabul Et" request
    /// inside the app instead of tapping an external link.
    /// recordID is deterministic (crewId+targetUserId), not a random UUID —
    /// re-inviting the same person to the same crew overwrites their one
    /// existing pending invite instead of stacking up duplicates in their
    /// inbox every time "Davet Gönder" gets tapped again.
    static func sendInviteRequest(crewId: String, crewName: String, shareURL: URL, fromNickname: String, targetUserId: String) async throws {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }
        let recordID = CKRecord.ID(recordName: "\(crewId)_\(targetUserId)")
        let record = (try? await publicDatabase.record(for: recordID)) ?? CKRecord(recordType: inviteRequestRecordType, recordID: recordID)
        record["crewId"] = crewId as CKRecordValue
        record["crewName"] = crewName as CKRecordValue
        record["shareURL"] = shareURL.absoluteString as CKRecordValue
        record["fromNickname"] = fromNickname as CKRecordValue
        record["targetUserId"] = targetUserId as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        do {
            _ = try await publicDatabase.save(record)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CrewServiceError.notSignedIntoiCloud
        } catch {
            throw CrewServiceError.underlying(error)
        }
    }

    /// Every request addressed to this user — there's no separate
    /// "pending/accepted" status field to filter on; accepting or declining
    /// deletes the record (see respond(to:)), so anything found here is by
    /// definition still open.
    static func fetchPendingInvites(userId: String) async throws -> [CrewInviteRequest] {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }
        let predicate = NSPredicate(format: "targetUserId == %@", userId)
        let query = CKQuery(recordType: inviteRequestRecordType, predicate: predicate)
        do {
            let (matchResults, _) = try await publicDatabase.records(matching: query)
            return matchResults.compactMap { _, result in
                guard case .success(let record) = result else { return nil }
                return mapInviteRequest(record)
            }
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CrewServiceError.notSignedIntoiCloud
        } catch {
            throw CrewServiceError.underlying(error)
        }
    }

    /// Accepting fetches the CKShare's metadata straight through the
    /// CloudKit API (CKFetchShareMetadataOperation over the URL stored in
    /// the invite record) instead of iOS's system share-link handoff —
    /// that's the whole point of this flow: it never touches the "does the
    /// App Store have a newer version" check that link taps go through,
    /// because nothing here opens a URL, it's a pure API call from inside
    /// the already-running app.
    static func acceptInviteRequest(_ invite: CrewInviteRequest, userId: String, nickname: String) async throws -> (crew: Crew, zoneRef: CrewZoneRef) {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }
        guard let url = URL(string: invite.shareURL) else { throw CrewServiceError.underlying(URLError(.badURL)) }

        do {
            let metadata: CKShare.Metadata = try await withCheckedThrowingContinuation { continuation in
                let operation = CKFetchShareMetadataOperation(shareURLs: [url])
                var result: CKShare.Metadata?
                operation.perShareMetadataResultBlock = { _, metadataResult in
                    if case .success(let metadata) = metadataResult { result = metadata }
                }
                operation.fetchShareMetadataResultBlock = { opResult in
                    switch opResult {
                    case .success:
                        if let result {
                            continuation.resume(returning: result)
                        } else {
                            continuation.resume(throwing: URLError(.cannotParseResponse))
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                CKContainer.default().add(operation)
            }

            let (crew, zoneRef) = try await acceptShare(metadata: metadata, userId: userId, nickname: nickname)
            try? await publicDatabase.deleteRecord(withID: CKRecord.ID(recordName: invite.id))
            return (crew, zoneRef)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CrewServiceError.notSignedIntoiCloud
        } catch {
            throw CrewServiceError.underlying(error)
        }
    }

    static func declineInviteRequest(_ invite: CrewInviteRequest) async throws {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }
        do {
            _ = try await publicDatabase.deleteRecord(withID: CKRecord.ID(recordName: invite.id))
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
    static func createSegment(_ segment: Segment, crewId: String, zoneRef: CrewZoneRef) async throws {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }
        let record = CKRecord(recordType: segmentRecordType, recordID: CKRecord.ID(recordName: segment.id, zoneID: zoneRef.zoneID))
        // Same "must be linked to the share root" requirement as
        // CrewMembership — a joined (non-owner) participant creating a
        // Segment here without this parent reference gets the same silent
        // "CREATE operation not permitted" rejection.
        record.parent = CKRecord.Reference(recordID: CKRecord.ID(recordName: crewId, zoneID: zoneRef.zoneID), action: .none)
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

    static func submitEffort(segmentId: String, crewId: String, userId: String, nickname: String, match: SegmentMatcher.Match, drivingScore: Int, zoneRef: CrewZoneRef) async throws {
        guard FeatureFlags.crewEnabled else { throw CrewServiceError.featureNotAvailable }
        guard AntiCheat.isPlausible(topSpeedKph: match.topSpeedKph, averageSpeedKph: match.averageSpeedKph) else {
            throw CrewServiceError.underlying(URLError(.badServerResponse))
        }
        let record = CKRecord(recordType: effortRecordType, recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneRef.zoneID))
        record.parent = CKRecord.Reference(recordID: CKRecord.ID(recordName: crewId, zoneID: zoneRef.zoneID), action: .none)
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

    private static func mapInviteRequest(_ record: CKRecord) -> CrewInviteRequest? {
        guard let crewId = record["crewId"] as? String,
              let crewName = record["crewName"] as? String,
              let shareURL = record["shareURL"] as? String,
              let fromNickname = record["fromNickname"] as? String,
              let targetUserId = record["targetUserId"] as? String,
              let createdAt = record["createdAt"] as? Date else { return nil }
        return CrewInviteRequest(
            id: record.recordID.recordName,
            crewId: crewId,
            crewName: crewName,
            shareURL: shareURL,
            fromNickname: fromNickname,
            targetUserId: targetUserId,
            createdAt: createdAt
        )
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
