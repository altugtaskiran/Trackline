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

import CoreLocation
import Foundation
import MapKit

@Observable
final class NearbySegmentsCache {
    static let shared = NearbySegmentsCache()
    private init() {}

    private(set) var segments: [Segment] = []
    private var fetchedAt: Date?

    private let freshnessWindow: TimeInterval = 300
    // Same fixed radius GlobalLeaderboardListView shows — a single sane
    // default, not user-adjustable (see that view's own comment on why).
    static let nearbyRadiusMeters: Double = 50_000

    var isFresh: Bool {
        guard let fetchedAt else { return false }
        return Date().timeIntervalSince(fetchedAt) < freshnessWindow
    }

    func store(_ segments: [Segment]) {
        self.segments = segments
        self.fetchedAt = Date()
    }

    /// The actual network fetch behind "Yakınımdakiler" — pulled out of
    /// GlobalLeaderboardListView so AppRootView can warm this cache once at
    /// launch (before the user ever opens the Global tab), instead of the
    /// tab's own first visit always eating the full CloudKit round-trip.
    /// Same primary-indexed-query + fallback-full-scan posture as before.
    @discardableResult
    static func fetchAndCache(around coordinate: CLLocationCoordinate2D) async throws -> [Segment] {
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = 111_320.0 * cos(coordinate.latitude * .pi / 180)
        let searchRegion = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: (nearbyRadiusMeters * 1.3) / metersPerDegreeLatitude,
                longitudeDelta: (nearbyRadiusMeters * 1.3) / max(metersPerDegreeLongitude, 1)
            )
        )
        let cells = Geohash.cells(covering: searchRegion, precision: Geohash.coarsePrecision, maxCells: 150) ?? []

        let userLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var fetched: [Segment] = []
        do {
            let candidates = try await CloudKitSegmentService.fetchNearbySegmentsWide(candidateCoarseGeohashes: cells, limit: 60)
            fetched = candidates.filter { segment in
                let segmentCenter = CLLocation(
                    latitude: (segment.minLatitude + segment.maxLatitude) / 2,
                    longitude: (segment.minLongitude + segment.maxLongitude) / 2
                )
                return userLocation.distance(from: segmentCenter) <= nearbyRadiusMeters
            }
        } catch SegmentServiceError.featureNotAvailable {
            return []
        } catch {
            // Safety net: fall back to the guaranteed-correct
            // fetch-all-and-filter path rather than surfacing an error for
            // what might just be a transient query hiccup.
            fetched = try await CloudKitSegmentService.fetchSegments(within: nearbyRadiusMeters, of: coordinate)
        }
        shared.store(fetched)
        return fetched
    }
}
