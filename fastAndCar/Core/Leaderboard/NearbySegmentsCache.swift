//
//  NearbySegmentsCache.swift
//  fastAndCar
//
//  In-memory cache of GlobalLeaderboardListView's "Yakınımdakiler" result —
//  without this, switching to Ana Sayfa and back to the Global tab tore
//  down and recreated the view, resetting its own @State back to empty and
//  re-running the whole nearby fetch from scratch every single time
//  (confirmed live: a slow-ish fetch repeated on every tab revisit read as
//  "kayıt etmiyor, sürekli yükleniyor"). A short freshness window is enough
//  to fix the actual complaint (quick back-and-forth tab switching) without
//  ever showing meaningfully stale data — same "don't refetch what's still
//  good" instinct as DashboardView's discoveredSegmentsById.
//

import Foundation

@Observable
final class NearbySegmentsCache {
    static let shared = NearbySegmentsCache()
    private init() {}

    private(set) var segments: [Segment] = []
    private var fetchedAt: Date?
    private var fetchedRadius: NearbySearchRadius?

    private let freshnessWindow: TimeInterval = 300

    func isFresh(radius: NearbySearchRadius) -> Bool {
        guard let fetchedAt, fetchedRadius == radius else { return false }
        return Date().timeIntervalSince(fetchedAt) < freshnessWindow
    }

    func store(_ segments: [Segment], radius: NearbySearchRadius) {
        self.segments = segments
        self.fetchedAt = Date()
        self.fetchedRadius = radius
    }
}
