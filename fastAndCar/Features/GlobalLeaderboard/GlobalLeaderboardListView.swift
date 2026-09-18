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
import SwiftUI

struct GlobalLeaderboardListView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    var onFollowSegment: (Segment) -> Void
    @State private var myCreatedSegmentsStore = MyCreatedSegmentsStore()
    @State private var searchText = ""
    @State private var searchResults: [Segment] = []
    @State private var isSearching = false
    @State private var nearbySegments: [Segment] = []
    @State private var isLoadingNearby = false
    @State private var didLoadNearby = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Yakınımdakiler")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)

                        if isLoadingNearby {
                            ProgressView().tint(AppColor.accent)
                        } else if didLoadNearby && nearbySegments.isEmpty {
                            Text("Yakınında parkur bulunamadı")
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
                                    SegmentRow(name: segment.name, subtitle: String(format: "%.1f km", segment.lengthMeters / 1000))
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

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Parkur Ara")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)

                        if isSearching {
                            ProgressView().tint(AppColor.accent)
                        } else if !searchText.trimmingCharacters(in: .whitespaces).isEmpty && searchResults.isEmpty {
                            Text("Sonuç bulunamadı")
                                .font(AppFont.body)
                                .foregroundStyle(AppColor.textSecondary)
                        } else {
                            ForEach(searchResults) { segment in
                                NavigationLink(value: segment) {
                                    SegmentRow(name: segment.name, subtitle: String(format: "%.1f km", segment.lengthMeters / 1000))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if myCreatedSegmentsStore.segments.isEmpty && nearbySegments.isEmpty && searchResults.isEmpty && searchText.isEmpty && didLoadNearby {
                        emptyState
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Global Liderlik")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Parkur adı")
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

    /// Best-effort and silent on failure — if the feature isn't active yet
    /// or the device has no location fix handy, the section just shows its
    /// empty state rather than an alert every time this tab opens.
    private func loadNearby() async {
        isLoadingNearby = true
        defer {
            isLoadingNearby = false
            didLoadNearby = true
        }
        guard let coordinate = await currentCoordinate() else { return }
        nearbySegments = (try? await CloudKitSegmentService.fetchNearbySegments(candidateGeohashes: Geohash.nearbyCells(around: coordinate))) ?? []
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
            errorMessage = "Bu özellik yakında aktif olacak."
        } catch {
            errorMessage = "Parkur yüklenemedi."
        }
    }
}
