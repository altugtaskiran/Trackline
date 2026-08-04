//
//  CloudKitLeaderboardService.swift
//  fastAndCar
//
//  Public-database CloudKit access for the route-segment leaderboard.
//  Requires the iCloud/CloudKit capability + entitlement (Config/fastAndCar.entitlements)
//  and a signed-in iCloud account to actually read/write — on a machine
//  without an interactive iCloud sign-in available, this compiles and runs
//  its local logic correctly, but real read/write round-trips need
//  verification on a real device signed into iCloud.
//

import CloudKit
import Foundation

enum LeaderboardServiceError: Error {
    case notSignedIntoiCloud
    case underlying(Error)
}

enum CloudKitLeaderboardService {
    private static let recordType = "LeaderboardEntry"
    private static var database: CKDatabase { CKContainer.default().publicCloudDatabase }

    static func submit(trip: Trip, segmentKey: String, nickname: String) async throws {
        let record = CKRecord(recordType: recordType)
        record["segmentKey"] = segmentKey as CKRecordValue
        record["nickname"] = nickname as CKRecordValue
        record["topSpeedKph"] = trip.topSpeedKph as CKRecordValue
        record["averageSpeedKph"] = trip.averageSpeedKph as CKRecordValue
        record["driveTime"] = trip.driveTime as CKRecordValue
        record["distanceMeters"] = trip.distanceMeters as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        if let polylineData = LeaderboardPolylineCodec.encode(samples: trip.samples) {
            record["polyline"] = polylineData as CKRecordValue
        }

        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw LeaderboardServiceError.notSignedIntoiCloud
        } catch {
            throw LeaderboardServiceError.underlying(error)
        }
    }

    static func fetchLeaderboard(segmentKey: String) async throws -> [LeaderboardEntry] {
        let predicate = NSPredicate(format: "segmentKey == %@", segmentKey)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "topSpeedKph", ascending: false)]

        do {
            let (matchResults, _) = try await database.records(matching: query)
            return matchResults.compactMap { _, result in
                guard case .success(let record) = result else { return nil }
                return map(record)
            }
        } catch let error as CKError where error.code == .notAuthenticated {
            throw LeaderboardServiceError.notSignedIntoiCloud
        } catch {
            throw LeaderboardServiceError.underlying(error)
        }
    }

    private static func map(_ record: CKRecord) -> LeaderboardEntry? {
        guard let nickname = record["nickname"] as? String,
              let topSpeedKph = record["topSpeedKph"] as? Double,
              let averageSpeedKph = record["averageSpeedKph"] as? Double,
              let driveTime = record["driveTime"] as? Double,
              let distanceMeters = record["distanceMeters"] as? Double,
              let createdAt = record["createdAt"] as? Date else { return nil }

        let polyline = (record["polyline"] as? Data).map(LeaderboardPolylineCodec.decode) ?? []

        return LeaderboardEntry(
            id: record.recordID.recordName,
            nickname: nickname,
            topSpeedKph: topSpeedKph,
            averageSpeedKph: averageSpeedKph,
            driveTime: driveTime,
            distanceMeters: distanceMeters,
            polyline: polyline,
            createdAt: createdAt
        )
    }
}
