//
//  CrewZoneRef.swift
//  fastAndCar
//
//  Every Crew lives in its own CKRecordZone (CKShare requires a custom zone,
//  not the default one) — this is the little bit of routing information
//  needed to find that zone again: the private database if this device
//  owns the crew, the shared database plus the owner's user record name
//  otherwise. Cached locally (see MyCrewsStore) so reading/writing a crew's
//  records never needs an extra round trip just to figure out where they live.
//

import CloudKit
import Foundation

struct CrewZoneRef: Codable, Equatable, Hashable {
    let zoneName: String
    /// nil when this device is the crew's creator (zone lives in
    /// CKContainer.default().privateCloudDatabase); set to the owner's
    /// CKRecord.ID.recordName when this device joined as a participant
    /// (zone is read via .sharedCloudDatabase instead).
    let ownerName: String?

    var isOwnedByThisDevice: Bool { ownerName == nil }

    var database: CKDatabase {
        isOwnedByThisDevice ? CKContainer.default().privateCloudDatabase : CKContainer.default().sharedCloudDatabase
    }

    var zoneID: CKRecordZone.ID {
        if let ownerName {
            return CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        }
        return CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }
}
