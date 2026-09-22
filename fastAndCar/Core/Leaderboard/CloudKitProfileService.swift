//
//  CloudKitProfileService.swift
//  fastAndCar
//
//  Public-database profile photos, one UserProfile record per user keyed by
//  their own CloudKit userId (same identity SegmentEffort.userId already
//  uses). Reads go through database.records(for:) — a plain batch fetch by
//  known record ID, not a CKQuery — so no "recordName not marked queryable"
//  index is needed, unlike the Segment/Effort record types.
//

import CloudKit
import Foundation

enum CloudKitProfileService {
    // Lowercase — matches the record type name as it was actually created
    // in CloudKit Console (record type names are case-sensitive and, once
    // deployed to Production, can never be renamed or deleted).
    private static let profileRecordType = "userProfile"
    // CKQuery over userProfile's nickname/tag fields proved unreliable in
    // this container — Console's own unfiltered "list all" query and the
    // app's own compound-predicate query both came back empty even though
    // direct record(for:) fetches of the exact same records succeeded
    // (proven via read-back right after every write). Rather than keep
    // fighting CKQuery, handle lookup goes through this second record
    // type instead: recordName IS the handle itself ("nickname_tag",
    // lowercased), so finding someone is a plain by-ID fetch — the same
    // mechanism already proven solid for photos and profile read-back —
    // no query, no index, nothing that can silently misbehave.
    private static let handleIndexRecordType = "HandleIndex"
    // One record per nickname (recordName = nickname.lowercased(), no tag —
    // several people can share a nickname), holding parallel `tags`/
    // `userIds` list fields for everyone currently using it. Same by-ID
    // fetch approach as HandleIndex: looking someone up by nickname alone
    // (no #tag) reads this one record instead of querying, then the caller
    // disambiguates client-side if it comes back with more than one entry.
    private static let nicknameIndexRecordType = "NicknameIndex"
    private static var database: CKDatabase { CKContainer.default().publicCloudDatabase }

