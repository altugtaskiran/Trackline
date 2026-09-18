//
//  CrewMembership.swift
//  fastAndCar
//
//  One participant's presence in a Crew — CloudKit's own CKShare
//  participant list already tracks *who* has access, but not their chosen
//  nickname, so this record is what CrewDetailView actually reads to label
//  rows and build the roster.
//

import Foundation

struct CrewMembership: Identifiable, Codable {
    let id: String
    var crewId: String
    var userId: String
    var nickname: String
    var joinedAt: Date
}
