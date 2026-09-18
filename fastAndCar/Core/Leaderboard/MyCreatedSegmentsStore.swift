//
//  MyCreatedSegmentsStore.swift
//  fastAndCar
//
//  CloudKit's public database has no cheap "segments created by me" query
//  without a custom queryable index, so the Global Leaderboard tab's own
//  "Oluşturduklarım" list is just a small locally-cached id+name list,
//  updated the moment a segment is created — same pragmatic local-cache
//  pattern as NicknameStore.
//

import Foundation
import Observation

struct MyCreatedSegmentRef: Codable, Identifiable, Equatable {
    let id: String
    let name: String
}

@Observable
final class MyCreatedSegmentsStore {
    private static let key = "myCreatedSegments"

    private(set) var segments: [MyCreatedSegmentRef]

    init() {
        segments = Self.load()
    }

    func record(id: String, name: String) {
        segments.insert(MyCreatedSegmentRef(id: id, name: name), at: 0)
        save()
    }

    private static func load() -> [MyCreatedSegmentRef] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([MyCreatedSegmentRef].self, from: data) else { return [] }
        return decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(segments) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
