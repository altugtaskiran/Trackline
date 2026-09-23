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
    @AppStorage("nearbySearchRadiusKm") private var nearbySearchRadiusKm: NearbySearchRadius = .km100

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
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Yakınında (\(nearbySearchRadiusKm.label) içinde) parkur bulunamadı")
                                    .font(AppFont.body)
                                    .foregroundStyle(AppColor.textSecondary)
                                if nearbySearchRadiusKm != .km100 {
                                    Text("Ayarlar'dan arama mesafesini artırabilirsin.")
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppColor.accent)
                                }
                            }
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
        .task(id: nearbySearchRadiusKm) { await loadNearby() }
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
    /// failure as "found nothing" — a "no route nearby" empty state and an
    /// actual query failure (missing Production index on geohashesCoarse,
    /// permissions, query too complex) used to look identical, which made
    /// a genuine bug here indistinguishable from there just being no
    /// nearby routes (confirmed live: a brand-new route, created on one
    /// device, wasn't found from a second device/account at all). A
    /// missing location fix still fails silently — that's routine, not a
    /// bug worth an alert every time this tab opens.
    private func loadNearby() async {
        isLoadingNearby = true
        defer {
            isLoadingNearby = false
            didLoadNearby = true
        }
        guard let coordinate = await currentCoordinate() else { return }
        let radiusMeters = nearbySearchRadiusKm.meters
        // Back to the geohashesCoarse-free path: a route that genuinely
        // exists in the database, created moments ago, still wasn't
        // showing up here even right next to it (confirmed live) — the
        // coarse geohash predicate this used to run
        // (fetchNearbySegmentsWide, "ANY geohashesCoarse IN %@") depends
        // on that field having a Queryable index actually deployed to
        // CloudKit's PRODUCTION environment specifically, which this
        // session's whole history (LiveLocation, SegmentEffort.userId —
        // every one of these needed a manual Console index + explicit
        // "Deploy Schema Changes to Production" before it worked from a
        // real device/TestFlight) makes very likely to be the real cause
        // here too, rather than anything about the 200km radius itself.
        // fetchSegments(within:of:) has no such dependency at all — it
        // fetches every public Segment and filters by real distance
        // client-side, so it's correct regardless of index state. Costs
        // more per call, but is fine at today's segment count, and
        // correctness beats a premature optimization that's currently
        // broken. Revisit once there's a confirmed-working index and/or
        // enough segments that fetching all of them stops being cheap.
        var fetched: [Segment] = []
        do {
            fetched = try await CloudKitSegmentService.fetchSegments(within: radiusMeters, of: coordinate)
        } catch SegmentServiceError.featureNotAvailable {
            // Expected right now if the build has the flag off — not a bug.
        } catch {
            errorMessage = error.localizedDescription
        }
        // My own routes already live in "Oluşturduklarım" just below —
        // showing them here too just duplicated them under a section meant
        // for discovering *other* people's routes.
        let myUserId = try? await CloudKitSegmentService.currentUserId()
        let userLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        nearbySegments = fetched.filter { segment in
            guard segment.creatorId != myUserId else { return false }
            let segmentCenter = CLLocation(
                latitude: (segment.minLatitude + segment.maxLatitude) / 2,
                longitude: (segment.minLongitude + segment.maxLongitude) / 2
            )
            return userLocation.distance(from: segmentCenter) <= radiusMeters
        }
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
