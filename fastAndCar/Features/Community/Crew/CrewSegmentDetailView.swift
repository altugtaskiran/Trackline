//
//  CrewSegmentDetailView.swift
//  fastAndCar
//
//  A crew's own version of SegmentDetailView — route preview + "Bu Rotayı
//  Sür" + a ranked leaderboard, just scoped to the crew's private zone
//  (CloudKitCrewService.fetchSegmentLeaderboard) instead of the public
//  Global Leaderboard. No voting — that's a public-discovery concept, a
//  crew already knows who made the route.
//

import CoreLocation
import SwiftUI

struct CrewSegmentDetailView: View {
    let segment: Segment
    let crewId: String
    let zoneRef: CrewZoneRef
    var onFollowSegment: (Segment, String, CrewZoneRef) -> Void

    @State private var entries: [SegmentEffort] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var photoCache = ProfilePhotoCache.shared
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.systemDefault.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .systemDefault }

    private var previewSamples: [LocationSample] {
        segment.polyline.enumerated().map { index, point in
            LocationSample(
                coordinate: CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon),
                timestamp: Date(timeIntervalSince1970: Double(index)),
                speedMps: 0,
                altitude: 0,
                heading: nil,
                horizontalAccuracy: 0
            )
        }
    }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    GeometryReader { proxy in
                        let rect = CGRect(origin: .zero, size: proxy.size)
                        let region = FittedRegion.fitting(samples: previewSamples, aspectRatio: rect.width / max(rect.height, 1))
                        let projector = GeoMapProjector.projector(region: region)
                        ZStack {
                            RouteMapBackdrop(region: region)
                            RouteCanvas(samples: previewSamples, lineWidth: 3, showsEndpoints: true, padding: 20, projector: projector)
                        }
                    }
                    .frame(height: 200)
                    .glassCard(cornerRadius: 22, padding: 0)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(distanceUnit.distanceString(meters: segment.lengthMeters))
                                .font(AppFont.statValue(16))
                                .foregroundStyle(AppColor.textPrimary)
                            Text("Paylaşan: \(segment.creatorNickname)")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        onFollowSegment(segment, crewId, zoneRef)
                    } label: {
                        Label("Bu Rotayı Sür", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                    .buttonStyle(.glass(.accent))

                    if isLoading {
                        ProgressView().tint(AppColor.accent).padding(.top, 40)
                    } else if entries.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                SegmentEffortRow(rank: index + 1, effort: entry, avatar: photoCache.image(for: entry.userId))
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(segment.name)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await load() }
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
            Image(systemName: "flag.checkered")
                .font(.system(size: 36))
                .foregroundStyle(AppColor.textTertiary)
            Text("Bu rotada henüz kimse yok")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Bu rotayı sür, otomatik olarak crew liderlik tablosuna gönderilsin.")
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.top, 60)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await CloudKitCrewService.fetchSegmentLeaderboard(segmentId: segment.id, zoneRef: zoneRef)
            await photoCache.prefetch(userIds: entries.map(\.userId))
        } catch CrewServiceError.featureNotAvailable {
            // Same as SegmentDetailView — not a real error, falls through
            // to the empty state instead of a blocking alert.
        } catch {
            errorMessage = "Liderlik tablosu yüklenemedi. Bağlantını kontrol edip tekrar dene."
        }
    }
}