    // CRITICAL: never use a bare `userId` as a record ID in the public
    // database's default zone. `userId` (from CloudKitSegmentService.
    // currentUserId()) IS `CKContainer.default().userRecordID().recordName`
    // — i.e. it's already the ID of that account's own CloudKit-managed
    // "Users" system record. `database.record(for:)` matches by ID alone,
    // regardless of type, so a bare-userId lookup silently returns and then
    // overwrites that system record instead of a separate "userProfile"
    // record (confirmed in testing: our fields were landing on "Users" in
    // Console, not "userProfile"). This prefix guarantees our record's ID
    // can never collide with a real user record ID.
    private static func profileRecordID(for userId: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "profile_" + userId)
    }

    private static func handleKey(nickname: String, tag: Int) -> String {
        nickname.trimmingCharacters(in: .whitespaces).lowercased() + "_" + String(tag)
    }

    private static func nicknameKey(_ nickname: String) -> String {
        nickname.trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func uploadMyPhoto(data: Data) async throws {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        let userId = try await CloudKitSegmentService.currentUserId()

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let recordID = profileRecordID(for: userId)
        let record = (try? await database.record(for: recordID)) ?? CKRecord(recordType: profileRecordType, recordID: recordID)
        record["photo"] = CKAsset(fileURL: tempURL)

        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    /// Publishes this device's nickname + tag onto its own UserProfile
    /// record — read-modify-write so it never clobbers a photo already
    /// saved there by uploadMyPhoto. Best-effort callers (NicknamePromptView,
    /// AppRootView's startup sync) swallow errors with `try?`, same posture
    /// as every other CloudKit write here.
    static func syncHandle(nickname: String, tag: Int, previousNickname: String? = nil) async throws {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        let userId = try await CloudKitSegmentService.currentUserId()
        let recordID = profileRecordID(for: userId)

        do {
            let record = (try? await database.record(for: recordID)) ?? CKRecord(recordType: profileRecordType, recordID: recordID)
            record["nickname"] = nickname as CKRecordValue
            record["tag"] = Int64(tag) as CKRecordValue
            _ = try await database.save(record)

            // Renamed since the last sync — the old handle's lookup records
            // would otherwise keep pointing here under a name that's no
            // longer valid, so they're cleaned up before the new ones go in.
            if let previousNickname, previousNickname.lowercased() != nickname.lowercased() {
                let oldKey = handleKey(nickname: previousNickname, tag: tag)
                try? await database.deleteRecord(withID: CKRecord.ID(recordName: oldKey))
                try? await removeFromNicknameIndex(nickname: previousNickname, userId: userId)
            }

            let newKey = handleKey(nickname: nickname, tag: tag)
            let indexRecordID = CKRecord.ID(recordName: newKey)
            let indexRecord = (try? await database.record(for: indexRecordID)) ?? CKRecord(recordType: handleIndexRecordType, recordID: indexRecordID)
            indexRecord["userId"] = userId as CKRecordValue
            _ = try await database.save(indexRecord)

            try await addToNicknameIndex(nickname: nickname, tag: tag, userId: userId)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    /// Recovers this device's own nickname+tag from its already-existing
    /// UserProfile record (if any) — called at launch when local storage
    /// has no nickname yet, which is true both on a genuinely first launch
    /// (nothing to recover, returns nil) and after a delete-and-reinstall
    /// (CloudKit's own record survives, keyed by the CloudKit userId, which
    /// is tied to the iCloud account rather than local app storage).
    static func fetchMyHandle() async throws -> (nickname: String, tag: Int)? {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        let userId = try await CloudKitSegmentService.currentUserId()
        do {
            let record = try await database.record(for: profileRecordID(for: userId))
            guard let nickname = record["nickname"] as? String, let tag = record["tag"] as? Int64 else { return nil }
            return (nickname, Int(tag))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    /// Direct by-ID fetch of the HandleIndex record keyed by this exact
    /// handle — see the type's own header comment for why this replaced a
    /// CKQuery-based lookup.
    static func findUser(nickname: String, tag: Int) async throws -> String? {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        let key = handleKey(nickname: nickname, tag: tag)
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: key))
            return record["userId"] as? String
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    /// Everyone currently using this nickname (any tag) — a plain by-ID
    /// fetch of the one NicknameIndex record for it, so a friend can be
    /// found by name alone without knowing their #tag up front. More than
    /// one result means the caller needs to ask which one (show the list,
    /// let the person pick, or ask for the #tag to disambiguate).
    static func findUsers(byNickname nickname: String) async throws -> [(userId: String, tag: Int)] {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: nicknameKey(nickname)))
            let tags = record["tags"] as? [Int64] ?? []
            let userIds = record["userIds"] as? [String] ?? []
            return zip(userIds, tags).map { (userId: $0, tag: Int($1)) }
        } catch let error as CKError where error.code == .unknownItem {
            return []
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    /// Read-modify-write append, keyed by userId so re-running (e.g. the
    /// app-launch best-effort sync) doesn't duplicate this person's own
    /// entry in the list.
    private static func addToNicknameIndex(nickname: String, tag: Int, userId: String) async throws {
        let recordID = CKRecord.ID(recordName: nicknameKey(nickname))
        let record = (try? await database.record(for: recordID)) ?? CKRecord(recordType: nicknameIndexRecordType, recordID: recordID)
        var tags = record["tags"] as? [Int64] ?? []
        var userIds = record["userIds"] as? [String] ?? []
        if let existingIndex = userIds.firstIndex(of: userId) {
            tags[existingIndex] = Int64(tag)
        } else {
            tags.append(Int64(tag))
            userIds.append(userId)
        }
        record["tags"] = tags as CKRecordValue
        record["userIds"] = userIds as CKRecordValue
        _ = try await database.save(record)
    }

    private static func removeFromNicknameIndex(nickname: String, userId: String) async throws {
        let recordID = CKRecord.ID(recordName: nicknameKey(nickname))
        guard let record = try? await database.record(for: recordID) else { return }
        var tags = record["tags"] as? [Int64] ?? []
        var userIds = record["userIds"] as? [String] ?? []
        guard let index = userIds.firstIndex(of: userId) else { return }
        tags.remove(at: index)
        userIds.remove(at: index)
        record["tags"] = tags as CKRecordValue
        record["userIds"] = userIds as CKRecordValue
        _ = try await database.save(record)
    }

    /// Missing profiles (never uploaded a photo) are just left out of the
    /// result rather than treated as an error — most users won't have one.
    static func fetchPhotos(userIds: [String]) async throws -> [String: Data] {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        guard !userIds.isEmpty else { return [:] }
        let ids = userIds.map { profileRecordID(for: $0) }

        do {
            let results = try await database.records(for: ids)
            var photos: [String: Data] = [:]
            for (recordID, result) in results {
                guard case .success(let record) = result,
                      let asset = record["photo"] as? CKAsset,
                      let fileURL = asset.fileURL,
                      let data = try? Data(contentsOf: fileURL) else { continue }
                // Map back to the raw userId the caller passed in — the
                // stored record ID is "profile_<userId>", not the userId.
                photos[String(recordID.recordName.dropFirst("profile_".count))] = data
            }
            return photos
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    struct CarSyncEntry {
        var name: String
        var photoData: Data?
    }

    // CloudKit records have no "list of Asset" field type, so a bounded set
    // of indexed single-Asset fields (carPhoto0...carPhoto7) stands in for
    // an array — plenty for a real garage, and simpler than a second
    // record type per car (which would need its own by-index deterministic
    // IDs anyway, no real savings over this).
    private static let maxSyncedCars = 8

    /// Publishes this device's local driving totals + garage onto its own
    /// UserProfile record, same read-modify-write posture as syncHandle —
    /// so PublicProfileView (opened from a leaderboard row) can show a real
    /// "like my own profile" view of someone else instead of just a photo.
    /// Best-effort: called opportunistically (trip ended, Profile opened),
    /// never blocks the UI on failure.
    static func syncStats(totalDistanceMeters: Double, tripCount: Int, totalDriveTime: TimeInterval, cars: [CarSyncEntry]) async throws {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        let userId = try await CloudKitSegmentService.currentUserId()
        let recordID = profileRecordID(for: userId)
        let synced = Array(cars.prefix(maxSyncedCars))

        var tempURLs: [URL] = []
        defer { for url in tempURLs { try? FileManager.default.removeItem(at: url) } }

        do {
            let record = (try? await database.record(for: recordID)) ?? CKRecord(recordType: profileRecordType, recordID: recordID)
            record["totalDistanceMeters"] = totalDistanceMeters as CKRecordValue
            record["tripCount"] = Int64(tripCount) as CKRecordValue
            record["totalDriveTime"] = totalDriveTime as CKRecordValue
            record["carSummaries"] = synced.map(\.name) as CKRecordValue

            for index in 0..<maxSyncedCars {
                let key = "carPhoto\(index)"
                guard index < synced.count, let data = synced[index].photoData else {
                    record[key] = nil
                    continue
                }
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                try data.write(to: tempURL)
                tempURLs.append(tempURL)
                record[key] = CKAsset(fileURL: tempURL)
            }

            _ = try await database.save(record)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }

    struct ProfileStats {
        var totalDistanceMeters: Double
        var tripCount: Int
        var totalDriveTime: TimeInterval
        var carSummaries: [String]
        var carPhotos: [Data?]
    }

    /// Batch by-ID fetch, same mechanism as fetchPhotos — a user who never
    /// synced stats (or is on an older build) is just left out of the result.
    static func fetchStats(userIds: [String]) async throws -> [String: ProfileStats] {
        guard FeatureFlags.globalLeaderboardEnabled else { throw SegmentServiceError.featureNotAvailable }
        guard !userIds.isEmpty else { return [:] }
        let ids = userIds.map { profileRecordID(for: $0) }

        do {
            let results = try await database.records(for: ids)
            var stats: [String: ProfileStats] = [:]
            for (recordID, result) in results {
                guard case .success(let record) = result,
                      let totalDistanceMeters = record["totalDistanceMeters"] as? Double else { continue }
                let carPhotos: [Data?] = (0..<maxSyncedCars).map { index in
                    guard let asset = record["carPhoto\(index)"] as? CKAsset,
                          let fileURL = asset.fileURL else { return nil }
                    return try? Data(contentsOf: fileURL)
                }
                // Map back to the raw userId — see fetchPhotos' same fix.
                stats[String(recordID.recordName.dropFirst("profile_".count))] = ProfileStats(
                    totalDistanceMeters: totalDistanceMeters,
                    tripCount: (record["tripCount"] as? Int64).map(Int.init) ?? 0,
                    totalDriveTime: record["totalDriveTime"] as? Double ?? 0,
                    carSummaries: record["carSummaries"] as? [String] ?? [],
                    carPhotos: carPhotos
                )
            }
            return stats
        } catch let error as CKError where error.code == .notAuthenticated {
            throw SegmentServiceError.notSignedIntoiCloud
        } catch {
            throw SegmentServiceError.underlying(error)
        }
    }
}
