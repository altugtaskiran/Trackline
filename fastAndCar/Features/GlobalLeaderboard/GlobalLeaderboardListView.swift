//
//  GlobalLeaderboardListView.swift
//  fastAndCar
//
//  Discover tab: a live-location "nearby" browse first (the actual
//  discovery path most people will use), segments the user has created
//  (cached locally — see MyCreatedSegmentsStore), then a name search
//  against the public database for everyone else's.
//

import CoreLocation
import MapKit
import SwiftUI

struct GlobalLeaderboardListView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    var onFollowSegment: (Segment) -> Void
    @State private var myCreatedSegmentsStore = MyCreatedSegmentsStore()
    @State private var drivenSegmentsStore = DrivenSegmentsStore()
    @State private var searchText = ""
    @State private var searchResults: [Segment] = []
    @State private var isSearching = false
    @State private var nearbySegments: [Segment] = []
    @State private var isLoadingNearby = false
    @State private var didLoadNearby = false
    @State private var errorMessage: String?
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.systemDefault.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .systemDefault }
    // Fixed, not user-configurable — a wider adjustable radius (up to
    // 200km) was the whole reason this search ever needed a huge
    // candidate-cell predicate in the first place. A single sane default
    // removes that failure mode entirely instead of just shrinking it.
    private let nearbyRadiusMeters: Double = 50_000

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !FeatureFlags.globalLeaderboardEnabled {
                        FeatureUnavailableView(
                            title: "Global Liderlik",
                            message: "Yakınımdakiler, Parkur Ara ve herkese açık parkurlar yakında aktif olacak."
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Yakınımdakiler")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)

                        if isLoadingNearby {
                            ProgressView().tint(AppColor.accent)
                        } else if didLoadNearby && nearbySegments.isEmpty {
                            Text("Yakınında (50 km içinde) parkur bulunamadı")
                                .font(AppFont.body)
                                .foregroundStyle(AppColor.textSecondary)
                        } else {
                            ForEach(nearbySegments) { segment in
                                // Pushed onto AppRootView's single shared
                                // NavigationStack (see .navigationDestination
                                // (for: Segment.self) there), not a
                                // NavigationStack owned by this view — a
                                // nested stack's push isn't reliably torn
                                // down just because Liderlik's own tab
                                // switches away from it.
                                NavigationLink(value: segment) {
                                    SegmentRow(name: segment.name, subtitle: distanceUnit.distanceString(meters: segment.lengthMeters))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !myCreatedSegmentsStore.segments.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Oluşturduklarım")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)
                            ForEach(myCreatedSegmentsStore.segments) { ref in
                                NavigationLink(value: ref.id) {
                                    SegmentRow(name: ref.name, subtitle: "Parkurunu görüntüle")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // A segment someone else created only surfaces in
                    // Yakınımdakiler while you're physically near it —
                    // without this, driving away lost your only way back to
                    // a route you'd already raced.
                    if !drivenSegmentsStore.segments.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Sürdüklerim")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)
                            ForEach(drivenSegmentsStore.segments) { ref in
                                NavigationLink(value: ref.id) {
                                    SegmentRow(name: ref.name, subtitle: "Parkurunu görüntüle")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Parkur Ara")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)

                        // A manual field, not .searchable — .searchable
                        // attaches its system search bar to the single
                        // NavigationStack AppRootView shares across every
                        // tab, so its (unstyled, light) chrome kept bleeding
                        // through as a stray white bar at the bottom of
                        // other tabs (Dashboard while recording, notably)
                        // even after switching away from Liderlik.
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(AppColor.textSecondary)
                            TextField("Parkur adı", text: $searchText)
                                .foregroundStyle(AppColor.textPrimary)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColor.surfaceElevated))

                        if isSearching {
                            ProgressView().tint(AppColor.accent)
                        } else if !searchText.trimmingCharacters(in: .whitespaces).isEmpty && searchResults.isEmpty {
                            Text("Sonuç bulunamadı")
                                .font(AppFont.body)
                                .foregroundStyle(AppColor.textSecondary)
                        } else {
                            ForEach(searchResults) { segment in
                                NavigationLink(value: segment) {
                                    SegmentRow(name: segment.name, subtitle: distanceUnit.distanceString(meters: segment.lengthMeters))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if myCreatedSegmentsStore.segments.isEmpty && drivenSegmentsStore.segments.isEmpty && nearbySegments.isEmpty && searchResults.isEmpty && searchText.isEmpty && didLoadNearby {
                        emptyState
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Global Liderlik")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: searchText) { _, newValue in
            search(for: newValue)
        }
        .task { await loadNearby() }
        .alert(
            "Bir Sorun Oluştu",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("Tamam") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "ruler")
                .font(.system(size: 36))
                .foregroundStyle(AppColor.textTertiary)
            Text("Henüz parkur yok")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Bir sürüş detayında rotandan bir parkur oluştur, ya da yukarıdan ara.")
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.top, 60)
    }

    /// Surfaces real CloudKit errors instead of silently treating any
    /// failure as "found nothing" — a missing location fix still fails
    /// silently (that's routine), but a genuine query error is now shown
    /// rather than looking identical to "no routes nearby".
    private func loadNearby() async {
        // Switching to Ana Sayfa and back tore this view down and rebuilt
        // it, resetting nearbySegments/didLoadNearby back to empty and
        // re-running this whole fetch every single time — confirmed live,
        // read as "sürekli yükleniyor, kaydetmiyor". A short-lived shared
        // cache means quick tab back-and-forth reuses the last result
        // instantly instead of refetching.
        if NearbySegmentsCache.shared.isFresh {
            await applyFetchedSegments(NearbySegmentsCache.shared.segments)
            didLoadNearby = true
            return
        }
        isLoadingNearby = true
        defer {
            isLoadingNearby = false
            didLoadNearby = true
        }
        guard let coordinate = await currentCoordinate() else { return }

        // Primary path: the indexed geohashesCoarse query — confirmed via
        // CloudKit Console that this field actually has a deployed
        // Queryable index in Production, so the earlier "can't find a
        // route that's right there" bug wasn't a missing index after all;
        // it was almost certainly the old candidate-cell predicate being
        // far too large (a fixed 50km radius keeps that grid small and
        // fast — no user-adjustable 200km option to blow it back up).
        // Server-side filtering here means the phone only ever downloads
        // matches, which is what actually scales to a large route count,
        // unlike fetching every public Segment.
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
            // The 1.3x padding above means the candidate cells cover a bit
            // more than the true 50km circle — this re-applies the exact
            // radius the same way fetchSegments(within:of:) does.
            fetched = candidates.filter { segment in
                let segmentCenter = CLLocation(
                    latitude: (segment.minLatitude + segment.maxLatitude) / 2,
                    longitude: (segment.minLongitude + segment.maxLongitude) / 2
                )
                return userLocation.distance(from: segmentCenter) <= nearbyRadiusMeters
            }
            NearbySegmentsCache.shared.store(fetched)
        } catch SegmentServiceError.featureNotAvailable {
            // Expected right now if the build has the flag off — not a bug.
        } catch {
            // Safety net: the indexed query genuinely failed (not just
            // "found nothing") — fall back to the guaranteed-correct
            // fetch-all-and-filter path rather than showing an error for
            // something that might just be a transient query hiccup.
            // Costs more per call, but only runs when the fast path
            // actually breaks.
            do {
                fetched = try await CloudKitSegmentService.fetchSegments(within: nearbyRadiusMeters, of: coordinate)
                NearbySegmentsCache.shared.store(fetched)
            } catch SegmentServiceError.featureNotAvailable {
                // Expected right now if the build has the flag off.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        await applyFetchedSegments(fetched)
    }

    /// fetchSegments(within:of:) already filters to the real radius before
    /// returning — the only thing left to do here (both for a fresh fetch
    /// and for a cache hit, which has no coordinate handy to re-filter
    /// with anyway) is drop the caller's own routes, which already live in
    /// "Oluşturduklarım" just below and would otherwise just be duplicated
    /// under a section meant for discovering *other* people's routes.
    private func applyFetchedSegments(_ fetched: [Segment]) async {
        let myUserId = try? await CloudKitSegmentService.currentUserId()
        nearbySegments = fetched.filter { $0.creatorId != myUserId }
    }

    private func currentCoordinate() async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { continuation in
            appEnvironment.locationManager.requestOneShotLocation { coordinate in
                continuation.resume(returning: coordinate)
            }
        }
    }

    private func search(for text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        Task {
            defer { isSearching = false }
            do {
                searchResults = try await CloudKitSegmentService.searchSegments(nameContains: text)
            } catch SegmentServiceError.featureNotAvailable {
                // Expected right now (CloudKit gated off) — fires on every
                // keystroke via onChange(of: searchText), so surfacing it as
                // a blocking alert here would mean one alert per character
                // typed. Empty results is enough.
                searchResults = []
            } catch {
                searchResults = []
            }
        }
    }
}

/// The "Oluşturduklarım" list only has the segment's id+name cached locally
/// (see MyCreatedSegmentsStore) — this fetches the full Segment (polyline,
/// tolerance, etc.) from CloudKit before handing off to SegmentDetailView,
/// which needs the whole thing to draw the route preview. Referenced from
/// AppRootView's own navigationDestination(for: String.self), so not
/// private to this file.
struct SegmentDetailLoaderView: View {
    let segmentId: String
    var onFollowSegment: (Segment) -> Void

    @State private var segment: Segment?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let segment {
                SegmentDetailView(segment: segment, onFollowSegment: onFollowSegment)
            } else if !FeatureFlags.globalLeaderboardEnabled {
                // No local fallback for this one — this loader exists only
                // to fetch a Segment CloudKit hasn't cached locally, so
                // there's genuinely nothing to show without it. A calm
                // empty state instead of a spinner that would otherwise
                // never resolve, and no alert since nothing went wrong.
                ZStack {
                    AppColor.background.ignoresSafeArea()
                    FeatureUnavailableView()
                }
            } else {
                ZStack {
                    AppColor.background.ignoresSafeArea()
                    ProgressView().tint(AppColor.accent)
                }
                .task { await load() }
            }
        }
        .alert(
            "Bir Sorun Oluştu",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("Tamam") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() async {
        do {
            segment = try await CloudKitSegmentService.fetchSegment(id: segmentId)
        } catch SegmentServiceError.featureNotAvailable {
            // Guarded above — shouldn't reach here, but keep it silent for
            // the same reason rather than surfacing an alert.
        } catch {
            errorMessage = "Parkur yüklenemedi."
        }
    }
}
