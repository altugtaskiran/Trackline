//
//  LocalRoutesStore.swift
//  fastAndCar
//
//  "Rotalar" tab's actual data: routes made from the user's own saved
//  drives, kept locally so the whole create → drive-again loop works today
//  regardless of whether CloudKit is active — sharing a route publicly
//  (via CloudKitSegmentService, once FeatureFlags.globalLeaderboardEnabled
//  flips on) is an *additional* step for a route already saved here, never
//  a requirement for using it yourself.
//

import Foundation
import Observation

@Observable
final class LocalRoutesStore {
    private static let key = "localRoutes"

    private(set) var routes: [Segment]

    init() {
        routes = Self.load()
    }

    func add(_ segment: Segment) {
        routes.removeAll { $0.id == segment.id }
        routes.insert(segment, at: 0)
        save()
    }

    func remove(_ segmentId: String) {
        routes.removeAll { $0.id == segmentId }
        save()
    }

    private static func load() -> [Segment] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Segment].self, from: data) else { return [] }
        return decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(routes) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
