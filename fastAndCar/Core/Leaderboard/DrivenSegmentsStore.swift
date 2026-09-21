//
//  DrivenSegmentsStore.swift
//  fastAndCar
//
//  A segment someone else created only shows up in "Yakınımdakiler" while
//  you're actually near it — drive it once, drive away, and it vanished
//  from the list with no way back to it. This is the same pragmatic
//  local-cache pattern as MyCreatedSegmentsStore, just recording "segments
//  I've successfully submitted an effort for" instead of "segments I
//  created", so SegmentAutoMatcher can give the Global Leaderboard tab a
//  persistent "Sürdüklerim" list.
//

import Foundation
import Observation

struct DrivenSegmentRef: Codable, Identifiable, Equatable {
    let id: String
    let name: String
}

@Observable
final class DrivenSegmentsStore {
    private static let key = "drivenSegments"

    private(set) var segments: [DrivenSegmentRef]

    init() {
        segments = Self.load()
    }

    /// No-op if already recorded — a segment driven twice shouldn't
    /// duplicate in the list, just keep its original (first-drive) spot.
    func record(id: String, name: String) {
        guard !segments.contains(where: { $0.id == id }) else { return }
        segments.insert(DrivenSegmentRef(id: id, name: name), at: 0)
        save()
    }

    func remove(_ id: String) {
        segments.removeAll { $0.id == id }
        save()
    }

    private static func load() -> [DrivenSegmentRef] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DrivenSegmentRef].self, from: data) else { return [] }
        return decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(segments) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
