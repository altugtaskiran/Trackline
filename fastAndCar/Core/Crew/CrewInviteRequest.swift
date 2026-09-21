//
//  CrewInviteRequest.swift
//  fastAndCar
//
//  A pending "join my crew" request addressed to a specific user by their
//  CloudKit userId — the name-search alternative to handing out a raw
//  CKShare link/QR. Lives in the public database (not the crew's own
//  private zone) since the target isn't a member yet and can't read that
//  zone; the actual CKShare.url travels inside this record so accepting it
//  can fetch share metadata purely through the CloudKit API
//  (CKFetchShareMetadataOperation), never through iOS's system share-link
//  handoff — which is what's unreliable for an app that isn't on the App
//  Store yet.
//

import Foundation

struct CrewInviteRequest: Identifiable, Codable, Equatable {
    let id: String
    var crewId: String
    var crewName: String
    var shareURL: String
    var fromNickname: String
    var targetUserId: String
    var createdAt: Date
}
