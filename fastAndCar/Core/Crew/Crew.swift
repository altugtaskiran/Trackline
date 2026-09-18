//
//  Crew.swift
//  fastAndCar
//
//  A small private group that compares completed drives — no live location
//  sharing, just post-drive summaries. Backed by a CKShare so members are
//  invited the normal iOS way (Messages/Mail/copy link), not a join code.
//

import Foundation

struct Crew: Identifiable, Codable {
    let id: String
    var name: String
    var creatorId: String
    var creatorNickname: String
    var createdAt: Date
}
